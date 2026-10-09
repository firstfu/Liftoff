//
//  SettingsButtonView.swift
//  Liftoff
//
//  啟動台右上角淡淡的設定齒輪。選單列圖示可能被瀏海擋住或在系統設定被關掉（issue #12），
//  ⌘, 又不容易被發現，這裡給一個看得到的入口。平時壓得很淡不搶畫面，滑鼠移上去才變清楚。
//  和搜尋列一樣是純 AppKit：不在格線範圍內，點擊由 LaunchpadPanel 照常交給 AppKit。
//

import AppKit

final class SettingsButtonView: NSButton {
    /// 按鈕大小（點擊範圍比圖示大一些）
    static let size = CGSize(width: 32, height: 32)
    /// 平時與 hover 時的不透明度
    private static let idleAlpha: CGFloat = 0.35
    private static let hoverAlpha: CGFloat = 0.85

    private let model: LaunchpadModel
    private var loop: RenderLoop?
    private var isHovering = false

    init(model: LaunchpadModel) {
        self.model = model
        super.init(frame: CGRect(origin: .zero, size: Self.size))
        image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: String(localized: "設定"))?
            .withSymbolConfiguration(.init(pointSize: 15, weight: .regular))
        imagePosition = .imageOnly
        isBordered = false
        toolTip = String(localized: "設定")
        target = self
        action = #selector(openSettings)
        alphaValue = Self.idleAlpha
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
        // 顏色跟著背景深淺（同名稱文字）；資料夾開著時淡出，避免跟資料夾面板搶注意力
        loop = RenderLoop { [weak self] in self?.syncAppearance() }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    @objc private func openSettings() {
        model.requestSettings?()
    }

    override func mouseEntered(with event: NSEvent) {
        isHovering = true
        animateAlpha()
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
        animateAlpha()
    }

    /// 依背景深淺選圖示顏色，資料夾開著時隱藏。
    private func syncAppearance() {
        contentTintColor = model.labelsAreDark ? .black : .white
        let hidden = model.openFolderID != nil
        if isHidden != hidden {
            isHidden = hidden
            if hidden { isHovering = false }
            alphaValue = isHovering ? Self.hoverAlpha : Self.idleAlpha
        }
    }

    private func animateAlpha() {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            animator().alphaValue = isHovering ? Self.hoverAlpha : Self.idleAlpha
        }
    }
}
