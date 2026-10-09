//
//  PagerScrollTests.swift
//  LiftoffTests
//
//  滑鼠滾輪翻頁（issue #11）：平滑捲動工具（Logi Options+、Mos…）會把滾輪轉成
//  「連續捲動、但沒有手勢 phase」的事件，必須和一般滾輪一樣能翻頁。
//

import AppKit
import CoreGraphics
import Testing
@testable import Liftoff

@MainActor
struct PagerScrollTests {
    /// 合成一個捲動事件。
    /// - Parameters:
    ///   - dy: 垂直位移（負值 = 往下捲 = 下一頁）
    ///   - continuous: 是否為連續捲動（決定 `hasPreciseScrollingDeltas`）
    ///   - phase: 手勢 phase（0 = 無，觸控板才有）
    private func event(dy: Int32, continuous: Bool, phase: Int64 = 0) -> NSEvent {
        let cg = CGEvent(scrollWheelEvent2Source: nil, units: continuous ? .pixel : .line,
                         wheelCount: 1, wheel1: dy, wheel2: 0, wheel3: 0)!
        cg.setIntegerValueField(.scrollWheelEventIsContinuous, value: continuous ? 1 : 0)
        cg.setIntegerValueField(.scrollWheelEventScrollPhase, value: phase)
        return NSEvent(cgEvent: cg)!
    }

    @Test func plainWheelFlipsPage() {
        let pager = PagerState()
        pager.pageWidth = 1000
        let e = event(dy: -1, continuous: false)
        #expect(!e.hasPreciseScrollingDeltas)
        _ = pager.handleScroll(e, pageCount: 2)
        #expect(pager.page == 1)
    }

    /// 平滑捲動：一格滾輪被拆成一串無 phase 的連續捲動事件。
    @Test func smoothScrollingWheelFlipsPage() {
        let pager = PagerState()
        pager.pageWidth = 1000
        for _ in 0..<15 {
            let e = event(dy: -8, continuous: true)
            #expect(e.hasPreciseScrollingDeltas)
            #expect(e.phase.isEmpty && e.momentumPhase.isEmpty)
            _ = pager.handleScroll(e, pageCount: 2)
        }
        #expect(pager.page == 1)
    }

    /// 同一串平滑捲動只翻一頁；停頓後的下一串才再翻（避免滾一格翻好幾頁）。
    @Test func smoothScrollingFlipsOncePerStream() {
        let pager = PagerState()
        pager.pageWidth = 1000
        for _ in 0..<40 { _ = pager.handleScroll(event(dy: -8, continuous: true), pageCount: 3) }
        #expect(pager.page == 1)
        usleep(200_000)
        for _ in 0..<15 { _ = pager.handleScroll(event(dy: -8, continuous: true), pageCount: 3) }
        #expect(pager.page == 2)
    }

    /// 觸控板（有 phase）仍走跟手路徑，不會被當成滾輪直接翻頁。
    @Test func trackpadStillTracksFinger() {
        let pager = PagerState()
        pager.pageWidth = 1000
        _ = pager.handleScroll(event(dy: 0, continuous: true, phase: 1), pageCount: 2)
        _ = pager.handleScroll(event(dy: -30, continuous: true, phase: 2), pageCount: 2)
        #expect(pager.page == 0)
    }
}
