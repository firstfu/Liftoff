//
//  AppClassifierTests.swift
//  LiftoffTests
//
//  智慧整理：分類規則的判斷順序、內建對照表的完整性、整理後版面不漏不重。
//

import Foundation
import Testing
@testable import Liftoff

@MainActor
struct AppClassifierTests {
    private func entry(_ id: String, name: String? = nil, path: String? = nil, category: String? = nil) -> AppEntry {
        let path = path ?? "/Applications/\(name ?? id).app"
        return AppEntry(id: id, bundleID: id, path: path, resolvedPath: path, name: name ?? id, altNames: [],
                        category: category, modified: .distantPast)
    }

    private let classifier = AppClassifier(
        byBundleID: ["com.test.editor": .developer, "com.test.mail": .communication, "com.test.player": .media],
        byAppName: ["onedrive.app": .cloud]
    )

    @Test func tableWinsOverCategory() {
        let result = classifier.classify(entry("com.test.editor", category: "public.app-category.productivity"))
        #expect(result == .init(folder: .developer, source: .table))
    }

    @Test func setappSuffixFallsBackToOriginalID() {
        #expect(classifier.classify(entry("com.test.mail-setapp"))?.folder == .communication)
    }

    @Test func appFileNameFallbackWhenBundleIDDiffers() {
        // App Store 版 OneDrive 的 bundle ID 與官網版不同，靠檔名比對
        #expect(classifier.classify(entry("com.microsoft.OneDrive-mac", name: "OneDrive"))?.folder == .cloud)
    }

    @Test func ambiguousAppFileNameIsNotUsedForFallback() throws {
        // 兩個不同的 App 檔名同為 Helium.app 卻分在不同資料夾：檔名比對不能挑其中一個
        let json = """
        {"version": 1, "apps": {
          "a.helium": {"folder": "browser", "app": "Helium.app", "name": "Helium"},
          "b.helium": {"folder": "utilities", "app": "Helium.app", "name": "Helium"},
          "c.solo": {"folder": "media", "app": "Solo.app", "name": "Solo"}}}
        """
        let table = try AppClassifier(tableData: Data(json.utf8))
        #expect(table.classify(entry("x.other", name: "Helium")) == nil)
        #expect(table.classify(entry("x.other", name: "Solo"))?.folder == .media)
        #expect(table.classify(entry("a.helium"))?.folder == .browser)
    }

    @Test func specificCategoryIsGuess() {
        let result = classifier.classify(entry("com.unknown.cam", category: "public.app-category.photography"))
        #expect(result == .init(folder: .design, source: .category))
    }

    @Test func broadOrMissingCategoryStaysUnclassified() {
        #expect(classifier.classify(entry("com.unknown.a", category: "public.app-category.productivity")) == nil)
        #expect(classifier.classify(entry("com.unknown.b", category: "public.app-category.utilities")) == nil)
        #expect(classifier.classify(entry("com.unknown.c")) == nil)
    }

    @Test func systemUtilitiesByLocation() {
        let disk = entry("com.apple.DiskUtility", path: "/System/Applications/Utilities/Disk Utility.app")
        #expect(classifier.classify(disk) == .init(folder: .systemUtilities, source: .location))
    }

    @Test func bundledTableLoadsAndCoversCommonApps() throws {
        let url = try #require(Bundle.main.url(forResource: "AppCategories", withExtension: "json"))
        // folder 不是已知種類時解碼會失敗，所以能載入就代表每一筆都合法
        let table = try AppClassifier(tableData: Data(contentsOf: url))
        #expect(table.classify(entry("com.apple.Maps"))?.folder == .lifestyle)
        #expect(table.classify(entry("com.googlecode.iterm2"))?.folder == .developer)
        #expect(table.classify(entry("com.microsoft.Word"))?.folder == .productivity)
    }

    @Test func planKeepsEveryAppExactlyOnce() {
        let entries = [
            entry("com.test.editor", name: "Editor"), entry("com.test.mail", name: "Mail"), entry("com.test.player", name: "Player"),
            entry("dev2", category: "public.app-category.developer-tools"), entry("dev3", category: "public.app-category.developer-tools"),
            entry("unknown"), entry("hidden", category: "public.app-category.developer-tools"),
            entry("u1", path: "/System/Applications/Utilities/A.app"), entry("u2", path: "/System/Applications/Utilities/B.app"),
        ]
        let plan = OrganizePlan(entries: entries, hidden: ["hidden"], classifier: classifier)
        // 開發工具 3 個 → 建資料夾；溝通、影音各 1 個 → 留在外面；工具程式 2 個 → 建資料夾
        #expect(plan.groups.map(\.folder) == [.developer, .systemUtilities])
        #expect(Set(plan.loose) == ["com.test.mail", "com.test.player", "unknown"])
        #expect(plan.guessed == ["dev2", "dev3"])
        #expect(plan.unclassifiedCount == 1)

        let layout = plan.layout(capacity: 4)
        let ids = layout.allAppIDs
        #expect(ids.count == Set(ids).count)
        #expect(Set(ids) == Set(entries.map(\.id)).subtracting(["hidden"]))
        // 工具程式資料夾排在最後
        #expect(layout.pages.last?.last?.folder?.name == AppFolder.systemUtilities.displayName)
    }
}
