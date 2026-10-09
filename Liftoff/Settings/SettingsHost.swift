//
//  SettingsHost.swift
//  Liftoff
//
//  主程式這一端的設定 process 管理：需要時以同一個執行檔另開一個實例顯示設定，
//  並代為執行只有主程式能做的事（改版面、備份、暫停快速鍵）。為什麼要分 process 見 `SettingsIPC.swift`。
//

import AppKit

final class SettingsHost {
    /// 版面相關請求實際要做的事，由 `AppCoordinator` 提供（持有版面、App 清單與快速鍵）。
    struct Actions {
        /// 執行版面指令；失敗時丟出錯誤，訊息會原樣顯示在設定頁
        var perform: (SettingsIPC.Command, String?) throws -> Void
        var pauseHotKey: () -> Void
        var resumeHotKey: () -> Void
        var hotKeyRegistered: () -> Bool
        var openURL: (URL) -> Void
    }

    private let actions: Actions
    /// 目前的設定 process（沒開時為 nil）
    private var process: NSRunningApplication?
    /// 監看設定 process 結束
    private var exitWatch: DispatchSourceProcess?
    /// 正在啟動中：避免連按兩次開出兩個設定 process
    private var isLaunching = false
    /// 設定 process 是否在錄製快速鍵途中（它若異常結束，要替它把快速鍵註冊回來）
    private var hotKeyPaused = false

    init(actions: Actions) {
        self.actions = actions
        DistributedNotificationCenter.default().addObserver(forName: SettingsIPC.requestName, object: nil, queue: .main) { [weak self] note in
            guard let fields = SettingsIPC.fields(of: note) else { return }
            nonisolated(unsafe) let info = fields
            MainActor.assumeIsolated { self?.handle(info) }
        }
    }

    /// 顯示設定：已開著就帶到最前，否則啟動設定 process。
    func open() {
        if let process, !process.isTerminated {
            // 系統的協作式啟用：前景 App 得先讓出，對方的 activate 才會生效
            NSApp.yieldActivation(to: process)
            process.activate()
            SettingsIPC.post(SettingsIPC.replyName, to: process.processIdentifier, [SettingsIPC.Field.command: SettingsIPC.Command.focus.rawValue])
            return
        }
        guard !isLaunching else { return }
        isLaunching = true
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        configuration.arguments = [SettingsIPC.processFlag, String(getpid())]
        configuration.addsToRecentItems = false
        configuration.activates = true
        // macOS 14 起啟用是協作式的：前景 App 不先讓出，新 process 的 activate 會被系統忽略，視窗開在後面。
        // 啟動前先讓給「同 bundle ID 的 App」（設定 process 還不存在，只能用 bundle ID 指定），啟動後再對它本人讓一次
        if let bundleID = Bundle.main.bundleIdentifier { NSApp.yieldActivation(toApplicationWithBundleIdentifier: bundleID) }
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { [weak self] app, error in
            let message = error?.localizedDescription
            Task { @MainActor in
                guard let self else { return }
                self.isLaunching = false
                guard let app else {
                    Log.app.error("無法開啟設定：\(message ?? "unknown", privacy: .public)")
                    return
                }
                self.process = app
                let pid = app.processIdentifier
                self.exitWatch = SettingsIPC.watchExit(of: pid) { [weak self] in self?.processDidTerminate(pid: pid) }
                NSApp.yieldActivation(to: app)
                // 主程式此時多半是前景（剛處理完選單／網址／快速鍵），由前景 App 主動啟用對方是系統允許的
                app.activate()
                // 設定 process 自己第一次搶前景時，這邊可能還沒讓出；讓出之後請它再搶一次
                SettingsIPC.post(SettingsIPC.replyName, to: pid, [SettingsIPC.Field.command: SettingsIPC.Command.focus.rawValue])
                // 它一啟動就詢問的狀態可能早於這裡記下 pid 而被略過，補送一次
                self.broadcastState()
            }
        }
    }

    /// 快速鍵註冊結果改變時通知設定 process（設定頁顯示「已被占用」提示用）。
    func broadcastState() {
        guard let process, !process.isTerminated else { return }
        SettingsIPC.post(SettingsIPC.replyName, to: process.processIdentifier, [
            SettingsIPC.Field.command: SettingsIPC.Command.state.rawValue,
            SettingsIPC.Field.hotKeyRegistered: actions.hotKeyRegistered(),
        ])
    }

    private func handle(_ info: [String: Any]) {
        guard let raw = info[SettingsIPC.Field.command] as? String, let command = SettingsIPC.Command(rawValue: raw),
              let sender = info[SettingsIPC.Field.sender] as? Int else { return }
        let argument = info[SettingsIPC.Field.argument] as? String
        // 只受理目前這個設定 process 的請求：其他程式也能送 distributed notification
        guard pid_t(sender) == process?.processIdentifier else { return }
        switch command {
        case .pauseHotKey:
            hotKeyPaused = true
            actions.pauseHotKey()
        case .resumeHotKey:
            hotKeyPaused = false
            actions.resumeHotKey()
            broadcastState()
        case .state:
            broadcastState()
        case .openURL:
            if let argument, let url = URL(string: argument) { actions.openURL(url) }
        case .focus:
            break
        case .compact, .alphabetical, .importLegacy, .organize, .backup, .restore:
            var reply: [String: Any] = [SettingsIPC.Field.command: raw]
            if let id = info[SettingsIPC.Field.id] as? String { reply[SettingsIPC.Field.id] = id }
            do {
                try actions.perform(command, argument)
            } catch {
                reply[SettingsIPC.Field.error] = error.localizedDescription
            }
            SettingsIPC.post(SettingsIPC.replyName, to: pid_t(sender), reply)
        }
    }

    private func processDidTerminate(pid: pid_t) {
        guard pid == process?.processIdentifier else { return }
        Log.app.info("設定 process 結束（pid \(pid)），快速鍵暫停中：\(self.hotKeyPaused)")
        process = nil
        exitWatch = nil
        // 設定 process 在錄製途中當掉或被強制結束：替它恢復快速鍵，否則使用者要重開 Liftoff 才能用快速鍵
        if hotKeyPaused {
            hotKeyPaused = false
            actions.resumeHotKey()
        }
    }
}
