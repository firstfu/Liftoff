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
}
