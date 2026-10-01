//
//  LaunchpadWindowController.swift
//  Liftoff
//
//  啟動台視窗：全螢幕的非啟用（non-activating）面板。
//  - 非啟用面板：像 Spotlight 一樣可以接收鍵盤輸入，卻不會把目前的 App 切到背景；收起時焦點自然回到原本的 App
//  - 視窗與 SwiftUI 畫面在 App 啟動時就建好、之後只 orderFront/orderOut，打開時不必重建任何 view
//  - 顯示/收起動畫全部交給 Core Animation（在 render server 執行），主執行緒忙碌也不會掉幀
//  - 背景是獨立圖層：預先算好的模糊桌布（靜態貼圖）或即時模糊（NSVisualEffectView）
//

import AppKit
import QuartzCore
import SwiftUI

/// 攔截鍵盤與捲動事件的面板。
final class LaunchpadPanel: NSPanel {
    /// 回傳 true 表示已處理、不再往下傳（例如方向鍵、Esc）
    var keyHandler: ((NSEvent) -> Bool)?
    var scrollHandler: ((NSEvent) -> Bool)?
    var mouseHandler: ((NSEvent) -> Bool)?
    /// 自我測試期間只接受合成的滑鼠事件：使用者同時移動真實滑鼠時，真實事件會蓋掉測試的游標位置
    var acceptsSyntheticMouseOnly = false
    /// 自我測試合成滑鼠事件使用的事件編號（用來分辨真實事件）
    static let syntheticEventNumber = 0x5E1F

    init() {
        super.init(
            contentRect: CGRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        isFloatingPanel = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        hidesOnDeactivate = false
        isMovable = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        becomesKeyOnlyIfNeeded = false
        acceptsMouseMovedEvents = true
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        if acceptsSyntheticMouseOnly {
            switch event.type {
            case .mouseMoved, .mouseEntered, .mouseExited, .leftMouseDown, .leftMouseUp, .leftMouseDragged, .rightMouseDown, .rightMouseUp:
                if event.eventNumber != Self.syntheticEventNumber { return }
            default:
                break
            }
        }
        switch event.type {
        case .keyDown:
            // 中文輸入法選字中（有未確認的組字）：方向鍵、Enter、Esc 都屬於輸入法，不能攔
            if let editor = firstResponder as? NSTextView, editor.hasMarkedText() { break }
            if keyHandler?(event) == true { return }
        case .scrollWheel:
            if scrollHandler?(event) == true { return }
        case .leftMouseDown, .leftMouseDragged, .leftMouseUp, .rightMouseDown, .mouseMoved:
            if mouseHandler?(event) == true { return }
        default:
            break
        }
        super.sendEvent(event)
    }
}

/// 背景圖層：靜態模糊圖或即時模糊。
final class BackgroundView: NSView {
    private let imageLayer = CALayer()
    private lazy var liveBlur: NSVisualEffectView = {
        let view = NSVisualEffectView(frame: bounds)
        view.autoresizingMask = [.width, .height]
        view.blendingMode = .behindWindow
        view.material = .fullScreenUI
        view.state = .active
        return view
    }()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        imageLayer.contentsGravity = .resizeAspectFill
        imageLayer.masksToBounds = true
        imageLayer.actions = ["contents": NSNull(), "bounds": NSNull(), "position": NSNull()]
        layer?.addSublayer(imageLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        imageLayer.frame = bounds
        CATransaction.commit()
    }

    /// 顯示預先算好的背景圖。
    func show(image: CGImage) {
        if liveBlur.superview != nil { liveBlur.removeFromSuperview() }
        layer?.backgroundColor = NSColor.black.cgColor
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        imageLayer.contents = image
        imageLayer.isHidden = false
        CATransaction.commit()
    }

    /// 改用即時模糊（透出後方視窗與桌面）。
    func showLiveBlur() {
        imageLayer.isHidden = true
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.12).cgColor
        if liveBlur.superview == nil {
            liveBlur.frame = bounds
            addSubview(liveBlur)
        }
    }
}

/// 以左上為原點的容器 view。
final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

final class LaunchpadWindowController {
    let panel = LaunchpadPanel()
    private let model: LaunchpadModel
    private let settings: AppSettings
    private let wallpapers: WallpaperProvider
    private let container = NSView()
    private let backgroundView = BackgroundView(frame: .zero)
    /// 內容層（格線圖層 + SwiftUI），顯示/收起時整層縮放；翻轉座標讓子 view 的 frame 與 SwiftUI 一樣以左上為原點
    private let contentView = FlippedView()
    private let hostingView: NSHostingView<LaunchpadRootView>
    /// 搜尋列是純 AppKit（見 SearchBarView）：打字完全不經過 SwiftUI 排版
    private let searchBar: SearchBarView
    private var searchLoop: RenderLoop?
    let renderer: GridRenderer
    private var hideGeneration = 0
    private var observers: [NSObjectProtocol] = []

    private(set) var isVisible = false
    /// 最近一次開始顯示的時間（效能量測用）
    private(set) var lastShowStartedAt: ContinuousClock.Instant?
    /// 啟動台收起後呼叫（協調者決定是否把焦點還給原本的 App）
    var onHide: ((DismissReason) -> Void)?

    init(model: LaunchpadModel, settings: AppSettings, wallpapers: WallpaperProvider, labels: LabelStore) {
        self.model = model
        self.settings = settings
        self.wallpapers = wallpapers
        renderer = GridRenderer(model: model, labels: labels)
        hostingView = NSHostingView(rootView: LaunchpadRootView(model: model))
        // 視窗大小由我們決定，不讓 SwiftUI 內容反過來撐大視窗
        hostingView.sizingOptions = []
        searchBar = SearchBarView(model: model)

        container.wantsLayer = true
        backgroundView.autoresizingMask = [.width, .height]
        container.addSubview(backgroundView)
        contentView.wantsLayer = true
        container.addSubview(contentView)
        // 由下而上：主格線 → 資料夾玻璃 → 資料夾格線 → 拖曳浮動圖示 → SwiftUI（搜尋列、預覽、提示）
        for view in [renderer.mainView, renderer.folderGlass, renderer.folderView, renderer.dragView] as [NSView] {
            contentView.addSubview(view)
        }
        hostingView.wantsLayer = true
        contentView.addSubview(hostingView)
        contentView.addSubview(searchBar)
        panel.contentView = container
        renderer.start()
        // 搜尋列位置跟著版面（螢幕大小、邊距設定）走
        searchLoop = RenderLoop { [weak self] in self?.positionSearchBar() }

        panel.keyHandler = { [weak model] event in model?.handleKeyDown(event) ?? false }
        panel.scrollHandler = { [weak model] event in
            guard let model, model.drag == nil else { return true }
            // 頁寬每次都依目前版面設定：沒設的話維持預設 1，跟手位移會被夾在 ±1pt，看起來完全不跟手
            if let folder = model.openFolder {
                let pages = (folder.apps.count + model.folderCapacity - 1) / model.folderCapacity
                model.folderPager.pageWidth = model.folderPanelFrame(for: folder).width
                return model.folderPager.handleScroll(event, pageCount: pages)
            }
            model.pager.pageWidth = model.containerSize.width
            return model.pager.handleScroll(event, pageCount: model.displayPages.count)
        }

        panel.mouseHandler = { [weak self, weak model] event in
            guard let self, let model else { return false }
            // NSHostingView 是翻轉座標（左上為原點），與 SwiftUI 根座標一致
            let point = self.hostingView.convert(event.locationInWindow, from: nil)
            return model.handleMouse(event, at: point, in: self.hostingView)
        }

        observers.append(NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: panel, queue: .main
        ) { [weak self] _ in
            // 切到別的 App（⌘Tab、點 Dock 等）時自動收起
            MainActor.assumeIsolated { self?.hide(reason: .user) }
        })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                // 不同桌面可能設了不同桌布：下次打開重新確認
                self?.lastBackground.removeAll()
                self?.hide(reason: .user)
            }
        })
    }

    /// 預熱：在螢幕外先排版並繪製一次，第一次真正打開時不必等 SwiftUI 建立畫面。
    func prewarm(on screen: NSScreen) {
        layout(for: screen)
        hostingView.layoutSubtreeIfNeeded()
        hostingView.displayIfNeeded()
        // 以透明度 0 先上屏再收起：第一次 orderFront 要等 WindowServer 建立視窗與玻璃效果的資源（實測 10–15ms，
        // 幾乎都是等待而非 CPU），趁啟動時先付掉，使用者第一次打開就和之後一樣快
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        panel.displayIfNeeded()
        panel.orderOut(nil)
        panel.alphaValue = 1
    }

    // MARK: - 顯示

    /// 在指定螢幕顯示啟動台。
    /// - Parameter interactive: true 時由捏合手勢逐幀驅動進度（從 0 開始、不播放進場動畫、先不取得鍵盤焦點），
    ///   之後須呼叫 `updateInteractive` / `endInteractive`
    func show(on screen: NSScreen, interactive: Bool = false) {
        lastShowStartedAt = .now
        let signpost = Log.signposter.beginInterval("Show")
        defer { Log.signposter.endInterval("Show", signpost) }
        isVisible = true
        hideGeneration += 1

        // 覆蓋模式：高於選單列；否則低於 Dock（Dock 與選單列浮在啟動台上，和經典啟動台一樣）
        var mark = ContinuousClock.now
        var steps: [String] = []
        func step(_ name: String) {
            steps.append("\(name) \(String(format: "%.1f", milliseconds(since: mark)))")
            mark = .now
        }
        let level = settings.coversDock
            ? Int(CGWindowLevelForKey(.mainMenuWindow)) + 2
            : Int(CGWindowLevelForKey(.dockWindow)) - 1
        panel.level = NSWindow.Level(rawValue: level)
        layout(for: screen)
        step("layout")
        applyBackground(for: screen)
        step("background")
        model.preview.backingScale = screen.backingScaleFactor
        model.prepareForShow()
        step("prepare")

        container.layer?.removeAllAnimations()
        contentView.layer?.removeAllAnimations()
        if interactive {
            setFraction(0)
        } else {
            // 上一次跟手/收起動畫可能把 model 值留在中間狀態，進場動畫結束後會露出它，所以先歸位
            setFraction(1)
            animateIn()
        }
        // 先上屏（WindowServer 排序是這裡最貴的一步），取得鍵盤焦點延到下一輪：
        // 第一幀提早出現，而使用者不可能在一幀內就開始打字
        panel.orderFrontRegardless()
        step("order")
        if !interactive { acquireKeyboardFocus() }
        Log.perf.debug("show：\(steps.joined(separator: "、"), privacy: .public)")
    }

    /// 取得鍵盤焦點：延後約一幀才做。makeKey 與輸入框開始編輯合計要 5–40ms（等輸入法服務等系統成本），
    /// 若用 main.async 會排在這一輪 run loop 的圖層提交之前執行，把打開的第一幀往後推；
    /// 延 20ms 讓第一幀先上屏，而使用者不可能在 20ms 內就開始打字。
    private func acquireKeyboardFocus() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) { [weak self] in
            guard let self, self.isVisible else { return }
            let start = ContinuousClock.now
            self.panel.makeKey()
            Log.perf.debug("makeKey \(milliseconds(since: start), format: .fixed(precision: 2))ms")
            self.model.focusRequest += 1
        }
    }

    /// 收起啟動台。
    func hide(reason: DismissReason) {
        guard isVisible else { return }
        isVisible = false
        model.didHide()
        hideGeneration += 1
        let generation = hideGeneration
        let duration = reason == .launched || reason == .switchedWindow ? 0.16 : 0.2
        animateOut(duration: duration)
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
            guard let self, self.hideGeneration == generation, !self.isVisible else { return }
            self.panel.orderOut(nil)
            self.container.layer?.removeAllAnimations()
            self.contentView.layer?.removeAllAnimations()
            // 看不見之後才清掉搜尋、資料夾等暫態，並預先確認桌布是否換過
            self.model.resetTransientState()
            self.refreshBackgroundIfNeeded()
        }
        onHide?(reason)
    }

    // MARK: - 版面

    /// 依螢幕與覆蓋設定擺放視窗、背景與內容區。
    private func layout(for screen: NSScreen) {
        let frame = screen.frame
        if panel.frame != frame { panel.setFrame(frame, display: false) }
        container.frame = CGRect(origin: .zero, size: frame.size)
        backgroundView.frame = container.bounds
        // 不覆蓋 Dock/選單列時，內容避開它們（背景仍鋪滿整個螢幕）
        var content = container.bounds
        if !settings.coversDock {
            let visible = screen.visibleFrame
            content = CGRect(
                x: visible.minX - frame.minX, y: visible.minY - frame.minY,
                width: visible.width, height: visible.height
            )
        }
        if contentView.frame != content {
            contentView.frame = content
            let bounds = CGRect(origin: .zero, size: content.size)
            hostingView.frame = bounds
            renderer.mainView.frame = bounds
            renderer.dragView.frame = bounds
        }
        renderer.backingScale = screen.backingScaleFactor
    }

    /// 收起後在背景檢查目前螢幕的桌布是否換過（查詢桌布路徑要 2–5ms，不放在打開的路徑上）。
    private func refreshBackgroundIfNeeded() {
        guard let screen = panel.screen else { return }
        _ = wallpapers.background(for: screen, settings: settings) { [weak self] prepared in
            guard let self else { return }
            self.lastBackground[screen.displayID] = prepared
            if self.isVisible { self.apply(prepared) }
        }
    }

    /// 啟動或螢幕/桌布變動時預先準備各螢幕的背景並記下：第一次打開就直接套用，
    /// 不必在打開的路徑上查桌布路徑（2–5ms）。
    func prewarmBackgrounds() {
        for screen in NSScreen.screens {
            let id = screen.displayID
            let isMain = screen == NSScreen.main
            if let prepared = wallpapers.background(for: screen, settings: settings, onReady: { [weak self] prepared in
                guard let self else { return }
                self.lastBackground[id] = prepared
                // 主螢幕的背景先套上（看不見時套用沒有代價）：最常見的第一次打開就不必換圖
                if isMain, !self.isVisible { self.apply(prepared) }
            }) {
                lastBackground[id] = prepared
                if isMain, !isVisible { apply(prepared) }
            }
        }
    }

    /// 每個螢幕最近一次用過的背景：打開時直接套用，不必再查桌布路徑。
    private var lastBackground: [CGDirectDisplayID: PreparedBackground] = [:]

    private func apply(_ prepared: PreparedBackground) {
        backgroundView.show(image: prepared.image)
        model.backgroundIsLight = prepared.luminance > 0.62
    }

    private func applyBackground(for screen: NSScreen) {
        if settings.backgroundStyle != .liveBlur, let cached = lastBackground[screen.displayID] {
            apply(cached)
            return
        }
        if let prepared = wallpapers.background(for: screen, settings: settings, onReady: { [weak self] prepared in
            // 第一次算好時若啟動台還開著，立即換上
            guard let self else { return }
            self.lastBackground[screen.displayID] = prepared
            if self.isVisible { self.apply(prepared) }
        }) {
            lastBackground[screen.displayID] = prepared
            apply(prepared)
        } else {
            backgroundView.showLiveBlur()
            model.backgroundIsLight = false
        }
    }

    // MARK: - 動畫

    private func animateIn() {
        guard let containerLayer = container.layer, let contentLayer = contentView.layer else { return }
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0
        fade.toValue = 1
        fade.duration = 0.22
        fade.timingFunction = CAMediaTimingFunction(name: .easeOut)
        containerLayer.add(fade, forKey: "fade")

        let zoom = CABasicAnimation(keyPath: "transform")
        zoom.fromValue = NSValue(caTransform3D: scaleTransform(1.08, in: contentLayer.bounds))
        zoom.toValue = NSValue(caTransform3D: CATransform3DIdentity)
        zoom.duration = 0.3
        zoom.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.3, 1)
        contentLayer.add(zoom, forKey: "zoom")
    }

    private func animateOut(duration: Double) {
        guard let containerLayer = container.layer, let contentLayer = contentView.layer else { return }
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = containerLayer.presentation()?.opacity ?? 1
        fade.toValue = 0
        fade.duration = duration
        fade.timingFunction = CAMediaTimingFunction(name: .easeIn)
        fade.fillMode = .forwards
        fade.isRemovedOnCompletion = false
        containerLayer.add(fade, forKey: "fade")

        let zoom = CABasicAnimation(keyPath: "transform")
        zoom.fromValue = NSValue(caTransform3D: contentLayer.presentation()?.transform ?? CATransform3DIdentity)
        zoom.toValue = NSValue(caTransform3D: scaleTransform(1.05, in: contentLayer.bounds))
        zoom.duration = duration
        zoom.timingFunction = CAMediaTimingFunction(name: .easeIn)
        zoom.fillMode = .forwards
        zoom.isRemovedOnCompletion = false
        contentLayer.add(zoom, forKey: "zoom")
    }

    // MARK: - 跟手（捏合手勢）

    /// 目前進度：0 = 完全收起、1 = 完全展開。
    private(set) var fraction: CGFloat = 1
    /// 進度 0 時內容層比正常大多少（進度 1 → 縮放 1.0）
    private static let zoomExtra: CGFloat = 0.12

    /// 直接設定整個視窗（透明度 + 縮放）的進度，不經隱式動畫。
    private func setFraction(_ value: CGFloat) {
        let f = min(max(value, 0), 1)
        fraction = f
        guard let containerLayer = container.layer, let contentLayer = contentView.layer else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        containerLayer.opacity = Float(f)
        contentLayer.transform = scaleTransform(1 + Self.zoomExtra * (1 - f), in: contentLayer.bounds)
        CATransaction.commit()
    }

    /// 開始關閉方向的跟手（啟動台已顯示）：停掉進行中的動畫，從完全展開開始。
    func beginInteractiveClose() {
        guard isVisible else { return }
        hideGeneration += 1
        container.layer?.removeAllAnimations()
        contentView.layer?.removeAllAnimations()
        setFraction(1)
    }

    /// 手勢進行中：視窗跟著手指。
    func updateInteractive(_ value: CGFloat) {
        guard isVisible else { return }
        setFraction(value)
    }

    /// 放手：從目前位置順著動畫補完（commit）或回彈（取消）。
    /// - Parameters:
    ///   - opening: 這次手勢是否為開啟方向
    ///   - commit: 是否完成（開啟 → 展開並取得焦點；關閉 → 收起）
    func endInteractive(opening: Bool, commit: Bool) {
        guard isVisible else { return }
        let target: CGFloat = (opening == commit) ? 1 : 0
        hideGeneration += 1
        let generation = hideGeneration
        let from = fraction
        let duration = max(0.1, 0.3 * Double(abs(target - from)))
        guard let containerLayer = container.layer, let contentLayer = contentView.layer else { return }

        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = Float(from)
        fade.toValue = Float(target)
        let zoom = CABasicAnimation(keyPath: "transform")
        zoom.fromValue = NSValue(caTransform3D: contentLayer.presentation()?.transform ?? scaleTransform(1 + Self.zoomExtra * (1 - from), in: contentLayer.bounds))
        zoom.toValue = NSValue(caTransform3D: scaleTransform(1 + Self.zoomExtra * (1 - target), in: contentLayer.bounds))
        for animation in [fade, zoom] {
            animation.duration = duration
            animation.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.3, 1)
        }
        containerLayer.removeAllAnimations()
        contentLayer.removeAllAnimations()
        setFraction(target)
        containerLayer.add(fade, forKey: "fade")
        contentLayer.add(zoom, forKey: "zoom")

        if target == 1 {
            // 展開（開啟完成，或關閉被取消）：開啟完成時此刻才取得鍵盤焦點
            if opening { acquireKeyboardFocus() }
            return
        }
        // 收到 0：關閉完成走正常收起流程；開啟被取消則悄悄收回（沒人看過，不必通知協調者還焦點）
        isVisible = false
        model.didHide()
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
            guard let self, self.hideGeneration == generation, !self.isVisible else { return }
            self.panel.orderOut(nil)
            self.container.layer?.removeAllAnimations()
            self.contentView.layer?.removeAllAnimations()
            self.model.resetTransientState()
            self.refreshBackgroundIfNeeded()
        }
        if !opening { onHide?(.user) }
    }

    /// 以圖層中心為基準的縮放（AppKit 管理的圖層 anchorPoint 在左下角，直接縮放會往角落縮）。
    private func scaleTransform(_ scale: CGFloat, in bounds: CGRect) -> CATransform3D {
        let cx = bounds.midX, cy = bounds.midY
        var transform = CATransform3DMakeTranslation(cx, cy, 0)
        transform = CATransform3DScale(transform, scale, scale, 1)
        return CATransform3DTranslate(transform, -cx, -cy, 0)
    }

    /// 背景設定（樣式、模糊、自選圖片）改變或換螢幕配置時清掉快取，下次打開重新計算。
    func invalidateBackground() {
        lastBackground.removeAll()
    }

    /// 分段量測強制排版（自我測試用）：回傳 (圖層同步, SwiftUI 根畫面排版) 各自的 ms。
    func forceLayoutTimed() -> (grid: Double, root: Double) {
        var mark = ContinuousClock.now
        renderer.syncNow()
        let grid = milliseconds(since: mark); mark = .now
        hostingView.layoutSubtreeIfNeeded()
        return (grid, milliseconds(since: mark))
    }

    /// 依版面把搜尋列置中於上方。
    private func positionSearchBar() {
        let metrics = model.metrics
        let size = SearchBarView.size
        let frame = CGRect(x: (metrics.containerSize.width - size.width) / 2, y: metrics.searchBarY - size.height / 2,
                           width: size.width, height: size.height)
        if searchBar.frame != frame { searchBar.frame = frame }
    }

    /// 立即讓 SwiftUI 套用狀態變更並完成排版（自我測試量測「狀態改變 → 畫面更新」的主執行緒成本）。
    func forceLayout() {
        renderer.syncNow()
        hostingView.layoutSubtreeIfNeeded()
    }

    /// 根座標（左上原點）→ 視窗座標（左下原點），自我測試合成滑鼠事件用。
    func windowPoint(fromRoot point: CGPoint) -> CGPoint {
        hostingView.convert(point, to: nil)
    }

    /// 目前啟動台視窗的 CGWindowID（自我測試截圖用）。
    var windowNumber: CGWindowID { CGWindowID(panel.windowNumber) }
}
