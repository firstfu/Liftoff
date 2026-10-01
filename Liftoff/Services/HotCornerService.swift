//
//  HotCornerService.swift
//  Liftoff
//
//  螢幕熱角：在每個螢幕的指定角落放一個 2×2 點、幾乎全透明的小面板，以追蹤區偵測游標進入。
//  為什麼不用全域滑鼠監聽：全域 mouseMoved 監聽會讓 App 在游標每動一下就被喚醒；
//  角落面板只在游標真的碰到角落時才收到事件，平時 CPU 使用為零。
//

import AppKit

final class HotCornerService {
    private var panels: [NSPanel] = []
    private var corner: HotCorner = .none
    private var screenObserver: NSObjectProtocol?
    private var lastFire = ContinuousClock.now - .seconds(10)
    /// 游標進入熱角時呼叫，參數為該角落所在的螢幕
    var onTrigger: ((NSScreen) -> Void)?

    /// 設定熱角位置（`.none` 關閉）；螢幕配置改變時自動重建。
    func configure(_ corner: HotCorner) {
        self.corner = corner
        rebuild()
        if screenObserver == nil {
            screenObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.rebuild() }
            }
        }
    }

    private func rebuild() {
        panels.forEach { $0.orderOut(nil) }
        panels.removeAll()
        guard corner != .none else { return }
        for screen in NSScreen.screens {
            let panel = makePanel(for: screen)
            panel.orderFrontRegardless()
            panels.append(panel)
        }
    }

    private func makePanel(for screen: NSScreen) -> NSPanel {
        let side: CGFloat = 2
        let frame = screen.frame
        let origin: CGPoint = switch corner {
        case .topLeft, .none: CGPoint(x: frame.minX, y: frame.maxY - side)
        case .topRight: CGPoint(x: frame.maxX - side, y: frame.maxY - side)
        case .bottomLeft: CGPoint(x: frame.minX, y: frame.minY)
        case .bottomRight: CGPoint(x: frame.maxX - side, y: frame.minY)
        }
        let panel = NSPanel(
            contentRect: CGRect(origin: origin, size: CGSize(width: side, height: side)),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false
        )
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        // 近乎全透明但非 0：完全透明的像素不參與滑鼠命中判定
        panel.backgroundColor = NSColor.black.withAlphaComponent(0.01)
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = false
        panel.isReleasedWhenClosed = false
        let view = CornerView(frame: CGRect(origin: .zero, size: panel.frame.size))
        view.onEnter = { [weak self, weak screen] in
            guard let self, let screen else { return }
            self.fire(screen)
        }
        panel.contentView = view
        return panel
    }

    private func fire(_ screen: NSScreen) {
        // 拖曳視窗到角落時不觸發；短時間內重複進入只算一次
        guard NSEvent.pressedMouseButtons == 0, ContinuousClock.now - lastFire > .milliseconds(600) else { return }
        lastFire = .now
        onTrigger?(screen)
    }
}

/// 角落面板的內容：追蹤游標進入。
private final class CornerView: NSView {
    var onEnter: (() -> Void)?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }

    override func mouseEntered(with event: NSEvent) {
        onEnter?()
    }
}
