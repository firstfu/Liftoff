//
//  LayoutTests.swift
//  LiftoffTests
//
//  版面模型的規則測試：插入/移動的連鎖擠頁、資料夾合併/移出/解散、與已安裝 App 同步。
//

import Foundation
import Testing
@testable import Liftoff

@MainActor
struct LayoutTests {
    private func apps(_ ids: String...) -> [LayoutItem] { ids.map { LayoutItem.app($0) } }

    @Test func insertCascadesOverflowToNextPage() {
        var layout = Layout(pages: [apps("a", "b", "c"), apps("d")])
        layout.insert(.app("x"), at: ItemPosition(page: 0, index: 1), capacity: 3)
        #expect(layout.pages == [apps("a", "x", "b"), apps("c", "d")])
    }

    @Test func insertBeyondLastPageCreatesPage() {
        var layout = Layout(pages: [apps("a", "b")])
        layout.insert(.app("x"), at: ItemPosition(page: 5, index: 0), capacity: 2)
        #expect(layout.pages == [apps("a", "b"), apps("x")])
    }

    @Test func moveWithinPageLandsAtTargetIndex() {
        var layout = Layout(pages: [apps("a", "b", "c", "d")])
        layout.move(itemID: "a", to: ItemPosition(page: 0, index: 2), capacity: 4)
        #expect(layout.pages == [apps("b", "c", "a", "d")])
    }

    @Test func moveAcrossPagesKeepsEmptySourcePageUntilNormalize() {
        var layout = Layout(pages: [apps("a"), apps("b", "c")])
        layout.move(itemID: "a", to: ItemPosition(page: 1, index: 1), capacity: 3)
        #expect(layout.pages == [[], apps("b", "a", "c")])
        layout.normalize(capacity: 3)
        #expect(layout.pages == [apps("b", "a", "c")])
    }

    @Test func mergeTwoAppsCreatesFolderInTargetSlot() throws {
        var layout = Layout(pages: [apps("a", "b", "c")])
        let merged = layout.merge(appID: "a", into: "c", folderName: "工具")
        let id = try #require(merged)
        #expect(layout.pages[0].count == 2)
        #expect(layout.pages[0][0] == .app("b"))
        let folder = try #require(layout.pages[0][1].folder)
        #expect(folder.id == id)
        #expect(folder.apps == ["c", "a"])
        #expect(folder.name == "工具")
    }

    @Test func mergeIntoExistingFolderAppends() throws {
        let folder = FolderData(name: "F", apps: ["x", "y"])
        var layout = Layout(pages: [[.folder(folder), .app("a")]])
        let merged = layout.merge(appID: "a", into: LayoutItem.folderKey(folder.id), folderName: "ignored")
        #expect(merged == folder.id)
        #expect(layout.pages[0] == [.folder(FolderData(id: folder.id, name: "F", apps: ["x", "y", "a"]))])
    }

    @Test func mergeOntoSelfIsRejected() {
        var layout = Layout(pages: [apps("a", "b")])
        let merged = layout.merge(appID: "a", into: "a", folderName: "F")
        #expect(merged == nil)
        #expect(layout.pages == [apps("a", "b")])
    }

    @Test func removingSecondToLastAppDissolvesFolder() {
        let folder = FolderData(name: "F", apps: ["x", "y"])
        var layout = Layout(pages: [[.app("a"), .folder(folder)]])
        layout.removeApp("x", fromFolder: folder.id)
        #expect(layout.pages == [apps("a", "y")])
    }

    @Test func dragAppOutOfFolderOntoFormerSibling() throws {
        // 資料夾 [x, y]：把 x 拖出後資料夾解散成 y，再把 x 拖到 y 上 → 重新合成資料夾
        let folder = FolderData(name: "F", apps: ["x", "y"])
        var layout = Layout(pages: [[.folder(folder)]])
        // 不能把 App 合併進它自己所在的資料夾
        let rejected = layout.merge(appID: "x", into: LayoutItem.folderKey(folder.id), folderName: "F")
        #expect(rejected == nil)
        layout.removeApp("x", fromFolder: folder.id)
        layout.insert(.app("x"), at: ItemPosition(page: 0, index: 1), capacity: 10)
        #expect(layout.pages == [apps("y", "x")])
        let regrouped = layout.merge(appID: "x", into: "y", folderName: "G")
        let groupID = try #require(regrouped)
        #expect(layout.folder(id: groupID)?.apps == ["y", "x"])
    }

    @Test func dissolveFolderPutsAppsInPlace() {
        let folder = FolderData(name: "F", apps: ["x", "y", "z"])
        var layout = Layout(pages: [[.app("a"), .folder(folder), .app("b")]])
        layout.dissolveFolder(folder.id, capacity: 4)
        #expect(layout.pages == [apps("a", "x", "y", "z"), apps("b")])
    }

    @Test func reconcileRemovesUninstalledAndAppendsNew() {
        let folder = FolderData(name: "F", apps: ["x", "gone"])
        var layout = Layout(pages: [[.app("a"), .folder(folder), .app("hidden")]])
        let changed = layout.reconcile(installed: ["a", "x", "hidden", "new"], hidden: ["hidden"], capacity: 10)
        #expect(changed)
        // 資料夾只剩一個 App 時自動解散；新 App 加在最後；隱藏的 App 移除
        #expect(layout.pages == [apps("a", "x", "new")])
    }

    @Test func reconcileRemovesDuplicates() {
        var layout = Layout(pages: [[.app("a"), .folder(FolderData(name: "F", apps: ["a", "b", "c"]))]])
        layout.reconcile(installed: ["a", "b", "c"], hidden: [], capacity: 10)
        #expect(layout.allAppIDs == ["a", "b", "c"])
    }

    @Test func compactFillsPages() {
        var layout = Layout(pages: [apps("a"), apps("b", "c"), apps("d")])
        layout.compact(capacity: 3)
        #expect(layout.pages == [apps("a", "b", "c"), apps("d")])
    }

    @Test func moveInFolderReorders() {
        let folder = FolderData(name: "F", apps: ["x", "y", "z"])
        var layout = Layout(pages: [[.folder(folder)]])
        layout.moveInFolder(folder.id, appID: "x", to: 2)
        #expect(layout.folder(id: folder.id)?.apps == ["y", "z", "x"])
    }

    @Test func renameIgnoresBlankNames() {
        let folder = FolderData(name: "F", apps: ["x", "y"])
        var layout = Layout(pages: [[.folder(folder)]])
        layout.renameFolder(folder.id, to: "   ")
        #expect(layout.folder(id: folder.id)?.name == "F")
        layout.renameFolder(folder.id, to: " 工作 ")
        #expect(layout.folder(id: folder.id)?.name == "工作")
    }

    @Test func layoutRoundTripsThroughJSON() throws {
        let layout = Layout(pages: [[.app("a"), .folder(FolderData(name: "F", apps: ["x", "y"]))], apps("b")])
        let decoded = try JSONDecoder().decode(Layout.self, from: JSONEncoder().encode(layout))
        #expect(decoded == layout)
    }

    @Test func folderNamingUsesSharedCategory() {
        func entry(_ category: String?) -> AppEntry {
            AppEntry(id: UUID().uuidString, bundleID: nil, path: "/x.app", resolvedPath: "/x.app", name: "X",
                     altNames: [], category: category, modified: .distantPast)
        }
        #expect(FolderNaming.name(target: entry("public.app-category.developer-tools"),
                                  dragged: entry("public.app-category.developer-tools")) == "開發者工具")
        #expect(FolderNaming.name(target: entry("public.app-category.action-games"), dragged: entry(nil)) == "遊戲")
        #expect(FolderNaming.name(target: entry(nil), dragged: entry(nil)) == "資料夾")
    }
}
