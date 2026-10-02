//
//  LaunchpadModel+Input.swift
//  Liftoff
//
//  滑鼠輸入的集中處理：點擊、拖曳、右鍵、hover 都在面板層攔下，用格線數學判斷命中哪一格，
//  不在每個格子上掛 SwiftUI 手勢——上百個格子因此少了大量事件節點，建立與更新都便宜得多。
//  沒命中格子的事件（搜尋框、頁碼點、資料夾標題、預覽卡片、空白處）照常交給 SwiftUI。
//

import AppKit
import SwiftUI

/// 滑鼠命中的格子。
struct HitTarget {
    let item: LayoutItem
    /// 圖示外框（根座標）
    let iconFrame: CGRect
    /// 所在資料夾（主格線為 nil）
    let folderID: UUID?
}

/// 按下但尚未放開的狀態。
struct PressState {
    let item: LayoutItem
    let folderID: UUID?
    let start: CGPoint
    let iconCenter: CGPoint
    /// 這次按下是否已經進入過拖曳（進入過就不能再當成點擊）
    var didDrag = false
}

extension LaunchpadModel {
    /// 處理滑鼠事件。
    /// - Parameters:
    ///   - event: 滑鼠事件
    ///   - point: 事件位置（根座標，左上為原點）
    ///   - view: 用來彈出右鍵選單的 view
    /// - Returns: true 表示已處理、不再交給 SwiftUI
    func handleMouse(_ event: NSEvent, at point: CGPoint, in view: NSView) -> Bool {
        switch event.type {
        case .leftMouseDown:
            guard let hit = hitTest(point) else {
                // 格線空白處（主畫面或資料夾面板內）：由我們接手，按住左右拖就翻頁
                // （搜尋列、頁碼點、資料夾標題不在格線範圍內，照常交給 SwiftUI）
                guard isShown, confirmation == nil, !preview.isVisible, drag == nil, isOverEmptyGrid(point) else { return false }
                backgroundPress = point
                backgroundLastX = point.x
                return true
            }
            preview.hide()
            press = PressState(item: hit.item, folderID: hit.folderID, start: point,
                               iconCenter: CGPoint(x: hit.iconFrame.midX, y: hit.iconFrame.midY))
            pressedID = hit.item.id
            startLongPress(for: hit)
            return true

        case .leftMouseDragged:
            if let start = backgroundPress {
                // 超過 4pt 才算拖動，避免點一下手抖就變成翻頁
                let target = mouseDragPager()
                if target.pager.isMouseTracking || abs(point.x - start.x) > 4 {
                    target.pager.pageWidth = target.width
                    target.pager.mouseDragged(point.x - backgroundLastX, pageCount: target.pageCount, timestamp: event.timestamp)
                    backgroundLastX = point.x
                }
                return true
            }
            guard let press else { return false }
            // 手指移動超過 6pt 就不算長按
            if hypot(point.x - press.start.x, point.y - press.start.y) > 6 { longPressTask?.cancel() }
            dragChanged(item: press.item, folderID: press.folderID, location: point, start: press.start, iconCenter: press.iconCenter)
            if drag != nil {
                self.press?.didDrag = true
                if pressedID != nil { pressedID = nil }
            }
            return true

        case .leftMouseUp:
            if backgroundPress != nil {
                backgroundPress = nil
                let target = mouseDragPager()
                if target.pager.isMouseTracking {
                    target.pager.mouseDragEnded(pageCount: target.pageCount)
                } else if openFolder != nil {
                    // 點資料夾面板內空白處：只結束改名，不關資料夾（原本由 SwiftUI 的透明底處理）
                    isRenamingFolder = false
                } else {
                    backgroundClicked()
                }
                return true
            }
            longPressTask?.cancel()
            guard let press else { return false }
            self.press = nil
            pressedID = nil
            if drag != nil {
                dragEnded()
            } else if !press.didDrag, hypot(point.x - press.start.x, point.y - press.start.y) < 6 {
                activate(press.item)
            }
            return true

        case .rightMouseDown:
            guard let hit = hitTest(point) else { return false }
            preview.hide()
            let menu = contextMenu(for: hit)
            NSMenu.popUpContextMenu(menu, with: event, for: view)
            return true

        case .mouseMoved:
            updateHover(hitTest(point))
            return false

        default:
            return false
        }
    }

    /// 長按 App 圖示（0.6 秒、期間沒移動也沒進入拖曳）→ 開啟「徹底移除」。資料夾不適用。
    private func startLongPress(for hit: HitTarget) {
        longPressTask?.cancel()
        guard case .app(let id) = hit.item, let entry = catalog.entry(id), !entry.isSystemApp else { return }
        longPressTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled, let self, self.press?.item.id == hit.item.id, self.drag == nil else { return }
            // 這次按下已被長按接手，放開時不能再被當成點擊而開啟 App
            self.press = nil
            self.pressedID = nil
            self.requestUninstall(id)
        }
    }

    /// 是否落在格線範圍內的空白處：資料夾開著時看面板內的格線區，否則看主格線區。
    private func isOverEmptyGrid(_ point: CGPoint) -> Bool {
        guard let folder = openFolder else { return metrics.gridRect.contains(point) }
        let panel = folderPanelFrame(for: folder)
        let local = CGPoint(x: point.x - panel.minX, y: point.y - panel.minY)
        return folderGridMetrics.gridRect.contains(local)
    }

    /// 滑鼠拖動翻頁的對象：資料夾開著時翻資料夾內頁，否則翻主畫面。
    private func mouseDragPager() -> (pager: PagerState, pageCount: Int, width: CGFloat) {
        if let folder = openFolder {
            let pages = (folder.apps.count + folderCapacity - 1) / folderCapacity
            return (folderPager, pages, folderPanelFrame(for: folder).width)
        }
        return (pager, displayPages.count, containerSize.width)
    }

    /// 命中測試：點落在哪個格子（被資料夾面板、預覽框、確認框蓋住的區域不算）。
    func hitTest(_ point: CGPoint) -> HitTarget? {
        guard isShown, confirmation == nil else { return nil }
        if preview.isVisible, WindowPreviewLayer.frame(for: preview, containerSize: containerSize).contains(point) { return nil }

        if let folder = openFolder {
            let panel = folderPanelFrame(for: folder)
            guard panel.contains(point) else { return nil }
            let local = CGPoint(x: point.x - panel.minX, y: point.y - panel.minY)
            let metrics = folderGridMetrics
            guard folderPager.offset == 0, let index = metrics.cellIndex(atHotPoint: local) else { return nil }
            let global = folderPager.page * folderCapacity + index
            guard folder.apps.indices.contains(global) else { return nil }
            return HitTarget(item: .app(folder.apps[global]),
                             iconFrame: metrics.iconFrame(index).offsetBy(dx: panel.minX, dy: panel.minY),
                             folderID: folder.id)
        }

        // 翻頁跟手中：格子正在移動，不接受點擊
        guard pager.offset == 0 else { return nil }
        let metrics = metrics
        guard let index = metrics.cellIndex(atHotPoint: point) else { return nil }
        let pages = displayPages
        guard pages.indices.contains(pager.page), pages[pager.page].indices.contains(index) else { return nil }
        return HitTarget(item: pages[pager.page][index], iconFrame: metrics.iconFrame(index), folderID: nil)
    }

    /// 游標移動：進出執行中 App 的圖示時觸發視窗預覽。
    private func updateHover(_ hit: HitTarget?) {
        let id = hit?.item.appID
        guard id != hoveredID else { return }
        if let previous = hoveredID {
            hover(.app(previous), inside: false, anchor: .zero)
        }
        hoveredID = id
        if let hit, id != nil, drag == nil, press == nil {
            hover(hit.item, inside: true, anchor: hit.iconFrame)
        }
    }

    // MARK: - 右鍵選單

    /// 依項目建立右鍵選單（只在右鍵當下建立，不佔用平時的記憶體與效能）。
    private func contextMenu(for hit: HitTarget) -> NSMenu {
        let menu = NSMenu()
        switch hit.item {
        case .app(let id):
            let entry = catalog.entry(id)
            menu.addItem(ClosureMenuItem(String(localized: "開啟")) { [weak self] in self?.launch(id) })
            if let app = running.application(for: id) {
                menu.addItem(ClosureMenuItem(String(localized: "顯示所有視窗")) { [weak self] in
                    guard let self, let entry else { return }
                    self.preview.showNow(appID: id, app: app, name: entry.name, anchor: hit.iconFrame)
                })
                menu.addItem(ClosureMenuItem(String(localized: "結束")) { AppActions.quit(app) })
            }
            if let entry {
                menu.addItem(ClosureMenuItem(String(localized: "在 Finder 中顯示")) { [weak self] in
                    self?.requestDismiss?(.user)
                    AppActions.revealInFinder(entry)
                })
            }
            if let folderID = hit.folderID {
                menu.addItem(ClosureMenuItem(String(localized: "移出資料夾")) { [weak self] in
                    self?.removeFromFolder(id, folderID: folderID)
                })
            }
            menu.addItem(.separator())
            menu.addItem(ClosureMenuItem(String(localized: "從啟動台隱藏")) { [weak self] in self?.hideApp(id) })
            if let entry, !entry.isSystemApp {
                menu.addItem(ClosureMenuItem(String(localized: "徹底移除…")) { [weak self] in self?.requestUninstall(id) })
            }
        case .folder(let folder):
            menu.addItem(ClosureMenuItem(String(localized: "打開資料夾")) { [weak self] in self?.openFolder(folder.id) })
            menu.addItem(ClosureMenuItem(String(localized: "重新命名")) { [weak self] in
                self?.openFolder(folder.id)
                self?.isRenamingFolder = true
            })
            menu.addItem(.separator())
            menu.addItem(ClosureMenuItem(String(localized: "解散資料夾")) { [weak self] in self?.dissolveFolder(folder.id) })
        case .window(let window):
            menu.addItem(ClosureMenuItem(String(localized: "切換到此視窗")) { [weak self] in self?.switchToWindow(window) })
            if let app = running.application(for: window.appID), let entry = catalog.entry(window.appID) {
                menu.addItem(ClosureMenuItem(String(localized: "顯示所有視窗")) { [weak self] in
                    self?.preview.showNow(appID: window.appID, app: app, name: entry.name, anchor: hit.iconFrame)
                })
            }
        }
        return menu
    }
}

/// 以 closure 建立選單項目（NSMenuItem 的 target 是弱參照，所以把動作物件放在 representedObject 保活）。
func ClosureMenuItem(_ title: String, handler: @escaping () -> Void) -> NSMenuItem {
    let action = MenuAction(handler)
    let item = NSMenuItem(title: title, action: #selector(MenuAction.invoke), keyEquivalent: "")
    item.target = action
    item.representedObject = action
    return item
}

final class MenuAction: NSObject {
    private let handler: () -> Void

    init(_ handler: @escaping () -> Void) {
        self.handler = handler
    }

    @objc func invoke() { handler() }
}
