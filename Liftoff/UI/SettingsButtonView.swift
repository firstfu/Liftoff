//
//  SettingsButtonView.swift
//  Liftoff
//
//  啟動台右上角淡淡的設定齒輪。選單列圖示可能被瀏海擋住或在系統設定被關掉（issue #12），
//  ⌘, 又不容易被發現，這裡給一個看得到的入口。平時壓得很淡不搶畫面，滑鼠移上去才變清楚。
//  有新版本時右上角加一個小圓點、齒輪也不再壓淡，點進設定頁就看得到「有新版本」（低調提醒，見 UpdateChecker.swift）。
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
    /// 有新版本時的小圓點
    private let badge = CALayer()

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
        wantsLayer = true
        // NSButton 是翻轉座標（y 往下），y 取小值才在右上角
        badge.frame = CGRect(x: Self.size.width - 11, y: 4, width: 7, height: 7)
        badge.cornerRadius = 3.5
        badge.backgroundColor = NSColor.systemRed.cgColor
        badge.isHidden = true
        layer?.addSublayer(badge)
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
        if badge.isHidden == model.hasUpdateBadge {
            badge.isHidden = !model.hasUpdateBadge
            alphaValue = targetAlpha
        }
        let hidden = model.openFolderID != nil
        if isHidden != hidden {
            isHidden = hidden
            if hidden { isHovering = false }
            alphaValue = targetAlpha
        }
    }

    /// 平時壓淡；滑鼠移上去或有新版本時清楚顯示
    private var targetAlpha: CGFloat {
        isHovering || model.hasUpdateBadge ? Self.hoverAlpha : Self.idleAlpha
    }

    private func animateAlpha() {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            animator().alphaValue = targetAlpha
        }
    }
}
