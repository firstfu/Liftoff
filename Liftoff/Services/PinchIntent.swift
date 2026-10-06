//
//  PinchIntent.swift
//  Liftoff
//
//  分辨四指手勢是「捏合」還是「滑動」（issue #10）。
//  四指左右滑動切換桌面時，手掌整個平移；起手時手指張得較開的話，滑完收手時手指會自然收攏，
//  張開程度因此變小，只看 ratio 就會被當成捏合而打開啟動台。
//  分辨依據：捏合時手的重心幾乎不動（主要是指間距離變化），滑動時重心大幅平移。
//  在 ratio 還沒超出死區、尚未判定之前，重心平移先超過門檻就判定為滑動，整個手勢都不回報。
//  純邏輯、不碰觸控板，方便單元測試。
//

import Foundation

nonisolated struct PinchIntent: Sendable {
    enum Phase: Sendable { case undecided, pinch, swipe }

    /// ratio 偏離 1 超過這個量才判定為捏合（避免手指微動就把視窗叫出來）
    static let deadZone = 0.05
    /// 判定前重心平移超過「起始張開程度 × 這個倍數」就判定為滑動。
    /// 實機數據（2026-10-07，issue #10）：捏合在 ratio 過死區時 travel 為 0.011～0.025；
    /// 手指張開滑動、收手被誤判為捏合時為 0.082～0.246；而且切換桌面的滑動整段也只移動約 0.3，
    /// 所以門檻要落在兩群之間，不能用「滑動會移很遠」來估。
    static let swipeTravel = 0.05

    private(set) var phase = Phase.undecided

    /// 餵入一幀並回傳這幀是否該回報給呼叫端。
    /// - Parameters:
    ///   - ratio: 目前張開程度 ÷ 起始張開程度
    ///   - travel: 重心從起點平移的距離 ÷ 起始張開程度
    /// - Returns: 已判定為捏合時為 true；尚未判定或判定為滑動時為 false
    mutating func update(ratio: Double, travel: Double) -> Bool {
        switch phase {
        case .pinch:
            return true
        case .swipe:
            return false
        case .undecided:
            // 同一幀兩者都超過時當成滑動：誤開比漏開更打擾人
            if travel > Self.swipeTravel {
                phase = .swipe
                return false
            }
            if abs(ratio - 1) > Self.deadZone {
                phase = .pinch
                return true
            }
            return false
        }
    }
}
