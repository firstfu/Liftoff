//
//  UpdateChecker.swift
//  Liftoff
//
//  App 內更新（issue #6），交給 Sparkle。只在主程式建立；設定頁是另一個 process，透過 IPC 請主程式檢查。
//
//  - 預設每週自動檢查、背景下載並在使用者閒置時安裝（Info.plist 的 SUEnableAutomaticChecks／SUAutomaticallyUpdate = YES，
//    也讓 Sparkle 不跳「要不要自動檢查」的詢問）；只讀 appcast（https://firstfu.github.io/Liftoff/appcast.xml）與下載 zip。
//  - 使用者在設定頁關掉自動檢查後，除非自己按「檢查更新…」，Liftoff 不會連網。
//  - 不送系統資訊（Sparkle 的 system profiling 預設關，我們不開）。
//  - 開關的唯一事實源是 `AppSettings`（兩個 process 共用並同步），這裡只負責套用到 Sparkle。
//
//  自動檢查找到新版時不跳視窗（Sparkle 的 gentle reminders）：只在選單列圖示與啟動台的設定齒輪加小圓點，
//  使用者自己點了才打開 Sparkle 的更新視窗。手動「檢查更新…」照常直接顯示視窗。
//
//  沒有 Developer ID／公證：更新檔的真偽靠 EdDSA 簽名（公鑰在 Info.plist 的 SUPublicEDKey），
//  自簽憑證沒有 Team ID，所以 entitlements 要關 Library Validation 才載得進 Sparkle.framework。
//  細節見 docs/context/reference/modules/updates.md。
//

import AppKit
import Observation
import Sparkle

@Observable
final class UpdateChecker: NSObject {
    /// 背景下載好的更新，在使用者沒在用時才安裝的檢查間隔
    nonisolated static let idleCheckInterval: TimeInterval = 5 * 60
    /// 使用者多久沒操作鍵盤滑鼠才算「沒在用」
    nonisolated static let idleThreshold: TimeInterval = 2 * 60

    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private var controller: SPUStandardUpdaterController?
    /// Sparkle 交給我們的「立即安裝並重新啟動」；有值代表更新已下載好、等時機安裝
    @ObservationIgnored private var installNow: (() -> Void)?
    @ObservationIgnored private var idleTimer: Timer?
    /// 現在能不能安靜地重啟（由 `AppCoordinator` 提供：啟動台沒打開）
    @ObservationIgnored var canRestartQuietly: () -> Bool = { true }
    /// 自動檢查找到、還沒給使用者看過的新版本；有值時選單列與設定齒輪顯示小圓點
    private(set) var availableVersion: String?

    init(settings: AppSettings) {
        self.settings = settings
    }

    /// 啟動 Sparkle 並套用設定。只在主程式呼叫一次。
    func start() {
        let controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: self, userDriverDelegate: self)
        self.controller = controller
        applySettings()
        // 設定錯誤（例如沒有公鑰）時 Sparkle 會自己跳提示；不阻擋 App 其餘功能
        controller.startUpdater()
    }

    /// 把 `AppSettings` 的開關套用到 Sparkle。自動安裝必須搭配自動檢查才有意義。
    func applySettings() {
        guard let updater = controller?.updater else { return }
        updater.automaticallyChecksForUpdates = settings.autoChecksForUpdates
        updater.automaticallyDownloadsUpdates = settings.autoChecksForUpdates && settings.autoInstallsUpdates
    }

    /// 選單或設定頁的「檢查更新…」：由 Sparkle 顯示結果與安裝視窗。
    /// 已有自動檢查找到的新版時，Sparkle 會直接接續那次結果，不重新下載清單。
    func checkForUpdates() {
        guard let controller else { return }
        NSApp.activate()
        controller.checkForUpdates(nil)
    }

    // MARK: - 背景安裝

    /// 更新已下載好：定期看時機，使用者沒在用啟動台、也一陣子沒操作時才重啟安裝。
    /// 計時器只在有待安裝的更新時存在，平常閒置 0% CPU 不受影響。
    private func scheduleQuietInstall(_ install: @escaping () -> Void) {
        installNow = install
        idleTimer?.invalidate()
        let timer = Timer(timeInterval: Self.idleCheckInterval, repeats: true) { _ in
            MainActor.assumeIsolated { [weak self] in self?.installIfIdle() }
        }
        timer.tolerance = 60
        RunLoop.main.add(timer, forMode: .common)
        idleTimer = timer
    }

    private func installIfIdle() {
        guard let installNow, canRestartQuietly() else { return }
        // ~0 是 kCGAnyInputEventType：任何鍵盤滑鼠觸控板輸入
        let idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
        guard idle >= Self.idleThreshold else { return }
        Log.app.notice("背景更新：使用者閒置 \(Int(idle))s，重新啟動以安裝")
        idleTimer?.invalidate()
        idleTimer = nil
        self.installNow = nil
        installNow()
    }
}

extension UpdateChecker: SPUUpdaterDelegate {
    /// 更新已在背景下載好、預定在結束時安裝。Liftoff 常駐、幾乎不會結束，所以改成閒置時主動安裝。
    /// - Returns: true 表示由我們決定何時安裝（仍保留結束時安裝）
    func updater(_ updater: SPUUpdater, willInstallUpdateOnQuit item: SUAppcastItem, immediateInstallationBlock: @escaping () -> Void) -> Bool {
        Log.app.notice("背景更新：\(item.displayVersionString, privacy: .public) 已下載，等閒置時安裝")
        scheduleQuietInstall(immediateInstallationBlock)
        return true
    }
}

extension UpdateChecker: SPUStandardUserDriverDelegate {
    /// 宣告支援低調提醒：自動檢查找到新版時，Sparkle 不自己跳視窗，交給我們決定怎麼提醒。
    var supportsGentleScheduledUpdateReminders: Bool { true }

    /// 自動檢查找到新版時是否由 Sparkle 直接顯示視窗。一律不要：Liftoff 是背景工具，突然跳窗會打斷使用者。
    func standardUserDriverShouldHandleShowingScheduledUpdate(_ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool) -> Bool {
        false
    }

    /// 即將顯示（或由我們接手提醒）某個更新。由我們接手時記下版本，讓 UI 顯示小圓點。
    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        guard !handleShowingUpdate else { return }
        availableVersion = update.displayVersionString
        Log.app.notice("自動檢查：有新版本 \(update.displayVersionString, privacy: .public)，以小圓點提醒")
    }

    /// 使用者已經看到更新視窗：拿掉小圓點（按「稍後提醒我」的話，下次自動檢查會再提醒）。
    func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        availableVersion = nil
    }

    /// 這次更新流程結束（安裝、跳過或關掉）。
    func standardUserDriverWillFinishUpdateSession() {
        availableVersion = nil
    }
}
