//
//  SettingsProcess.swift
//  Liftoff
//
//  設定 process 這一端：以 `--settings-process <主程式 pid>` 啟動時只顯示設定視窗，不啟動任何啟動台服務；
//  視窗關掉就結束整個 process，設定頁用掉的記憶體全數還給系統。為什麼要分 process 見 `SettingsIPC.swift`。
//

import AppKit
import Observation

/// 設定頁需要的資料與動作。設定值直接讀寫 `AppSettings`（UserDefaults 兩邊共用），
/// 只有主程式能做的事（改版面、備份、暫停快速鍵）透過 `SettingsIPC` 請主程式執行。
@Observable
final class SettingsContext {
    let settings: AppSettings
    let updates: UpdateChecker
    let permissions = Permissions()
    /// App 清單：讀主程式寫在磁碟上的索引，只用來顯示名稱與智慧整理預覽，不掃描、不監看
    let catalog = AppCatalog()
    /// 主程式的快速鍵是否註冊成功（被其他 App 占用時為 false）
    private(set) var hotKeyRegistered = true

    @ObservationIgnored private let hostPID: pid_t?
    @ObservationIgnored private var pending: [String: CheckedContinuation<String?, Never>] = [:]
    /// 主程式要求把視窗帶到最前時呼叫
    @ObservationIgnored var onFocusRequest: (() -> Void)?

    /// - Parameters:
    ///   - settings: 設定值
    ///   - hostPID: 主程式 pid；nil 表示沒有主程式（Xcode 預覽），需要主程式的動作直接略過
    init(settings: AppSettings, hostPID: pid_t?) {
        self.settings = settings
        self.hostPID = hostPID
        updates = UpdateChecker(settings: settings)
        catalog.loadIndex()
        guard hostPID != nil else { return }
        DistributedNotificationCenter.default().addObserver(forName: SettingsIPC.replyName, object: nil, queue: .main) { [weak self] note in
            guard let fields = SettingsIPC.fields(of: note) else { return }
            nonisolated(unsafe) let info = fields
            MainActor.assumeIsolated { self?.handleReply(info) }
        }
        send(.state)
    }

    /// 快速鍵錄製開始／結束：請主程式暫停或恢復全域快速鍵。
    func setHotKeyRecording(_ recording: Bool) {
        send(recording ? .pauseHotKey : .resumeHotKey)
    }

    /// 請主程式執行版面指令並等待結果。
    /// - Parameters:
    ///   - command: 版面指令
    ///   - argument: 指令參數（還原時為備份檔路徑）
    /// - Returns: 失敗時的錯誤訊息；成功為 nil
    func perform(_ command: SettingsIPC.Command, argument: String? = nil) async -> String? {
        guard hostPID != nil else { return nil }
        let id = UUID().uuidString
        return await withCheckedContinuation { continuation in
            pending[id] = continuation
            var fields: [String: Any] = [SettingsIPC.Field.id: id]
            if let argument { fields[SettingsIPC.Field.argument] = argument }
            send(command, fields)
            // 主程式沒回應（例如已結束）時不要讓按鈕永遠等下去
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(5))
                self?.pending.removeValue(forKey: id)?.resume(returning: String(localized: "Liftoff 沒有回應，請稍後再試"))
            }
        }
    }

    /// App 圖示：直接向系統取，不經過主程式的圖示快取（避免寫入不同尺寸的快取檔）。
    func icon(for id: String) -> NSImage? {
        catalog.entry(id).map { NSWorkspace.shared.icon(forFile: $0.resolvedPath) }
    }

    func name(for id: String) -> String {
        catalog.entry(id)?.name ?? id
    }

    func backups() -> [LayoutStore.Backup] {
        LayoutStore().backups()
    }

    /// 刪除備份只是刪檔，不必經過主程式。
    func deleteBackup(_ backup: LayoutStore.Backup) {
        LayoutStore().deleteBackup(backup)
    }

    private func send(_ command: SettingsIPC.Command, _ fields: [String: Any] = [:]) {
        guard let hostPID else { return }
        var info = fields
        info[SettingsIPC.Field.command] = command.rawValue
        SettingsIPC.post(SettingsIPC.requestName, to: hostPID, info)
    }

    private func handleReply(_ info: [String: Any]) {
        guard let raw = info[SettingsIPC.Field.command] as? String, let command = SettingsIPC.Command(rawValue: raw) else { return }
        switch command {
        case .state:
            if let registered = info[SettingsIPC.Field.hotKeyRegistered] as? Bool { hotKeyRegistered = registered }
        case .focus:
            onFocusRequest?()
        default:
            guard let id = info[SettingsIPC.Field.id] as? String else { return }
            pending.removeValue(forKey: id)?.resume(returning: info[SettingsIPC.Field.error] as? String)
        }
    }
}

/// 設定 process 的進入點與生命週期。
enum SettingsProcess {
    /// 主程式 pid；不是設定 process 時為 nil
    static let hostPID = SettingsIPC.hostPID
    static var isActive: Bool { hostPID != nil }

    private static var context: SettingsContext?
    private static let windowController = SettingsWindowController()
    private static var keyMonitor: Any?
    private static var hostWatch: DispatchSourceProcess?

    /// 顯示設定視窗；視窗關掉或主程式結束時整個 process 跟著結束。
    static func start() {
        // 不出現在 Dock：Dock 上已經有主程式的圖示，兩個一樣的圖示會讓人分不清
        NSApp.setActivationPolicy(.accessory)
        let settings = AppSettings.shared
        settings.startExternalSync()
        let context = SettingsContext(settings: settings, hostPID: hostPID)
        self.context = context
        let window = windowController.show(context: context)
        // 下一輪再結束：讓 view 樹的 onDisappear（結束快速鍵錄製、停止權限輪詢）先跑完
        windowController.onClose = { Task { @MainActor in NSApp.terminate(nil) } }
        context.onFocusRequest = { bringToFront(window) }
        bringToFront(window)
        installKeyMonitor()
        // 主程式結束後設定頁已無法套用版面指令，跟著結束
        if let hostPID { hostWatch = SettingsIPC.watchExit(of: hostPID) { NSApp.terminate(nil) } }
    }

    /// 把外部控制（liftoff://、點 Dock 圖示）轉交主程式：系統可能把它們送到設定 process 這個實例。
    static func forward(_ url: URL) {
        guard let hostPID else { return }
        SettingsIPC.post(SettingsIPC.requestName, to: hostPID, [
            SettingsIPC.Field.command: SettingsIPC.Command.openURL.rawValue,
            SettingsIPC.Field.argument: url.absoluteString,
        ])
    }

    /// 帶到最前並成為 key window；剛啟動時系統可能還沒讓我們成為前景，150ms 後再補一次。
    private static func bringToFront(_ window: NSWindow) {
        Task { @MainActor in
            for delay in [Duration.zero, .milliseconds(150)] {
                try? await Task.sleep(for: delay)
                NSApp.activate()
                // 私有 API 可指定視窗前置；不可用時（回 false）退回公開 API
                _ = SkyLight.focus(pid: ProcessInfo.processInfo.processIdentifier, windowID: CGWindowID(window.windowNumber))
                window.makeKeyAndOrderFront(nil)
                window.orderFrontRegardless()
            }
        }
    }

    /// accessory App 沒有選單列，⌘W／⌘Q 不會經過選單項目，自己攔下來關視窗。
    private static func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard flags == .command, let key = event.charactersIgnoringModifiers?.lowercased(), key == "w" || key == "q" else { return event }
            // 開著對話框或選檔視窗時交給它們自己處理
            guard let window = windowController.currentWindow, window.isKeyWindow, window.attachedSheet == nil else { return event }
            window.performClose(nil)
            return nil
        }
    }
}
