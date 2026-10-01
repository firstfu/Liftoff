//
//  SearchIndex.swift
//  Liftoff
//
//  App 搜尋：支援完整名稱、字首、單字字首縮寫（vsc → Visual Studio Code）、中文名稱的拼音與拼音首字母、
//  子字串與模糊子序列比對。所有正規化在建索引時一次做完，查詢只做字串比對，170 個 App 查詢 < 0.2ms。
//

import Foundation

nonisolated struct SearchIndex: Sendable {
    private struct Key: Sendable {
        /// 正規化後的完整字串（小寫、去重音、全形轉半形）
        let text: String
        /// 去掉空白與符號的連寫版本（"visual studio code" → "visualstudiocode"）
        let compact: String
        /// 各單字（含 camelCase 切分）
        let words: [String]
        /// 單字字首縮寫
        let initials: String
        /// 權重：主要名稱 1.0，其他名稱略低
        let weight: Double
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
        let q = Self.normalize(query)
        guard !q.isEmpty else { return [] }
        let qCompact = q.filter { !$0.isWhitespace }

        var scored: [(id: String, score: Double)] = []
        for entry in entries {
            var best = 0.0
            for key in entry.keys {
                let score = Self.score(q, compactQuery: qCompact, key: key) * key.weight
                if score > best { best = score }
            }
            if best > 0 {
                scored.append((entry.id, best + (boost[entry.id] ?? 0) * 40))
            }
        }
        scored.sort { $0.score > $1.score }
        return scored.map(\.id)
    }

    // MARK: - 計分

    private static func score(_ q: String, compactQuery: String, key: Key) -> Double {
        if key.text == q || key.compact == compactQuery { return 1000 }
        if key.text.hasPrefix(q) { return 900 - Double(min(key.text.count - q.count, 50)) }
        if key.compact.hasPrefix(compactQuery) { return 860 - Double(min(key.compact.count - compactQuery.count, 50)) }
        if key.words.contains(where: { $0.hasPrefix(q) }) { return 800 }
        if compactQuery.count >= 2, key.initials.hasPrefix(compactQuery) { return 760 }
        if let range = key.text.range(of: q) {
            return 600 - Double(min(key.text.distance(from: key.text.startIndex, to: range.lowerBound), 100))
        }
        if compactQuery.count >= 2, let gaps = subsequenceGaps(compactQuery, in: key.compact) {
            return max(100, 400 - Double(gaps) * 15)
        }
        return 0
    }

    /// 模糊子序列比對：查詢的每個字元都依序出現在目標中時，回傳中間跳過的字元數（越小越相關）。
    static func subsequenceGaps(_ query: String, in text: String) -> Int? {
        var gaps = 0
        var started = false
        var iterator = text.makeIterator()
        for character in query {
            var matched = false
            while let next = iterator.next() {
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

    private static func makeKey(_ raw: String, weight: Double) -> Key {
        let text = normalize(raw)
        let words = splitWords(raw).map(normalize).filter { !$0.isEmpty }
        return Key(
            text: text,
            compact: String(text.filter { $0.isLetter || $0.isNumber }),
            words: words,
            initials: String(words.compactMap(\.first)),
            weight: weight
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
