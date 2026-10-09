//
//  AppSettingsSyncTests.swift
//  LiftoffTests
//
//  設定頁跑在另一個 process，兩邊靠同一個 UserDefaults 網域同步（`AppSettings.reload`）。
//  這裡用兩個 AppSettings 共用一個獨立的 suite 模擬「主程式」與「設定 process」，驗證同步邏輯本身；
//  跨 process 的 KVO 通知是系統行為，已在實機驗證（約 30ms 送達），不在單元測試範圍。
//

import Foundation
import Testing
@testable import Liftoff

@MainActor
struct AppSettingsSyncTests {
    /// 每個測試一個全新的 suite，結束時清掉
    private static func makeDefaults() -> (UserDefaults, String) {
        let name = "com.firstfu.Liftoff.tests.\(UUID().uuidString)"
        return (UserDefaults(suiteName: name)!, name)
    }

    @Test func reloadPicksUpValuesWrittenByTheOtherSide() {
        let (defaults, name) = Self.makeDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let host = AppSettings(defaults: defaults)
        let settingsProcess = AppSettings(defaults: defaults)

        settingsProcess.columns = 9
        settingsProcess.compactMargins = true
        settingsProcess.backgroundStyle = .preset
        settingsProcess.hotKey = nil
        settingsProcess.hiddenApps = ["/Applications/Chess.app"]
        settingsProcess.extraDirectories = ["/Volumes/External/Apps"]
        #expect(host.columns == 7)

        host.reload()
        #expect(host.columns == 9)
        #expect(host.compactMargins)
        #expect(host.backgroundStyle == .preset)
        #expect(host.hotKey == nil)
        #expect(host.hiddenApps == ["/Applications/Chess.app"])
        #expect(host.extraDirectories == ["/Volumes/External/Apps"])
    }

    /// 重新讀取期間不可寫回：否則拖滑桿時這邊寫回的舊值會蓋掉對方剛寫的新值
    @Test func reloadDoesNotWriteBack() {
        let (defaults, name) = Self.makeDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let host = AppSettings(defaults: defaults)
        let settingsProcess = AppSettings(defaults: defaults)

        settingsProcess.iconScale = 1.2
        host.reload()
        #expect(host.iconScale == 1.2)
        // 對方接著寫了更新的值；這邊若在 reload 時寫回過，就會在下面這次 reload 前把 1.2 蓋回去
        settingsProcess.iconScale = 1.3
        #expect(defaults.double(forKey: "iconScale") == 1.3)
        host.reload()
        #expect(host.iconScale == 1.3)
    }

    /// 本地修改照常寫入（reload 結束後不能殘留「略過寫入」的狀態）
    @Test func localChangesStillPersistAfterReload() {
        let (defaults, name) = Self.makeDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = AppSettings(defaults: defaults)
        settings.reload()
        settings.rows = 6
        #expect(defaults.integer(forKey: "rows") == 6)
    }

    /// Dock 與選單列圖示至少留一個的規則，在同步過來的值上也成立
    @Test func reloadKeepsAtLeastOneEntryPoint() {
        let (defaults, name) = Self.makeDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let host = AppSettings(defaults: defaults)
        let settingsProcess = AppSettings(defaults: defaults)

        settingsProcess.showsDockIcon = false
        #expect(settingsProcess.showsMenuBarIcon)
        host.reload()
        #expect(!host.showsDockIcon)
        #expect(host.showsMenuBarIcon)
    }
}
