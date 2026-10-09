//
//  LiftoffApp.swift
//  Liftoff
//
//  App 進入點。預設在 Dock 顯示圖示（點它就打開啟動台，和經典啟動台一樣），可在設定改成只在選單列。
//  實際工作由 AppCoordinator 統籌。
//  同一個執行檔也用來跑設定頁：以 `--settings-process <主程式 pid>` 啟動時只顯示設定視窗（見 `SettingsProcess.swift`）。
//

import SwiftUI

@main
struct LiftoffApp: App {
    /// 必須排在所有屬性之前：上次素材產生若沒正常結束，要在 AppSettings／版面被讀進記憶體之前把檔案還原（屬性依宣告順序初始化）
    /// 設定 process 不做：素材產生是主程式的事，設定 process 去還原會和主程式搶著改檔案
    private let demoRecovery: Void = SettingsProcess.isActive ? () : DemoShots.restoreIfInterrupted()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var settings = AppSettings.shared

    var body: some Scene {
        // 設定頁跑在另一個 process（見 SettingsProcess.swift），那個 process 不顯示選單列圖示
        MenuBarExtra("Liftoff", systemImage: "square.grid.3x3.fill", isInserted: SettingsProcess.isActive ? .constant(false) : $settings.showsMenuBarIcon) {
            MenuContent()
        }
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("設定…") {
                    // 設定 process 本身就是設定視窗；不能在那裡碰 AppCoordinator（會把整套啟動台服務建起來）
                    if !SettingsProcess.isActive { AppCoordinator.shared.openSettings() }
                }
                .keyboardShortcut(",")
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // 作為單元測試宿主時不啟動任何服務（不顯示啟動台、不註冊快速鍵）
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        if SettingsProcess.isActive {
            SettingsProcess.start()
            return
        }
        let coordinator = AppCoordinator.shared
        coordinator.launch()

        let arguments = CommandLine.arguments
        if arguments.contains("--register-login-item") {
            AppSettings.shared.launchAtLogin = true
        }
        if arguments.contains("--selftest-preview") {
            Task { await SelfTest.runPreviewTest(coordinator: coordinator) }
        } else if arguments.contains("--selftest-profile") {
            Task { await SelfTest.profileLoop(coordinator: coordinator) }
        } else if let output = DemoShots.outputDirectory {
            Task {
                await DemoShots.run(coordinator: coordinator, output: output)
                NSApp.terminate(nil)
            }
        } else if SelfTest.isRequested {
            Task { await SelfTest.run(coordinator: coordinator) }
        } else if !arguments.contains("--background") && !Self.launchedAsLoginItem {
            // 使用者手動打開（例如點 Dock 上的圖示）時直接顯示啟動台；開機自動啟動時保持安靜
            Task { await coordinator.showAfterLaunch() }
        }
    }

    /// 點 Dock 圖示（App 已在執行）：切換啟動台。
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if SettingsProcess.isActive {
            SettingsProcess.forward(URL(string: "liftoff://toggle")!)
            return false
        }
        AppCoordinator.shared.toggle()
        return false
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where url.scheme == "liftoff" {
            // 有兩個 Liftoff 實例時，系統可能把網址送到設定 process，轉交主程式
            if SettingsProcess.isActive { SettingsProcess.forward(url) } else { AppCoordinator.shared.handle(url: url) }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        // 設定 process 沒有版面、也沒動過系統手勢，不可以在這裡存檔或還原（會蓋掉主程式的狀態）
        guard !SettingsProcess.isActive else { return }
        AppCoordinator.shared.layoutStore.saveNow()
        // 結束後我們的手勢就沒人處理了，把系統捏合手勢還給使用者（下次啟動會再關掉）
        SystemGesture.restoreSystemPinch()
    }

    /// 是否由「登入項目」啟動（開機自動執行）。依序判斷：
    /// 1. 啟動事件帶有「以登入項目啟動」旗標（傳統登入項目）
    /// 2. 啟動事件由 loginwindow 送出，或根本沒有啟動事件（SMAppService 由 launchd 直接啟動）
    /// 3. 剛開機不到 3 分鐘
    /// 使用者手動打開（點 Dock、Finder、Spotlight）時啟動事件會來自這些 App，因此會正常顯示啟動台。
    private static var launchedAsLoginItem: Bool {
        if ProcessInfo.processInfo.systemUptime < 180 { return true }
        guard let event = NSAppleEventManager.shared().currentAppleEvent else { return true }
        if event.eventID == kAEOpenApplication,
           event.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem {
            return true
        }
        if let pid = event.attributeDescriptor(forKeyword: keySenderPIDAttr)?.int32Value,
           let sender = NSRunningApplication(processIdentifier: pid_t(pid)) {
            return sender.bundleIdentifier == "com.apple.loginwindow"
        }
        return false
    }
}

/// 選單列下拉選單。
private struct MenuContent: View {
    var body: some View {
        Button("打開啟動台") { AppCoordinator.shared.show() }
        Divider()
        Button("設定…") { AppCoordinator.shared.openSettings() }
            .keyboardShortcut(",")
        Divider()
        if let update = AppCoordinator.shared.updates.availableUpdate {
            Button("有新版本：\(update.version)…") { AppInfo.open(update.url) }
        } else {
            Button("檢查更新…") { Task { await AppCoordinator.shared.updates.checkAndAnnounce() } }
        }
        Button("回報問題…") { AppInfo.open(AppInfo.reportProblemURL) }
        Divider()
        Button("結束 Liftoff") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
