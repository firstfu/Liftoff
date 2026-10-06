//
//  Permissions.swift
//  Liftoff（沿用自 DockLens，已在 DockLens 實測驗證）
//
//  視窗縮圖預覽用到的兩項權限（啟動台本身不需要任何權限）：
//  - 螢幕錄製（Screen Recording）：擷取視窗縮圖、讀取視窗標題（必要）
//  - 輔助使用（Accessibility）：列出最小化的視窗、點縮圖時精準切換到「那一個」視窗（選用）
//  系統不會通知權限變更，因此設定頁的權限區顯示期間、尚未全部授權時每秒輪詢一次；
//  全部授權或離開該頁就停止——螢幕錄製是選用權限，不授權的使用者若一直輪詢，就是每秒一次 TCC IPC 直到 App 結束。
//

import AppKit
import ApplicationServices
import Observation

@Observable
final class Permissions {
    private(set) var accessibility = AXIsProcessTrusted()
    private(set) var screenRecording = CGPreflightScreenCaptureAccess()

    var allGranted: Bool { accessibility && screenRecording }

    /// 全部授權完成時呼叫一次
    @ObservationIgnored var onAllGranted: (() -> Void)?
    @ObservationIgnored private var pollTask: Task<Void, Never>?

    /// 重新讀取權限狀態；若由未授權變為全部授權則觸發 `onAllGranted`。
    func refresh() {
        let wasGranted = allGranted
        accessibility = AXIsProcessTrusted()
        screenRecording = CGPreflightScreenCaptureAccess()
        if !wasGranted && allGranted { onAllGranted?() }
    }

    /// 在尚未全部授權期間每秒輪詢；呼叫端離開權限畫面時必須呼叫 `stopPolling()`。
    func startPolling() {
        guard pollTask == nil, !allGranted else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self, !Task.isCancelled else { return }
                self.refresh()
                if self.allGranted { self.pollTask = nil; return }
            }
        }
    }

    /// 停止輪詢（設定頁的權限區消失時）。
    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    /// 跳出系統的輔助使用授權提示，並打開對應的系統設定頁。
    func requestAccessibility() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    /// 請求螢幕錄製權限；系統通常只在第一次顯示提示，之後需到系統設定手動開啟。
    func requestScreenRecording() {
        if !CGRequestScreenCaptureAccess() {
            open("x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
        }
    }

    /// 打開系統設定的「螢幕錄製」頁（第一次會先跳系統授權提示）。
    static func openScreenRecordingSettings() {
        if !CGRequestScreenCaptureAccess() {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
        }
    }

    /// 打開系統設定的「輔助使用」頁並跳出授權提示。
    static func openAccessibilitySettings() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    private func open(_ string: String) {
        if let url = URL(string: string) { NSWorkspace.shared.open(url) }
    }
}
