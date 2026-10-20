//
//  UpdateCheckerTests.swift
//  LiftoffTests
//
//  App 內更新交給 Sparkle，這裡鎖住會「安靜出錯」的設定：漏了公鑰 Sparkle 啟動就報錯、
//  自動檢查預設被打開會違反「不主動連網」的隱私承諾、feed 不是 https 會被拒。
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

    @Test func automaticChecksAreOffByDefault() {
        #expect(info["SUEnableAutomaticChecks"] as? Bool == false)
        #expect(info["SUEnableSystemProfiling"] as? Bool != true)
    }
}
