//
//  WindowActions.swift
//  Liftoff（沿用自 DockLens，已在 DockLens 實測驗證）
//
//  對視窗/App 的操作：切換到視窗、關閉、縮小、隱藏、結束。
//  切換視窗優先走 SkyLight 私有 API（可指定視窗、可跨 Space），失敗才退回公開 API。
//

import AppKit

enum WindowActions {
    /// 切換到指定視窗：取消最小化 → 前置 App 並讓該視窗成為 key → AXRaise 確保它在同 App 視窗的最上層。
    /// - Parameter window: 目標視窗
    static func focus(_ window: WindowInfo) {
        let element = window.ax?.element
        if window.isMinimized {
            element?.set(kAXMinimizedAttribute, kCFBooleanFalse)
        }
        if !SkyLight.focus(pid: window.pid, windowID: window.id) {
            NSRunningApplication(processIdentifier: window.pid)?.activate()
        }
        element?.perform(kAXRaiseAction)
        element?.set(kAXMainAttribute, kCFBooleanTrue)
    }

    /// 關閉視窗：按下視窗的關閉鈕（等同使用者點紅燈，App 可以跳出「是否儲存」）。
    /// - Returns: 是否成功送出
    @discardableResult
    static func close(_ window: WindowInfo) -> Bool {
        guard let element = window.ax?.element,
              let button: AXUIElement = element.value(kAXCloseButtonAttribute) else { return false }
        return button.perform(kAXPressAction)
    }

    /// 切換最小化狀態。
    /// - Returns: 是否成功
    @discardableResult
    static func toggleMinimize(_ window: WindowInfo) -> Bool {
        guard let element = window.ax?.element else { return false }
        return element.set(kAXMinimizedAttribute, window.isMinimized ? kCFBooleanFalse : kCFBooleanTrue)
    }

    /// 切換全螢幕。
    @discardableResult
    static func toggleFullScreen(_ window: WindowInfo) -> Bool {
        guard let element = window.ax?.element else { return false }
        let current: Bool = element.value("AXFullScreen") ?? false
        return element.set("AXFullScreen", current ? kCFBooleanFalse : kCFBooleanTrue)
    }

    /// 隱藏或顯示 App。
    static func toggleHidden(_ app: NSRunningApplication) {
        if app.isHidden { app.unhide() } else { app.hide() }
    }

    /// 開新視窗：啟用 App 後對它送出 ⌘N（絕大多數 App 的「新增視窗」快捷鍵）。
    /// 直接把按鍵事件投遞給該 pid，不會誤觸其他 App。
    static func newWindow(_ app: NSRunningApplication) {
        app.unhide()
        app.activate()
        let pid = app.processIdentifier
        Task { @MainActor in
            // 等 App 成為前景再送鍵，否則部分 App 會忽略
            try? await Task.sleep(for: .milliseconds(120))
            let source = CGEventSource(stateID: .hidSystemState)
            let keyN: CGKeyCode = 45
            for isDown in [true, false] {
                let event = CGEvent(keyboardEventSource: source, virtualKey: keyN, keyDown: isDown)
                event?.flags = .maskCommand
                event?.postToPid(pid)
            }
        }
    }

    /// 結束 App（正常結束，App 可詢問是否存檔）。
    static func quit(_ app: NSRunningApplication) {
        app.terminate()
    }
}
