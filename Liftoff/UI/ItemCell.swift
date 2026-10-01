//
//  ItemCell.swift
//  Liftoff
//
//  格子外觀狀態（純值），以及 SwiftUI 端少數需要顯示 App 圖示的地方（確認框、設定頁）共用的圖示 view。
//  格線本身由 Core Animation 繪製，見 Grid/GridLayers.swift。
//

import SwiftUI

/// 一格的外觀狀態。
nonisolated struct CellState: Equatable, Sendable {
    var isSelected = false
    var isPressed = false
    var isDragged = false
    var isMergeTarget = false
    var isRunning = false
}

/// 單一 App 圖示：只依賴自己的 IconImage，載入完成時只重畫這一個。
struct AppIconImage: View {
    let icon: IconImage
    let placeholder: CGImage?

    var body: some View {
        if let image = icon.cgImage ?? placeholder {
            Image(decorative: image, scale: 1)
                .resizable()
                .interpolation(.high)
        } else {
            RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white.opacity(0.15))
        }
    }
}
