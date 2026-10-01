//
//  GridRenderer.swift
//  Liftoff
//
//  把 LaunchpadModel 的狀態同步到 Core Animation 圖層。
//  以 Observation 追蹤：model 有任何相關屬性改變時，下一輪主執行緒重新「同步」一次（同一輪多次變更自動合併）。
//  同步是差異式的：只改真的變了的圖層屬性，不重建圖層。
//
//  三條獨立的追蹤迴圈，避免高頻變化拖累整體：
//  - 主迴圈：格子集合、位置、狀態、圖示、名稱、資料夾
//  - 翻頁迴圈：只處理頁面容器的位移（觸控板跟手時每個事件都會變）
//  - 拖曳迴圈：只移動浮動圖示（游標每動一下都會變）
//
//  視圖層級（由下而上）：主格線 → 資料夾玻璃 → 資料夾格線 → 拖曳浮動圖示，之上才是 SwiftUI（搜尋列等）。
//

import AppKit
import Observation
import QuartzCore

/// 承載圖層的 view（layer-hosting，原點在左上，與 SwiftUI 座標一致）。
final class LayerHostView: NSView {
    let root = StaticLayer()

    override init(frame: NSRect) {
        super.init(frame: frame)
        root.isGeometryFlipped = true
        layer = root
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    // 事件一律由面板層處理，這些 view 不攔截滑鼠
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// 以 withObservationTracking 反覆追蹤並重繪的迴圈。
final class RenderLoop {
    private let body: () -> Void

    init(_ body: @escaping () -> Void) {
        self.body = body
        run()
    }

    private func run() {
        withObservationTracking {
            body()
        } onChange: { [weak self] in
            // 「將要改變」時通知；排到下一輪主執行緒再同步（屆時值已更新，且同一輪的變更只同步一次）
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.run() }
            }
        }
    }
}

final class GridRenderer {
    let mainView = LayerHostView(frame: .zero)
    let folderGlass = NSGlassEffectView(frame: .zero)
    let folderView = LayerHostView(frame: .zero)
    let dragView = LayerHostView(frame: .zero)

    private let model: LaunchpadModel
    private let labels: LabelStore
    /// 目前螢幕倍率（名稱渲染用）
    var backingScale: CGFloat = 2

    private let pagesLayer = StaticLayer()
    private let folderPagesLayer = StaticLayer()
    private let dragLayer = IconTileLayer()
    private var cells: [String: CellLayer] = [:]
    private var folderCells: [String: CellLayer] = [:]
    private var loops: [RenderLoop] = []

    private var lastMetrics: GridMetrics?
    private var lastFolderMetrics: GridMetrics?
    private var wasSearching = false
    private var shownFolderID: UUID?
    private var lastPageX: CGFloat?
    private var lastFolderPageX: CGFloat?
    private var draggedItemID: String?
    /// 拖曳中最後一次的合併目標（放開那一刻 model 的 drag 已清空，靠這個知道剛剛是合併）
    private var lastMergeTargetID: String?
    /// 浮動圖示收尾動畫的世代號：動畫中又開始新的拖曳時，舊動畫的完成回呼不能把它藏起來
    private var dragLayerGeneration = 0

    init(model: LaunchpadModel, labels: LabelStore) {
        self.model = model
        self.labels = labels
        pagesLayer.anchorPoint = .zero
        mainView.root.addSublayer(pagesLayer)

        folderGlass.cornerRadius = 30
        // 白色淡染：比照 Big Sur 之後的資料夾面板，透出後方模糊而不是一塊深灰（原本黑色 0.28 太暗）
        folderGlass.tintColor = NSColor.white.withAlphaComponent(0.1)
        folderGlass.appearance = NSAppearance(named: .darkAqua)
        folderGlass.isHidden = true
        folderView.isHidden = true
        folderView.root.masksToBounds = true
        folderView.root.cornerRadius = 30
        folderView.root.cornerCurve = .continuous
        folderPagesLayer.anchorPoint = .zero
        folderView.root.addSublayer(folderPagesLayer)

        dragLayer.isHidden = true
        dragLayer.shadowColor = CGColor(gray: 0, alpha: 1)
        dragLayer.shadowOpacity = 0.35
        dragLayer.shadowRadius = 12
        dragLayer.shadowOffset = CGSize(width: 0, height: 6)
        dragView.root.addSublayer(dragLayer)
    }

    /// 開始追蹤 model（視窗建好後呼叫一次）。
    func start() {
        loops = [
            RenderLoop { [weak self] in self?.syncMain() },
            RenderLoop { [weak self] in self?.syncPager() },
            RenderLoop { [weak self] in self?.syncDrag() },
        ]
    }

    /// 格子圖層數（自我測試/除錯用）。
    var cellCount: Int { cells.count }

    /// 立即同步一次（自我測試量測「狀態改變 → 圖層更新」的主執行緒成本；正常流程由追蹤迴圈自動觸發）。
    func syncNow() {
        syncMain()
        syncPager()
        syncDrag()
    }

    // MARK: - 主迴圈

    private func syncMain() {
        let metrics = model.metrics
        let items = model.cellItems
        let placements = model.placements
        let running = model.running.ids
        let selection = model.selection
        let drag = model.drag
        let draggedID = drag?.itemID
        let mergeTarget = drag?.mergeTargetID
        let pressed = model.pressedID
        let labelsDark = model.labelsAreDark
        let searching = model.isSearching
        let width = metrics.containerSize.width
        let style = LabelStyle(fontSize: metrics.labelFontSize, maxWidth: metrics.cellSize.width - 12, scale: backingScale)
        _ = labels.revision

        let metricsChanged = metrics != lastMetrics
        // 只有「一般瀏覽中的版面變動」（拖曳換位、隱藏、合併資料夾）才做位移動畫；搜尋結果切換要即時
        let animate = model.isShown && !metricsChanged && !searching && !wasSearching
        lastMetrics = metrics
        wasSearching = searching

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        var alive = Set<String>()
        for item in items {
            alive.insert(item.id)
            let cell: CellLayer
            if let existing = cells[item.id] {
                cell = existing
                if metricsChanged { cell.layout(metrics: metrics) }
            } else {
                cell = CellLayer()
                cell.layout(metrics: metrics)
                cell.isHidden = true
                pagesLayer.addSublayer(cell)
                cells[item.id] = cell
            }
            configureIcon(cell.icon, for: item)
            if metrics.showsLabels {
                cell.setLabel(labels.image(for: model.title(for: item), dark: labelsDark, style: style), scale: backingScale)
            } else {
                cell.setLabel(nil, scale: backingScale)
            }

            if let placement = placements[item.id] {
                let frame = metrics.cellFrame(placement.index)
                let target = CGPoint(x: CGFloat(placement.page) * width + frame.midX, y: frame.midY)
                if cell.isHidden || !animate {
                    cell.removeAnimation(forKey: "position")
                    cell.position = target
                    cell.isHidden = false
                } else if cell.position != target {
                    GridAnimation.animate(cell, keyPath: "position", to: NSValue(point: target), duration: 0.32, spring: true) {
                        cell.position = target
                    }
                }
            } else if !cell.isHidden {
                cell.isHidden = true
            }

            let state = CellState(
                isSelected: selection != nil && placements[item.id] == selection && model.openFolderID == nil,
                isPressed: pressed == item.id,
                isDragged: draggedID == item.id,
                isMergeTarget: mergeTarget == item.id,
                isRunning: item.appID.map(running.contains) ?? false
            )
            if state != cell.state || metricsChanged {
                cell.apply(state, labelsDark: labelsDark, animated: model.isShown)
            }
        }
        for (id, cell) in cells where !alive.contains(id) {
            cell.removeFromSuperlayer()
            cells.removeValue(forKey: id)
        }
        CATransaction.commit()

        syncFolder(metrics: metrics, running: running, draggedID: draggedID, style: style)
        prepareDragLayer(drag, metrics: metrics, items: items)
        if drag != nil { lastMergeTargetID = mergeTarget }
    }

    /// 設定圖示內容：App 取自己的圖示，資料夾取前 9 個 App 的圖示。
    private func configureIcon(_ layer: IconTileLayer, for item: LayoutItem) {
        switch item {
        case .app(let id):
            layer.showApp(model.icons.icon(for: id).cgImage ?? model.icons.placeholder)
        case .folder(let folder):
            layer.showFolder(folder.apps.prefix(9).map { model.icons.icon(for: $0).cgImage ?? model.icons.placeholder })
        }
    }

    // MARK: - 資料夾

    private func syncFolder(metrics main: GridMetrics, running: Set<String>, draggedID: String?, style: LabelStyle) {
        let folder = model.openFolder
        let closingID = shownFolderID
        let wasOpen = shownFolderID != nil
        shownFolderID = folder?.id

        // 開資料夾時主格線淡出、略為縮小
        setDimmed(folder != nil, animated: wasOpen != (folder != nil) && model.isShown)

        guard let folder else {
            if wasOpen { popOut([folderGlass, folderView], toward: closingID.flatMap(folderIconCenter)) }
            return
        }
        let panel = model.folderPanelFrame(for: folder)
        let metrics = model.folderGridMetrics
        let metricsChanged = metrics != lastFolderMetrics
        lastFolderMetrics = metrics

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        // view 的 frame 由 AppKit 同步到它的圖層；不要直接改 root 圖層的 frame，否則會脫離 view 的位置
        folderGlass.frame = panel
        folderView.frame = panel

        let capacity = model.folderCapacity
        var alive = Set<String>()
        for (offset, appID) in folder.apps.enumerated() {
            alive.insert(appID)
            let cell: CellLayer
            if let existing = folderCells[appID] {
                cell = existing
                if metricsChanged { cell.layout(metrics: metrics) }
            } else {
                cell = CellLayer()
                cell.layout(metrics: metrics)
                folderPagesLayer.addSublayer(cell)
                folderCells[appID] = cell
            }
            configureIcon(cell.icon, for: .app(appID))
            cell.setLabel(metrics.showsLabels ? labels.image(for: model.title(for: .app(appID)), dark: false, style: style) : nil,
                          scale: backingScale)
            let frame = metrics.cellFrame(offset % capacity)
            let target = CGPoint(x: CGFloat(offset / capacity) * panel.width + frame.midX, y: frame.midY)
            if wasOpen, model.isShown, cell.position != target, !cell.isHidden {
                GridAnimation.animate(cell, keyPath: "position", to: NSValue(point: target), duration: 0.3, spring: true) {
                    cell.position = target
                }
            } else {
                cell.position = target
            }
            cell.isHidden = false
            let state = CellState(
                isSelected: model.folderSelection == offset,
                isPressed: model.pressedID == appID,
                isDragged: draggedID == appID,
                isRunning: running.contains(appID)
            )
            if state != cell.state || metricsChanged { cell.apply(state, labelsDark: false, animated: model.isShown) }
        }
        for (id, cell) in folderCells where !alive.contains(id) {
            cell.removeFromSuperlayer()
            folderCells.removeValue(forKey: id)
        }
        CATransaction.commit()

        if !wasOpen { popIn([folderGlass, folderView], from: folderIconCenter(folder.id)) }
    }

    private var isDimmed = false

    private func setDimmed(_ dimmed: Bool, animated: Bool) {
        guard dimmed != isDimmed else { return }
        isDimmed = dimmed
        let root = mainView.root
        let opacity: Float = dimmed ? 0.22 : 1
        let transform = dimmed ? Self.scale(0.97, in: root.bounds) : CATransform3DIdentity
        if animated {
            GridAnimation.animate(root, keyPath: "opacity", to: opacity, duration: 0.28) { root.opacity = opacity }
            GridAnimation.animate(root, keyPath: "transform", to: NSValue(caTransform3D: transform), duration: 0.3) {
                root.transform = transform
            }
        } else {
            root.opacity = opacity
            root.transform = transform
        }
    }

    /// 資料夾圖示在主格線上的中心（根座標）；不在目前頁面（例如搜尋中）時為 nil。
    private func folderIconCenter(_ id: UUID) -> CGPoint? {
        guard let cell = cells[LayoutItem.folderKey(id)], !cell.isHidden else { return nil }
        let center = cell.iconCenterInSuperlayer
        let point = CGPoint(x: center.x + pagesLayer.position.x, y: center.y + pagesLayer.position.y)
        return mainView.bounds.contains(point) ? point : nil
    }

    /// 面板縮在資料夾圖示上的變換：以圖示中心為支點縮小（面板本地座標，左上原點）。
    /// 支點在面板外時，縮小後整個面板就落在圖示附近，看起來像從圖示裡長出來（經典啟動台的開資料夾動畫）。
    private func collapsedTransform(for layer: CALayer, frame: CGRect, toward point: CGPoint?) -> CATransform3D {
        guard let point else { return Self.scale(0.86, in: layer.bounds) }
        let iconSide = model.metrics.iconSize
        let scale = max(0.12, min(0.6, iconSide / (frame.width * frame.height).squareRoot()))
        let pivot = CGPoint(x: point.x - frame.minX, y: point.y - frame.minY)
        var transform = CATransform3DMakeTranslation(pivot.x, pivot.y, 0)
        transform = CATransform3DScale(transform, scale, scale, 1)
        return CATransform3DTranslate(transform, -pivot.x, -pivot.y, 0)
    }

    /// 資料夾面板彈出：從資料夾圖示放大並淡入。
    private func popIn(_ views: [NSView], from point: CGPoint?) {
        for view in views {
            view.isHidden = false
            guard let layer = view.layer else { continue }
            layer.removeAllAnimations()
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 0
            fade.toValue = 1
            fade.duration = 0.2
            let zoom = CASpringAnimation(perceptualDuration: 0.38, bounce: 0.06)
            zoom.keyPath = "transform"
            zoom.fromValue = NSValue(caTransform3D: collapsedTransform(for: layer, frame: view.frame, toward: point))
            zoom.toValue = NSValue(caTransform3D: CATransform3DIdentity)
            layer.add(fade, forKey: "popFade")
            layer.add(zoom, forKey: "popZoom")
        }
    }

    /// 資料夾面板收起：縮回資料夾圖示並淡出。
    private func popOut(_ views: [NSView], toward point: CGPoint?) {
        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.shownFolderID == nil else { return }
                views.forEach { $0.isHidden = true; $0.layer?.removeAllAnimations() }
            }
        }
        for view in views {
            guard let layer = view.layer else { continue }
            let duration = 0.26
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = layer.presentation()?.opacity ?? 1
            fade.toValue = 0
            fade.duration = duration
            fade.timingFunction = CAMediaTimingFunction(name: .easeIn)
            fade.fillMode = .forwards
            fade.isRemovedOnCompletion = false
            let zoom = CABasicAnimation(keyPath: "transform")
            zoom.fromValue = NSValue(caTransform3D: layer.presentation()?.transform ?? CATransform3DIdentity)
            zoom.toValue = NSValue(caTransform3D: collapsedTransform(for: layer, frame: view.frame, toward: point))
            zoom.duration = duration
            zoom.timingFunction = CAMediaTimingFunction(controlPoints: 0.4, 0, 0.6, 1)
            zoom.fillMode = .forwards
            zoom.isRemovedOnCompletion = false
            layer.add(fade, forKey: "popFade")
            layer.add(zoom, forKey: "popZoom")
        }
        CATransaction.commit()
    }

    /// 以中心為基準的縮放（圖層 anchorPoint 不一定在中心）。
    static func scale(_ scale: CGFloat, in bounds: CGRect) -> CATransform3D {
        var transform = CATransform3DMakeTranslation(bounds.midX, bounds.midY, 0)
        transform = CATransform3DScale(transform, scale, scale, 1)
        return CATransform3DTranslate(transform, -bounds.midX, -bounds.midY, 0)
    }

    // MARK: - 翻頁迴圈

    private func syncPager() {
        let width = model.containerSize.width
        let pager = model.pager
        let x = -CGFloat(pager.page) * width + pager.offset
        move(pagesLayer, toX: x, last: &lastPageX, interactive: pager.offset != 0)

        if let folder = model.openFolder {
            let panelWidth = model.folderPanelFrame(for: folder).width
            let folderPager = model.folderPager
            let fx = -CGFloat(folderPager.page) * panelWidth + folderPager.offset
            move(folderPagesLayer, toX: fx, last: &lastFolderPageX, interactive: folderPager.offset != 0)
        } else {
            lastFolderPageX = nil
            folderPagesLayer.removeAllAnimations()
            folderPagesLayer.position = .zero
        }
    }

    /// 跟手時直接設定位置；翻頁（頁碼改變、放開手指）時從畫面上目前位置以彈簧動畫移到目標。
    private func move(_ layer: CALayer, toX x: CGFloat, last: inout CGFloat?, interactive: Bool) {
        defer { last = x }
        guard last != x else { return }
        let target = CGPoint(x: x, y: 0)
        if interactive || last == nil || !model.isShown {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layer.removeAnimation(forKey: "position")
            layer.position = target
            CATransaction.commit()
        } else {
            GridAnimation.animate(layer, keyPath: "position", to: NSValue(point: target), duration: 0.42, spring: true) {
                layer.position = target
            }
        }
    }

    // MARK: - 拖曳迴圈

    /// 拖曳開始/結束時設定浮動圖示的內容與大小（由主迴圈呼叫）。
    /// 放開在合併目標上時，浮動圖示縮小飛進資料夾、新資料夾從底板大小彈回（經典啟動台的合併動畫）。
    private func prepareDragLayer(_ drag: DragSession?, metrics: GridMetrics, items: [LayoutItem]) {
        guard drag?.itemID != draggedItemID else { return }
        let endedID = draggedItemID
        draggedItemID = drag?.itemID
        dragLayerGeneration += 1
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if let drag {
            dragLayer.removeAllAnimations()
            dragLayer.transform = CATransform3DIdentity
            let size = metrics.iconSize * 1.12
            dragLayer.bounds = CGRect(x: 0, y: 0, width: size, height: size)
            configureIcon(dragLayer, for: drag.item)
            dragLayer.position = drag.iconCenter
            dragLayer.opacity = 1
            dragLayer.isHidden = false
        } else if let endedID, let targetID = lastMergeTargetID, model.isShown,
                  let folder = items.first(where: { if case .folder(let f) = $0 { f.apps.contains(endedID) } else { false } }),
                  let cell = cells[folder.id] {
            flyIntoFolder(cell: cell, isNewFolder: folder.id != targetID)
        } else {
            dragLayer.isHidden = true
        }
        if drag == nil { lastMergeTargetID = nil }
        CATransaction.commit()
    }

    /// 浮動圖示縮小、淡出並飛進資料夾中心；新建的資料夾同時從底板大小彈回。
    private func flyIntoFolder(cell: CellLayer, isNewFolder: Bool) {
        let center = cell.iconCenterInSuperlayer
        let target = CGPoint(x: center.x + pagesLayer.position.x, y: center.y + pagesLayer.position.y)
        let shrink = CATransform3DMakeScale(0.3, 0.3, 1)
        let generation = dragLayerGeneration
        let duration = 0.34
        GridAnimation.animate(dragLayer, keyPath: "position", to: NSValue(point: target), duration: duration) {
            dragLayer.position = target
        }
        GridAnimation.animate(dragLayer, keyPath: "transform", to: NSValue(caTransform3D: shrink), duration: duration) {
            dragLayer.transform = shrink
        }
        // 淡出用 ease-in：前段看得到圖示飛過去，快到資料夾時才消失
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = dragLayer.presentation()?.opacity ?? dragLayer.opacity
        fade.toValue = 0
        fade.duration = duration
        fade.timingFunction = CAMediaTimingFunction(name: .easeIn)
        dragLayer.opacity = 0
        dragLayer.add(fade, forKey: "opacity")
        if isNewFolder { cell.settleFromMerge() }
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
            guard let self, self.dragLayerGeneration == generation else { return }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            self.dragLayer.isHidden = true
            self.dragLayer.removeAllAnimations()
            CATransaction.commit()
        }
    }

    private func syncDrag() {
        guard let drag = model.drag else { return }
        let center = drag.iconCenter
        let merging = drag.mergeTargetID != nil
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        dragLayer.position = center
        dragLayer.opacity = merging ? 0.85 : 1
        CATransaction.commit()
    }
}
