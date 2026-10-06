//
//  PinchReleaseTests.swift
//  LiftoffTests
//
//  捏合放手的完成／回彈判斷：進度過門檻就完成；進度不足但放手前快速朝目標移動（又快又小的捏合，issue #9）也完成；
//  停住或往回收則回彈。
//

import Testing
@testable import Liftoff

struct PinchReleaseTests {
    /// 以 120Hz 依序餵入進度樣本。
    private func release(_ progresses: [Double], start: Double = 10) -> PinchRelease {
        var r = PinchRelease()
        for (i, p) in progresses.enumerated() { r.record(time: start + Double(i) / 120, progress: p) }
        return r
    }

    @Test func passingThresholdCommits() {
        #expect(release([0.2, 0.3, 0.45]).shouldCommit)
    }

    /// issue #9：約 80ms 內進度只走到 0.3，放手仍在移動 → 視為要開
    @Test func quickSmallPinchCommits() {
        let r = release(stride(from: 0.16, through: 0.3, by: 0.015).map { $0 })
        #expect(r.progress < PinchRelease.commitProgress)
        #expect(r.velocity >= PinchRelease.flickVelocity)
        #expect(r.shouldCommit)
    }

    /// 慢慢捏到一半停住再放手 → 回彈（原本的取消手感不變）
    @Test func slowPartialPinchThenHoldRebounds() {
        let r = release(Array(stride(from: 0.16, through: 0.3, by: 0.002)) + Array(repeating: 0.3, count: 30))
        #expect(r.velocity < PinchRelease.flickVelocity)
        #expect(!r.shouldCommit)
    }

    /// 捏進去又快速張回來 → 速度為負，回彈
    @Test func reversingRebounds() {
        let r = release([0.16, 0.25, 0.35, 0.3, 0.22, 0.15])
        #expect(r.velocity < 0)
        #expect(!r.shouldCommit)
    }

    /// 速度只看放手前的窗口：前段快、最後停了很久，不能被前段的速度帶過
    @Test func velocityOnlyCountsRecentWindow() {
        let r = release([0.16, 0.25, 0.3] + Array(repeating: 0.3, count: 40))
        #expect(r.velocity == 0)
        #expect(!r.shouldCommit)
    }

    @Test func singleSampleHasNoVelocity() {
        let r = release([0.2])
        #expect(r.velocity == 0)
        #expect(!r.shouldCommit)
    }

    @Test func resetClearsSamples() {
        var r = release([0.1, 0.2, 0.3])
        r.reset()
        #expect(r.progress == 0)
        #expect(r.velocity == 0)
    }
}
