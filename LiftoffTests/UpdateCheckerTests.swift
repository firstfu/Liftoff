//
//  UpdateCheckerTests.swift
//  LiftoffTests
//
//  App 內更新交給 Sparkle，這裡鎖住會「安靜出錯」的設定：漏了公鑰 Sparkle 啟動就報錯、
//  feed 不是 https 會被拒、預設的自動更新被改掉（對外文案寫的是預設自動更新）。
//  測試宿主就是 Liftoff.app，所以 Bundle.main 讀到的是實際出貨的 Info.plist。
//

import Foundation
import Testing
@testable import Liftoff

struct UpdateCheckerTests {
    private let info = Bundle.main.infoDictionary ?? [:]

    @Test func feedIsHTTPSOnGitHubPages() throws {
        let feed = try #require((info["SUFeedURL"] as? String).flatMap(URL.init(string:)))
        #expect(feed.scheme == "https")
        #expect(feed.host == "firstfu.github.io")
    }

    @Test func hasEdDSAPublicKey() throws {
        let key = try #require(info["SUPublicEDKey"] as? String)
        // ed25519 公鑰 32 bytes，base64 後 44 字元
        #expect(Data(base64Encoded: key)?.count == 32)
    }

    @Test func automaticUpdatesAreOnByDefaultWithoutProfiling() {
        #expect(info["SUEnableAutomaticChecks"] as? Bool == true)
        #expect(info["SUAutomaticallyUpdate"] as? Bool == true)
        #expect(info["SUEnableSystemProfiling"] as? Bool != true)
    }

    /// 全新安裝（UserDefaults 沒有任何值）時兩個開關都是開的；使用者關掉後存下 false 就維持關閉。
    @Test func settingsDefaultToAutomaticUpdates() throws {
        let suite = "UpdateCheckerTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults)
        #expect(settings.autoChecksForUpdates)
        #expect(settings.autoInstallsUpdates)
        settings.autoChecksForUpdates = false
        #expect(AppSettings(defaults: defaults).autoChecksForUpdates == false)
    }
}
