//
//  WindowSearchTests.swift
//  LiftoffTests
//
//  視窗標題搜尋：快照的過濾規則（尺寸、桌面、與 App 同名）與標題比對的門檻、排序。
//

import CoreGraphics
import Testing
@testable import Liftoff

@MainActor
struct WindowSearchTests {
    private let apps: [pid_t: (id: String, name: String)] = [
        100: ("com.google.Chrome", "Google Chrome"),
        200: ("com.apple.iCal", "行事曆"),
    ]

    private func candidate(_ id: CGWindowID, pid: pid_t = 100, title: String, size: CGSize = CGSize(width: 1200, height: 800),
                           onScreen: Bool = true, spaces: [Int]? = nil) -> WindowCandidate {
        WindowCandidate(windowID: id, pid: pid, title: title, frame: CGRect(origin: .zero, size: size),
                        isOnScreen: onScreen, spaces: spaces)
    }

    @Test func keepsNamedWindowsOfKnownApps() {
        let hits = WindowSnapshot.hits(from: [candidate(1, title: "firstfu/Liftoff: A Launchpad replacement")], apps: apps)
        #expect(hits == [WindowHit(windowID: 1, pid: 100, appID: "com.google.Chrome", title: "firstfu/Liftoff: A Launchpad replacement")])
    }

    @Test func dropsNoise() {
        let hits = WindowSnapshot.hits(from: [
            candidate(1, title: "  "),                                         // 空白標題
            candidate(2, title: "Autofill", size: CGSize(width: 180, height: 300)), // 太小
            candidate(3, pid: 999, title: "Unknown app"),                      // 不在 App 清單
            candidate(4, pid: 200, title: "行事曆"),                            // 與 App 同名，跟 App 結果重複
            candidate(5, title: "Hidden helper", onScreen: false, spaces: []),  // 不屬於任何桌面的隱藏視窗
            candidate(6, title: "Duplicate"), candidate(6, title: "Duplicate"),
        ], apps: apps)
        #expect(hits.map(\.windowID) == [6])
    }

    @Test func keepsWindowsOnOtherSpaces() {
        let hits = WindowSnapshot.hits(from: [
            candidate(1, title: "Other desktop", onScreen: false, spaces: [3]),
            candidate(2, title: "Unknown space", onScreen: false, spaces: nil),
        ], apps: apps, currentSpaces: [6, 14])
        #expect(hits.map(\.windowID) == [1, 2])
    }

    @Test func offscreenWindowsOnCurrentDesktopMustBeVisibleToAX() {
        // 在目前桌面卻不在畫面上：AX 列得出來的（最小化、App 被 ⌘H 隱藏）收，其餘是關掉後殘留的幽靈視窗
        let ghost = candidate(1, title: "所有iCloud", onScreen: false, spaces: [6])
        let minimized = candidate(2, title: "Minimized doc", onScreen: false, spaces: [14])
        let hiddenApp = candidate(3, title: "Hidden app tab", onScreen: false, spaces: [14])
        #expect(WindowSnapshot.needsAXCheck(ghost, currentSpaces: [6, 14]))
        let hits = WindowSnapshot.hits(from: [ghost, minimized, hiddenApp], apps: apps, currentSpaces: [6, 14], axVisible: [2, 3])
        #expect(hits.map(\.windowID) == [2, 3])
    }

    private func hit(_ id: UInt32, _ title: String) -> WindowHit {
        WindowHit(windowID: id, pid: 100, appID: "com.google.Chrome", title: title)
    }

    @Test func matchesWordsAndSubstringsButNotFuzzy() {
        let index = WindowSearchIndex(hits: [hit(1, "Pull request #42 · firstfu/Liftoff"), hit(2, "報價單 2026.xlsx")])
        #expect(index.search("liftoff").map(\.hit.windowID) == [1])
        #expect(index.search("報價").map(\.hit.windowID) == [2])
        // 出現在標題中間的子字串（分數依位置遞減到 500）也要找得到
        let middle = WindowSearchIndex(hits: [hit(3, "新分頁 - obsidianDB - Obsidian 1.13.7")])
        #expect(middle.search("obsidiandb").map(\.hit.windowID) == [3])
        // 模糊子序列（p…l…f）在長標題上幾乎都對得上，不收
        #expect(index.search("plf").isEmpty)
    }

    @Test func singleCharacterQueriesAreIgnored() {
        let index = WindowSearchIndex(hits: [hit(1, "a")])
        #expect(index.search("a").isEmpty)
    }

    @Test func tiesKeepSnapshotOrder() {
        // 快照順序即前後層次：同分時越前面（越近期使用）的排前面
        let index = WindowSearchIndex(hits: [hit(1, "Liftoff docs"), hit(2, "Liftoff docs")])
        #expect(index.search("liftoff").map(\.hit.windowID) == [1, 2])
    }

    @Test func appsOutrankEquallyMatchingWindows() {
        let apps = SearchIndex(apps: [AppEntry(id: "x", bundleID: "x", path: "/Applications/Liftoff.app", resolvedPath: "/Applications/Liftoff.app",
                                               name: "Liftoff", altNames: [], category: nil, modified: .distantPast)])
        let windows = WindowSearchIndex(hits: [hit(1, "Liftoff")])
        let app = apps.scored("liftoff").first?.score ?? 0
        let window = windows.search("liftoff").first?.score ?? 0
        #expect(app > window)
    }
}
