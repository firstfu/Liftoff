//
//  PinchIntentTests.swift
//  LiftoffTests
//
//  四指手勢的捏合／滑動分辨（issue #10）：重心幾乎不動、指距變化才是捏合；
//  重心先大幅平移就是滑動，之後手指收攏也不能被當成捏合。
//

import Testing
@testable import Liftoff

struct PinchIntentTests {
    /// 依序餵入 (ratio, travel)，回傳每幀是否回報。
    private func run(_ frames: [(Double, Double)]) -> (PinchIntent, [Bool]) {
        var intent = PinchIntent()
        let reports = frames.map { intent.update(ratio: $0.0, travel: $0.1) }
        return (intent, reports)
    }

    @Test func smallMovementStaysUndecided() {
        let (intent, reports) = run([(0.99, 0.01), (1.02, 0.03), (0.97, 0.04)])
        #expect(intent.phase == .undecided)
        #expect(!reports.contains(true))
    }

    /// 實機捏合：過死區時 travel 約 0.01～0.03
    @Test func pinchIsReportedOnceItLeavesDeadZone() {
        let (intent, reports) = run([(0.98, 0.01), (0.94, 0.025), (0.85, 0.04), (0.7, 0.2)])
        #expect(intent.phase == .pinch)
        #expect(reports == [false, true, true, true])
    }

    /// 張開關閉同樣成立
    @Test func spreadIsReportedAsPinch() {
        let (intent, _) = run([(1.03, 0.01), (1.08, 0.02)])
        #expect(intent.phase == .pinch)
    }

    /// issue #10：手指張開起手滑動，滑完收攏——重心早已平移，整個手勢都不回報
    @Test func contractionAfterSwipeIsIgnored() {
        let (intent, reports) = run([(1.0, 0.03), (0.98, 0.06), (0.945, 0.08), (0.8, 0.2), (0.6, 0.3)])
        #expect(intent.phase == .swipe)
        #expect(!reports.contains(true))
    }

    /// 已判定為捏合後手部漂移不會中斷跟手
    @Test func driftAfterPinchKeepsReporting() {
        let (intent, reports) = run([(0.9, 0.02), (0.8, 0.5), (0.7, 1.0)])
        #expect(intent.phase == .pinch)
        #expect(reports == [true, true, true])
    }

    /// 同一幀兩者都超過時寧可不開
    @Test func ambiguousFrameIsSwipe() {
        let (intent, _) = run([(0.9, 0.5)])
        #expect(intent.phase == .swipe)
    }
}
