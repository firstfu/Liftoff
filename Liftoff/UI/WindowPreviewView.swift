//
//  WindowPreviewView.swift
//  Liftoff
//
//  視窗縮圖預覽框：貼在執行中 App 圖示的上方（空間不足時放下方），一排列出該 App 的視窗縮圖，點擊切換到該視窗。
//  尺寸由卡片數量直接計算，不需量測就能定位，出現時不會跳動。
//

import SwiftUI

struct WindowPreviewLayer: View {
    let model: LaunchpadModel
    let containerSize: CGSize

    var body: some View {
        let preview = model.preview
        if preview.isVisible, preview.appID != nil {
            let frame = Self.frame(for: preview, containerSize: containerSize)
            WindowPreviewPanel(model: model, preview: preview)
                .frame(width: frame.width, height: frame.height)
                .position(x: frame.midX, y: frame.midY)
                .transition(.scale(scale: 0.94, anchor: .bottom).combined(with: .opacity))
        }
    }

    /// 預覽框位置：圖示正上方（放不下就放下方），左右不超出螢幕。命中測試也用同一個計算。
    static func frame(for preview: WindowPreviewModel, containerSize: CGSize) -> CGRect {
        let size = size(for: preview)
        let anchor = preview.anchor
        let x = min(max(anchor.midX, size.width / 2 + 16), containerSize.width - size.width / 2 - 16)
        let above = anchor.minY - 12 - size.height
        let y = above > 8 ? above : anchor.maxY + 12
        return CGRect(x: x - size.width / 2, y: y, width: size.width, height: size.height)
    }

    static let thumbHeight: CGFloat = 132
    static let padding: CGFloat = 14
    static let spacing: CGFloat = 12

    /// 依卡片數量與狀態計算預覽框大小。
    static func size(for preview: WindowPreviewModel) -> CGSize {
        switch preview.status {
        case .ready where !preview.cards.isEmpty, .loading where !preview.cards.isEmpty:
            let count = CGFloat(max(1, preview.cards.count))
            return CGSize(
                width: count * WindowPreviewModel.cardWidth + (count - 1) * spacing + padding * 2,
                height: 30 + thumbHeight + 24 + padding * 2
            )
        case .needsPermission:
            return CGSize(width: 340, height: 112)
        default:
            return CGSize(width: 260, height: 92)
        }
    }
}

private struct WindowPreviewPanel: View {
    let model: LaunchpadModel
    let preview: WindowPreviewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(preview.appName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)
                .padding(.leading, 2)
            content
        }
        .padding(WindowPreviewLayer.padding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
        .environment(\.colorScheme, .dark)
        .onHover { preview.popoverHover($0) }
    }

    @ViewBuilder
    private var content: some View {
        switch preview.status {
        case .loading where preview.cards.isEmpty:
            ProgressView().controlSize(.small).frame(maxWidth: .infinity)
        case .noWindows:
            Text("沒有開啟的視窗").font(.system(size: 12)).foregroundStyle(.secondary)
        case .needsPermission:
            VStack(alignment: .leading, spacing: 10) {
                Text("需要「螢幕錄製」權限才能顯示視窗縮圖。")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Button("前往授權") {
                    model.requestDismiss?(.settings)
                    Permissions.openScreenRecordingSettings()
                }
                .buttonStyle(.glassProminent)
            }
        default:
            HStack(alignment: .top, spacing: WindowPreviewLayer.spacing) {
                ForEach(preview.cards) { card in
                    WindowCard(card: card) { preview.activate(card) }
                }
            }
        }
    }
}

private struct WindowCard: View {
    let card: WindowPreviewModel.Card
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        VStack(spacing: 7) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.white.opacity(hovering ? 0.16 : 0.07))
                if let image = card.image {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .clipShape(.rect(cornerRadius: 6))
                        .padding(6)
                        .opacity(card.window.isMinimized ? 0.6 : 1)
                } else {
                    Image(systemName: "macwindow")
                        .font(.system(size: 30, weight: .light))
                        .foregroundStyle(.tertiary)
                }
                if card.window.isMinimized || card.window.isOnOtherSpace {
                    Image(systemName: card.window.isMinimized ? "arrow.down.right.and.arrow.up.left" : "square.stack.3d.up")
                        .font(.system(size: 10, weight: .bold))
                        .padding(5)
                        .background(.black.opacity(0.55), in: .circle)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                        .padding(8)
                }
            }
            .frame(width: WindowPreviewModel.cardWidth, height: WindowPreviewLayer.thumbHeight)
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(.white.opacity(hovering ? 0.55 : 0), lineWidth: 1.5)
            }
            Text(card.window.title.isEmpty ? String(localized: "（無標題）") : card.window.title)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: WindowPreviewModel.cardWidth - 8)
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(perform: action)
        .animation(.snappy(duration: 0.15), value: hovering)
    }
}
