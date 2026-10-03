//
//  UpdateCheckerTests.swift
//  LiftoffTests
//
//  檢查更新的純邏輯：版本號比較與 GitHub release JSON 解析。網路請求本身不在單元測試範圍。
//

import Foundation
import Testing
@testable import Liftoff

struct UpdateCheckerTests {
    @Test func comparesVersionsNumerically() {
        #expect(UpdateChecker.isNewer("1.1.2", than: "1.1.1"))
        #expect(UpdateChecker.isNewer("1.0.10", than: "1.0.9"))
        #expect(UpdateChecker.isNewer("2.0", than: "1.9.9"))
        #expect(!UpdateChecker.isNewer("1.1.1", than: "1.1.1"))
        #expect(!UpdateChecker.isNewer("1.1", than: "1.1.0"))
        #expect(!UpdateChecker.isNewer("1.0.9", than: "1.0.10"))
    }

    @Test func parsesReleaseJSON() throws {
        let json = #"{"tag_name":"v1.2.0","html_url":"https://github.com/firstfu/Liftoff/releases/tag/v1.2.0","name":"x"}"#
        let release = try #require(UpdateChecker.parseRelease(Data(json.utf8)))
        #expect(release.version == "1.2.0")
        #expect(release.url.absoluteString == "https://github.com/firstfu/Liftoff/releases/tag/v1.2.0")
    }

    @Test func rejectsMalformedJSON() {
        #expect(UpdateChecker.parseRelease(Data("{}".utf8)) == nil)
        #expect(UpdateChecker.parseRelease(Data("not json".utf8)) == nil)
    }
}
