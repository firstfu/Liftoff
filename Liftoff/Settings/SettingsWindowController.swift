//
//  SettingsWindowController.swift
//  Liftoff
//
//  設定 process 裡的設定視窗：自建 NSWindow＋NSHostingController，關閉時通知呼叫端（設定 process 隨即結束）。
//  不用 SwiftUI 的 `Settings` 場景：它沒有公開的開啟方式，而且關閉只是藏起視窗，無法得知何時該結束 process。
//

import AppKit
import SwiftUI

final class SettingsWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    /// 視窗關閉後呼叫
    var onClose: (() -> Void)?

    /// 目前開著的設定視窗（沒開時為 nil）。
    var currentWindow: NSWindow? { window }

    /// 顯示設定視窗；已開著就沿用同一個。
    /// - Parameter context: 傳給 `SettingsView` 的資料與動作
    /// - Returns: 設定視窗，呼叫端負責帶到最前。
    func show(context: SettingsContext) -> NSWindow {
        if let window { return window }
        // 第一次回呼發生在下面 NSWindow 建立途中（self.window 還沒指派），所以先記下來、建好後再套用
        var pendingTitle = ""
        let view = SettingsView(context: context) { [weak self] title in
            if let window = self?.window { window.title = title } else { pendingTitle = title }
        }
        let hosting = NSHostingController(rootView: view)
        // 視窗大小由 SettingsView 自己的 frame 決定，不讓 hosting 依內容反覆調整
        hosting.sizingOptions = [.preferredContentSize]
        let window = NSWindow(contentViewController: hosting)
        // 和系統設定視窗慣例一致：不可縮到 Dock、不可調整大小
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.toolbarStyle = .unified
        // 由本類別持有並在關閉時放掉；交給 AppKit 自動釋放會和這裡的強參考重複釋放
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        window.title = pendingTitle
        self.window = window
        return window
    }

    func windowWillClose(_ notification: Notification) {
        guard let closing = notification.object as? NSWindow, closing === window else { return }
        // 先拆掉 content，讓 SwiftUI 的 view 樹（含 onDisappear 停止權限輪詢、結束快速鍵錄製）在結束前跑完
        closing.contentViewController = nil
        closing.delegate = nil
        window = nil
        onClose?()
    }
}
