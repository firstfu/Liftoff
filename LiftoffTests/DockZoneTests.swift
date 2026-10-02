//
//  DockZoneTests.swift
//  LiftoffTests
//
//  拖進 Dock 的感應區：依 visibleFrame 推出 Dock 方向與厚度；Dock 看不到時底部用加寬的感應帶、左右用細條，
//  以及自動隱藏時游標貼邊要先退開（Dock 只在「進入」邊緣時滑出）。
//

import CoreGraphics
import Testing
@testable import Liftoff

@MainActor
struct DockZoneTests {
    private let frame = CGRect(x: 0, y: 0, width: 1728, height: 1117)

    @Test func bottomDockUsesItsFullHeight() {
        let visible = CGRect(x: 0, y: 72, width: 1728, height: 1012)
        let zone = DockZone.make(frame: frame, visible: visible, coversDock: false, autohide: false, orientation: "bottom")
        #expect(zone == DockZone(rect: CGRect(x: 0, y: 0, width: 1728, height: 72), side: .bottom, needsReveal: false))
    }

    @Test func leftDockIsDetectedFromVisibleFrame() {
        let visible = CGRect(x: 64, y: 0, width: 1664, height: 1084)
        let zone = DockZone.make(frame: frame, visible: visible, coversDock: false, autohide: false, orientation: "bottom")
        #expect(zone?.rect == CGRect(x: 0, y: 0, width: 64, height: 1117))
        #expect(zone?.side == .left)
    }

    @Test func coveredSideDockOnlyUsesThinEdge() {
        // 左右側只用細條：不搶走拖到螢幕邊緣翻頁
        let visible = CGRect(x: 0, y: 0, width: 1664, height: 1084)
        let zone = DockZone.make(frame: frame, visible: visible, coversDock: true, autohide: false, orientation: "right")
        #expect(zone?.rect == CGRect(x: 1724, y: 0, width: 4, height: 1117))
    }

    @Test func autohideBottomUsesApproachBand() {
        let visible = CGRect(x: 0, y: 4, width: 1728, height: 1080)
        let zone = DockZone.make(frame: frame, visible: visible, coversDock: true, autohide: true, orientation: "bottom")
        #expect(zone == DockZone(rect: CGRect(x: 0, y: 0, width: 1728, height: 32), side: .bottom, needsReveal: true))
    }

    @Test func autohideSideFallsBackToPreferredEdge() {
        let visible = CGRect(x: 0, y: 4, width: 1728, height: 1080)
        let zone = DockZone.make(frame: frame, visible: visible, coversDock: false, autohide: true, orientation: "left")
        #expect(zone == DockZone(rect: CGRect(x: 0, y: 0, width: 4, height: 1117), side: .left, needsReveal: true))
    }

    @Test func noZoneWhenDockIsOnAnotherScreen() {
        let visible = CGRect(x: 0, y: 0, width: 1728, height: 1084)
        #expect(DockZone.make(frame: frame, visible: visible, coversDock: false, autohide: false, orientation: "bottom") == nil)
    }

    @Test func pullsBackOnlyWhenTouchingTheEdge() {
        let zone = DockZone(rect: CGRect(x: 0, y: 0, width: 1728, height: 32), side: .bottom, needsReveal: true)
        #expect(zone.pulledBack(CGPoint(x: 500, y: 0), in: frame) == CGPoint(x: 500, y: 8))
        #expect(zone.pulledBack(CGPoint(x: 500, y: 20), in: frame) == nil)
        let right = DockZone(rect: CGRect(x: 1724, y: 0, width: 4, height: 1117), side: .right, needsReveal: true)
        #expect(right.pulledBack(CGPoint(x: 1727.5, y: 300), in: frame) == CGPoint(x: 1720, y: 300))
    }
}
