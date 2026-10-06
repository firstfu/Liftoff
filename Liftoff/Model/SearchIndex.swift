//
//  SearchIndex.swift
//  Liftoff
//
//  App 搜尋：支援完整名稱、字首、單字字首縮寫（vsc → Visual Studio Code）、中文名稱的拼音與拼音首字母、
//  子字串與模糊子序列比對。所有正規化在建索引時一次做完，並轉成 Unicode scalar 整數陣列；
//  查詢只做整數陣列比對。為什麼不直接比 String：Foundation 的 `range(of:)` 每次呼叫都要做泛型型別查找，
//  Time Profiler 量到每鍵約 0.5ms 幾乎都花在這裡；比陣列不到它的十分之一。
//  另有 WindowSearchIndex：執行中視窗的標題，規則較嚴（標題長，模糊比對幾乎什麼都對得上）。
//

import Foundation

nonisolated struct SearchIndex: Sendable {
    /// 正規化後的字串，以 Unicode scalar 值表示（已 NFC 組合，與 Character 比對結果一致）
    typealias Scalars = [UInt32]

    struct Key: Sendable {
        /// 正規化後的完整字串（小寫、去重音、全形轉半形）
        let text: Scalars
        /// 去掉空白與符號的連寫版本（"visual studio code" → "visualstudiocode"）
        let compact: Scalars
        /// 各單字（含 camelCase 切分）
        let words: [Scalars]
        /// 單字字首縮寫
        let initials: Scalars
        /// 權重：主要名稱 1.0，其他名稱略低
        let weight: Double
        /// `text`／`compact` 的字元（Character）數：分數裡的長度差以字元計，emoji 等一個字元會含多個 scalar
        let textLength: Int
        let compactLength: Int
    }

    /// 正規化後的查詢（每次按鍵只做一次）。
    struct Query: Sendable {
        /// 完整查詢
        let text: Scalars
        /// 去掉空白的查詢
        let compact: Scalars
        /// 字元（Character）數
        let textLength: Int
        let compactLength: Int

        /// - Parameter raw: 使用者輸入
        init(_ raw: String) {
            let q = SearchIndex.normalize(raw)
            let compactString = String(q.filter { !$0.isWhitespace })
            text = SearchIndex.scalars(q)
            compact = SearchIndex.scalars(compactString)
            textLength = q.count
            compactLength = compactString.count
        }

        var isEmpty: Bool { text.isEmpty }
    }

    private struct Entry: Sendable {
        let id: String
        let keys: [Key]
    }

    private let entries: [Entry]

    init(apps: [AppEntry]) {
        entries = apps.map { app in
            var keys: [Key] = [Self.makeKey(app.name, weight: 1.0)]
            for alt in app.altNames { keys.append(Self.makeKey(alt, weight: 0.95)) }
            // 中文名稱加上拼音（「計算機」→ ji suan ji / jsj），讓用英文鍵盤也能快速找到（拼音在掃描時已算好）
            if let latin = app.latin {
                keys.append(Self.makeKey(latin, weight: 0.9))
            }
            return Entry(id: app.id, keys: keys)
        }
    }

    /// 查詢並依相關度排序。
    /// - Parameters:
    ///   - query: 使用者輸入
    ///   - boost: 依使用頻率給的加權（App 識別鍵 → 0…1），分數相同時常用的排前面
    /// - Returns: 相符 App 的識別鍵，最相關的在前
    func search(_ query: String, boost: [String: Double] = [:]) -> [String] {
        scored(query, boost: boost).map(\.id)
    }

    /// 查詢並回傳分數（與視窗結果合併排序用）。
    /// - Parameters:
    ///   - query: 使用者輸入
    ///   - boost: 依使用頻率給的加權
    /// - Returns: (App 識別鍵, 分數)，分數高的在前
    func scored(_ query: String, boost: [String: Double] = [:]) -> [(id: String, score: Double)] {
        let q = Query(query)
        guard !q.isEmpty else { return [] }

        var scored: [(id: String, score: Double)] = []
        for entry in entries {
            var best = 0.0
            for key in entry.keys {
                let score = Self.score(q, key: key) * key.weight
                if score > best { best = score }
            }
            if best > 0 {
                scored.append((entry.id, best + (boost[entry.id] ?? 0) * 40))
            }
        }
        scored.sort { $0.score > $1.score }
        return scored
    }

    // MARK: - 計分

    /// 計算查詢與一個名稱的相符分數（未乘權重）。規則由嚴到寬，取第一個成立的。
    /// - Parameters:
    ///   - q: 正規化後的查詢
    ///   - key: 名稱索引
    /// - Returns: 0（不相符）或 100…1000
    static func score(_ q: Query, key: Key) -> Double {
        if key.text == q.text || key.compact == q.compact { return 1000 }
        if key.text.starts(with: q.text) { return 900 - Double(min(key.textLength - q.textLength, 50)) }
        if key.compact.starts(with: q.compact) { return 860 - Double(min(key.compactLength - q.compactLength, 50)) }
        if key.words.contains(where: { $0.starts(with: q.text) }) { return 800 }
        if q.compactLength >= 2, key.initials.starts(with: q.compact) { return 760 }
        if let position = firstOccurrence(of: q.text, in: key.text) {
            // 位置以字元計；名稱全是單一 scalar 的字元時（絕大多數）scalar 索引就是字元索引
            let characters = key.textLength == key.text.count ? position : characterCount(key.text[..<position])
            return 600 - Double(min(characters, 100))
        }
        if q.compactLength >= 2, let gaps = subsequenceGaps(q.compact, in: key.compact) {
            return max(100, 400 - Double(gaps) * 15)
        }
        return 0
    }

    /// 一段 scalar 組成幾個字元（只在名稱含 emoji 等多 scalar 字元時才用到）。
    private static func characterCount(_ scalars: ArraySlice<UInt32>) -> Int {
        var view = String.UnicodeScalarView()
        view.append(contentsOf: scalars.compactMap(Unicode.Scalar.init))
        return String(view).count
    }

    /// 子字串第一次出現的位置（名稱都很短，直接逐位比對）。
    /// - Returns: 起點索引；不包含時為 nil
    static func firstOccurrence(of needle: Scalars, in haystack: Scalars) -> Int? {
        let n = needle.count, h = haystack.count
        guard n > 0, n <= h else { return n == 0 ? 0 : nil }
        return needle.withUnsafeBufferPointer { needle in
            haystack.withUnsafeBufferPointer { haystack in
                let first = needle[0]
                outer: for start in 0...(h - n) where haystack[start] == first {
                    for k in 1..<n where haystack[start + k] != needle[k] { continue outer }
                    return start
                }
                return nil
            }
        }
    }

    /// 模糊子序列比對：查詢的每個字元都依序出現在目標中時，回傳中間跳過的字元數（越小越相關）。
    static func subsequenceGaps(_ query: Scalars, in text: Scalars) -> Int? {
        var gaps = 0
        var started = false
        var position = 0
        for character in query {
            var matched = false
            while position < text.count {
                let next = text[position]
                position += 1
                if next == character { matched = true; started = true; break }
                if started { gaps += 1 }
            }
            if !matched { return nil }
        }
        return gaps
    }

    // MARK: - 正規化

    static func normalize(_ string: String) -> String {
        string.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 轉成比對用的 scalar 陣列：先做 NFC 組合，讓檔名常見的分解形式（韓文字母、重音）與輸入的組合形式一致。
    static func scalars(_ string: String) -> Scalars {
        string.precomposedStringWithCanonicalMapping.unicodeScalars.map(\.value)
    }

    static func makeKey(_ raw: String, weight: Double) -> Key {
        let text = normalize(raw)
        let compact = String(text.filter { $0.isLetter || $0.isNumber })
        let words = splitWords(raw).map(normalize).filter { !$0.isEmpty }
        return Key(
            text: scalars(text),
            compact: scalars(compact),
            words: words.map(scalars),
            initials: scalars(String(words.compactMap(\.first))),
            weight: weight,
            textLength: text.count,
            compactLength: compact.count
        )
    }

    /// 以空白、符號與 camelCase 邊界切字（"PhotoBooth" → Photo, Booth；"Visual Studio Code" → 三個字）。
    static func splitWords(_ string: String) -> [String] {
        var words: [String] = []
        var current = ""
        var previous: Character?
        for character in string {
            if !(character.isLetter || character.isNumber) {
                if !current.isEmpty { words.append(current); current = "" }
            } else if let previous, character.isUppercase, previous.isLowercase {
                words.append(current)
                current = String(character)
            } else {
                current.append(character)
            }
            previous = character
        }
        if !current.isEmpty { words.append(current) }
        return words
    }
}

/// 執行中視窗標題的搜尋索引：每次打開啟動台拍一次快照後建立，正規化只做一次。
nonisolated struct WindowSearchIndex: Sendable {
    /// 只收「子字串」等級以上的相符：子字串依出現位置得 500–600 分，模糊子序列最高 400 分——
    /// 視窗標題很長，模糊子序列幾乎任何查詢都對得上，所以不收
    static let minimumScore: Double = 500
    /// 視窗分數打折：同樣相符程度時 App 排在視窗前面
    static let weight: Double = 0.9

    private let hits: [WindowHit]
    private let keys: [SearchIndex.Key]

    init(hits: [WindowHit]) {
        self.hits = hits
        keys = hits.map { SearchIndex.makeKey($0.title, weight: Self.weight) }
    }

    var isEmpty: Bool { hits.isEmpty }

    /// 查詢視窗標題。
    /// - Parameter query: 使用者輸入（至少 2 個字元才查，避免一個字母就列出一堆視窗）
    /// - Returns: (視窗, 已打折的分數)，分數高的在前；同分時維持快照順序（越前面的視窗越近期使用）
    func search(_ query: String) -> [(hit: WindowHit, score: Double)] {
        let q = SearchIndex.Query(query)
        guard q.compact.count >= 2 else { return [] }
        var result: [(index: Int, score: Double)] = []
        for (index, key) in keys.enumerated() {
            let raw = SearchIndex.score(q, key: key)
            if raw >= Self.minimumScore { result.append((index, raw * key.weight)) }
        }
        result.sort { $0.score != $1.score ? $0.score > $1.score : $0.index < $1.index }
        return result.map { (hits[$0.index], $0.score) }
    }
}
