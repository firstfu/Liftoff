//
//  SearchIndexTests.swift
//  LiftoffTests
//
//  搜尋排序：字首優先、單字縮寫、英文別名、中文拼音、模糊比對、使用頻率加權。
//

import Foundation
import Testing
@testable import Liftoff

@MainActor
struct SearchIndexTests {
    private func app(_ id: String, _ name: String, alt: [String] = []) -> AppEntry {
        AppEntry(id: id, bundleID: id, path: "/\(id).app", resolvedPath: "/\(id).app", name: name,
                 altNames: alt, category: nil, modified: .distantPast, latin: AppScanner.latinName(for: name))
    }

    private var index: SearchIndex {
        SearchIndex(apps: [
            app("safari", "Safari"),
            app("siri", "Siri", alt: ["Siri AI"]),
            app("messages", "訊息", alt: ["Messages"]),
            app("vscode", "Visual Studio Code"),
            app("calc", "計算機", alt: ["Calculator"]),
            app("settings", "系統設定", alt: ["System Settings"]),
            app("shazam", "Shazam"),
        ])
    }

    @Test func prefixMatchRanksFirst() {
        #expect(index.search("sa").first == "safari")
    }

    @Test func initialsMatchMultiWordNames() {
        #expect(index.search("vsc").first == "vscode")
    }

    @Test func englishAliasFindsLocalizedApp() {
        #expect(index.search("settings").first == "settings")
        #expect(index.search("calcu").first == "calc")
    }

    @Test func chineseNameAndPinyin() {
        #expect(index.search("計算").first == "calc")
        #expect(index.search("jisuan").first == "calc")
        #expect(index.search("jsj").first == "calc")
    }

    @Test func fuzzySubsequence() {
        #expect(index.search("shzm").contains("shazam"))
    }

    @Test func caseAndWidthInsensitive() {
        #expect(index.search("ＳＡＦ").first == "safari")
        #expect(index.search("SAFARI").first == "safari")
    }

    @Test func emptyQueryReturnsNothing() {
        #expect(index.search("   ").isEmpty)
    }

    @Test func usageBoostBreaksTies() {
        let plain = SearchIndex(apps: [app("a", "Notes Alpha"), app("b", "Notes Beta")])
        #expect(plain.search("notes", boost: ["b": 1]).first == "b")
    }

    @Test func splitWordsHandlesCamelCase() {
        #expect(SearchIndex.splitWords("PhotoBooth") == ["Photo", "Booth"])
        #expect(SearchIndex.splitWords("Visual Studio Code") == ["Visual", "Studio", "Code"])
    }

    /// 計分改成比對 scalar 陣列後，分數必須與原本的 String 版完全相同（參考實作是改寫前的原始碼）。
    @Test func scalarScoringMatchesStringReference() {
        let names = [
            "Safari", "Visual Studio Code", "PhotoBooth", "計算機", "ji suan ji", "系統設定", "System Settings",
            "Café Ñandú", "ＦｕｌｌＷｉｄｔｈ", "日本語入力", "카카오톡", "카카오톡".decomposedStringWithCanonicalMapping,
            "Xcode-beta", "1Password 8", "Notes 🗒️ Pro", "über-App", "Microsoft Word", "TextEdit", "a",
        ]
        let queries = [
            "s", "sa", "saf", "safari", "vsc", "visual s", "code", "stu", "pb", "photo", "booth", "計", "計算", "jsj",
            "jisuan", "set", "sys", "cafe", "nandu", "fullw", "ＦＵＬＬ", "日本", "카카", "카카".decomposedStringWithCanonicalMapping,
            "xcb", "beta", "1pass", "pass 8", "notes", "pro", "uber", "mw", "word", "txed", "te", "a", "zz", "o",
        ]
        for name in names {
            let key = SearchIndex.makeKey(name, weight: 1)
            for query in queries {
                let expected = Self.referenceScore(query, name: name)
                let actual = SearchIndex.score(SearchIndex.Query(query), key: key)
                #expect(actual == expected, "名稱「\(name)」查詢「\(query)」：\(actual) ≠ \(expected)")
            }
        }
    }

    /// 改寫前以 String 比對的計分（逐字保留原始邏輯，只當作測試的對照組）。
    private static func referenceScore(_ query: String, name: String) -> Double {
        let q = SearchIndex.normalize(query)
        let compactQuery = q.filter { !$0.isWhitespace }
        let text = SearchIndex.normalize(name)
        let compact = String(text.filter { $0.isLetter || $0.isNumber })
        let words = SearchIndex.splitWords(name).map(SearchIndex.normalize).filter { !$0.isEmpty }
        let initials = String(words.compactMap(\.first))
        if text == q || compact == compactQuery { return 1000 }
        if text.hasPrefix(q) { return 900 - Double(min(text.count - q.count, 50)) }
        if compact.hasPrefix(compactQuery) { return 860 - Double(min(compact.count - compactQuery.count, 50)) }
        if words.contains(where: { $0.hasPrefix(q) }) { return 800 }
        if compactQuery.count >= 2, initials.hasPrefix(compactQuery) { return 760 }
        if let range = text.range(of: q) {
            return 600 - Double(min(text.distance(from: text.startIndex, to: range.lowerBound), 100))
        }
        if compactQuery.count >= 2 {
            var gaps = 0, started = false, matchedAll = true
            var iterator = compact.makeIterator()
            for character in compactQuery {
                var matched = false
                while let next = iterator.next() {
                    if next == character { matched = true; started = true; break }
                    if started { gaps += 1 }
                }
                if !matched { matchedAll = false; break }
            }
            if matchedAll { return max(100, 400 - Double(gaps) * 15) }
        }
        return 0
    }
}
