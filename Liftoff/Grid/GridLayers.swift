//
//  GridLayers.swift
//  Liftoff
//
//  格線用的 Core Animation 圖層：一格 = 一個 CellLayer（圖示 + 名稱 + 執行中圓點 + 選取底色）。
//  為什麼用圖層而不是 SwiftUI view：實測 160 格的 SwiftUI 格線，每次搜尋/選取更新要 15–65ms 主執行緒時間；
//  改成圖層後只是設定幾個屬性（位置、貼圖、隱藏），同樣的更新 < 1ms，動畫也全交給 render server。
//  經典啟動台本身也是用 Core Animation 圖層實作。
//
//  所有圖層預設關閉隱式動畫（defaultAction 回傳 NSNull），需要動畫時一律明確加 CAAnimation。
//

import AppKit
import QuartzCore

/// 關閉所有隱式動畫的圖層基底。
nonisolated class StaticLayer: CALayer {
    override init() { super.init() }
    override init(layer: Any) { super.init(layer: layer) }
    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override class func defaultAction(forKey event: String) -> (any CAAction)? { NSNull() }
}

/// 圖示本體：App 圖示貼圖，或資料夾的半透明方塊 + 3×3 迷你圖示。
nonisolated final class IconTileLayer: StaticLayer {
    private let tile = StaticLayer()
    private var minis: [StaticLayer] = []
    /// 目前顯示的是資料夾（合併目標的動畫依此分流）
    private(set) var isFolder = false

    override init() {
        super.init()
        contentsGravity = .resizeAspect
        tile.isHidden = true
        tile.backgroundColor = CGColor(gray: 1, alpha: 0.26)
        tile.borderColor = CGColor(gray: 1, alpha: 0.35)
        tile.borderWidth = 0.75
        tile.cornerCurve = .continuous
        addSublayer(tile)
    }

    override init(layer: Any) { super.init(layer: layer) }

    /// 顯示 App 圖示。
    func showApp(_ image: CGImage?) {
        if isFolder {
            isFolder = false
            tile.isHidden = true
            minis.forEach { $0.isHidden = true }
        }
        if contents as! CGImage? !== image { contents = image }
    }

    /// 顯示資料夾（方塊比照 App 圖示的實體大小：約占畫布 82%）。
    /// - Parameter images: 前 9 個 App 的圖示
    func showFolder(_ images: [CGImage?]) {
        isFolder = true
        contents = nil
        tile.isHidden = false
        let size = bounds.width
        let side = size * 0.82
        let inset = side * 0.11
        let gap = side * 0.06
        let mini = (side - inset * 2 - gap * 2) / 3
        tile.frame = CGRect(x: (size - side) / 2, y: (size - side) / 2, width: side, height: side)
        tile.cornerRadius = side * 0.225
        while minis.count < 9 {
            let layer = StaticLayer()
            layer.contentsGravity = .resizeAspect
            tile.addSublayer(layer)
            minis.append(layer)
        }
        for (index, layer) in minis.enumerated() {
            guard index < images.count else {
                layer.isHidden = true
                continue
            }
            layer.isHidden = false
            // 放大 1.2 倍抵銷圖示本身的透明留白
            let center = CGPoint(x: inset + CGFloat(index % 3) * (mini + gap) + mini / 2,
                                 y: inset + CGFloat(index / 3) * (mini + gap) + mini / 2)
            let side = mini * 1.2
            layer.frame = CGRect(x: center.x - side / 2, y: center.y - side / 2, width: side, height: side)
            if layer.contents as! CGImage? !== images[index] { layer.contents = images[index] }
        }
    }
}

/// 一格。
nonisolated final class CellLayer: StaticLayer {
    let icon = IconTileLayer()
    /// 拖曳的 App 停在這格 App 上時，從圖示背後長出的資料夾底板（經典啟動台「即將合併成資料夾」的提示）
    private let plate = StaticLayer()
    private let label = StaticLayer()
    private let dot = StaticLayer()
    private let highlight = StaticLayer()
    private(set) var state = CellState()
    private var iconRect = CGRect.zero

    override init() {
        super.init()
        highlight.isHidden = true
        highlight.cornerRadius = 18
        highlight.cornerCurve = .continuous
        dot.isHidden = true
        dot.cornerRadius = 2.5
        label.contentsGravity = .center
        // 外觀與資料夾方塊一致，合併完成時新資料夾才能無縫接上
        plate.backgroundColor = CGColor(gray: 1, alpha: 0.26)
        plate.borderColor = CGColor(gray: 1, alpha: 0.35)
        plate.borderWidth = 0.75
        plate.cornerCurve = .continuous
        plate.opacity = 0
        addSublayer(highlight)
        addSublayer(plate)
        addSublayer(icon)
        addSublayer(dot)
        addSublayer(label)
    }

    override init(layer: Any) { super.init(layer: layer) }

    /// 依格線尺寸擺放內部元件（格子大小、圖示大小改變時呼叫）。
    func layout(metrics: GridMetrics) {
        bounds = CGRect(origin: .zero, size: metrics.cellSize)
        let cell = metrics.cellFrame(0)
        iconRect = metrics.iconFrame(0).offsetBy(dx: -cell.minX, dy: -cell.minY)
        icon.bounds = CGRect(origin: .zero, size: iconRect.size)
        icon.position = CGPoint(x: iconRect.midX, y: iconRect.midY)
        let side = iconRect.width * 0.82
        plate.bounds = CGRect(x: 0, y: 0, width: side, height: side)
        plate.position = icon.position
        plate.cornerRadius = side * 0.225
        dot.frame = CGRect(x: iconRect.midX - 2.5, y: iconRect.maxY + 4.5, width: 5, height: 5)
        let block = iconRect.height + (metrics.showsLabels ? metrics.labelSpacing + metrics.labelHeight : 0) + 16
        let width = min(metrics.cellSize.width - 8, iconRect.width * 2.1)
        highlight.frame = CGRect(x: iconRect.midX - width / 2, y: iconRect.minY - 8, width: width, height: block)
        labelSpacing = metrics.labelSpacing
        // metrics 變動（瀏海 inset、欄列數、圖示大小）後名稱圖不會重新設定（setLabel 對同一張圖直接略過），
        // 所以框要在這裡依新的 iconRect 重算，否則標籤會停在舊位置而與圖示錯位
        layoutLabel()
    }

    private var labelSpacing: CGFloat = 7
    /// 目前名稱圖的點尺寸，layout 時用來重算位置
    private var labelSize = CGSize.zero

    /// 名稱圖置於圖示下方；四周各留 2pt 陰影空間。
    private func layoutLabel() {
        guard labelSize != .zero else { return }
        label.frame = CGRect(x: (iconRect.midX - labelSize.width / 2).rounded(), y: (iconRect.maxY + labelSpacing - 2).rounded(),
                             width: labelSize.width, height: labelSize.height)
    }

    /// 設定名稱圖（像素 → 點以 scale 換算），置中於圖示下方。
    func setLabel(_ image: CGImage?, scale: CGFloat) {
        guard label.contents as! CGImage? !== image || label.contentsScale != scale else { return }
        label.contents = image
        label.contentsScale = scale
        guard let image else { labelSize = .zero; return }
        labelSize = CGSize(width: CGFloat(image.width) / scale, height: CGFloat(image.height) / scale)
        layoutLabel()
    }

    /// 套用外觀狀態（按下/合併目標的縮放有動畫）。
    func apply(_ newState: CellState, labelsDark: Bool, animated: Bool) {
        let old = state
        state = newState
        if old.isDragged != newState.isDragged { opacity = newState.isDragged ? 0 : 1 }
        if old.isSelected != newState.isSelected { highlight.isHidden = !newState.isSelected }
        highlight.backgroundColor = labelsDark ? CGColor(gray: 0, alpha: 0.12) : CGColor(gray: 1, alpha: 0.2)
        dot.isHidden = !newState.isRunning
        dot.backgroundColor = labelsDark ? CGColor(gray: 0, alpha: 0.65) : CGColor(gray: 1, alpha: 0.9)

        let scale = iconScale(for: newState)
        let oldScale = iconScale(for: old)
        if scale != oldScale {
            let target = CATransform3DMakeScale(scale, scale, 1)
            if animated {
                GridAnimation.animate(icon, keyPath: "transform", to: NSValue(caTransform3D: target),
                                      duration: newState.isPressed ? 0.1 : 0.24, spring: !newState.isPressed) { icon.transform = target }
            } else {
                icon.transform = target
            }
        }
        // 停在 App 上：底板從圖示背後放大浮現、圖示略縮進底板裡；離開時反向收回
        let showsPlate = newState.isMergeTarget && !icon.isFolder
        if showsPlate != (plate.opacity > 0) {
            let opacity: Float = showsPlate ? 1 : 0
            let transform = CATransform3DMakeScale(showsPlate ? Self.mergeScale : 0.7, showsPlate ? Self.mergeScale : 0.7, 1)
            if animated {
                if showsPlate, plate.presentation()?.opacity ?? 0 == 0 { plate.transform = CATransform3DMakeScale(0.7, 0.7, 1) }
                GridAnimation.animate(plate, keyPath: "opacity", to: opacity, duration: 0.18) { plate.opacity = opacity }
                GridAnimation.animate(plate, keyPath: "transform", to: NSValue(caTransform3D: transform), duration: 0.3, spring: true) {
                    plate.transform = transform
                }
            } else {
                plate.opacity = opacity
                plate.transform = transform
            }
        }
        let iconOpacity: Float = newState.isPressed ? 0.72 : 1
        if icon.opacity != iconOpacity { icon.opacity = iconOpacity }
    }
}

nonisolated extension CellLayer {
    /// 合併目標放大的倍率（資料夾方塊、App 背後的底板都用它；合併完成時新資料夾從這個大小縮回 1）
    static let mergeScale: CGFloat = 1.18

    /// 依狀態決定圖示縮放：按下縮小；合併目標若是資料夾就整個放大，若是 App 則略縮進底板。
    fileprivate func iconScale(for state: CellState) -> CGFloat {
        if state.isPressed { return 0.9 }
        guard state.isMergeTarget else { return 1 }
        return icon.isFolder ? Self.mergeScale : 0.8
    }

    /// 圖示中心在父圖層（頁面容器）座標中的位置（以 model 值計算，不受進行中的動畫影響）。
    var iconCenterInSuperlayer: CGPoint {
        CGPoint(x: position.x - bounds.midX + icon.position.x, y: position.y - bounds.midY + icon.position.y)
    }

    /// 剛合併出的新資料夾：從合併目標放大的大小彈回原尺寸，接續前一刻的底板。
    func settleFromMerge() {
        let start = CATransform3DMakeScale(Self.mergeScale, Self.mergeScale, 1)
        icon.transform = start
        GridAnimation.animate(icon, keyPath: "transform", to: NSValue(caTransform3D: CATransform3DIdentity), duration: 0.36, spring: true) {
            icon.transform = CATransform3DIdentity
        }
    }
}

/// 明確動畫的小工具：從目前畫面上的值（presentation）動到新值，中途被打斷也不會跳。
nonisolated enum GridAnimation {
    /// 以 spring 或 ease-out 動畫把屬性改成新值。
    /// - Parameters:
    ///   - layer: 目標圖層
    ///   - keyPath: 屬性路徑
    ///   - value: 新值（動畫結束後的 model 值）
    ///   - duration: 時長
    ///   - spring: 是否用彈簧曲線
    ///   - apply: 實際寫入 model 值
    static func animate(_ layer: CALayer, keyPath: String, to value: Any, duration: CFTimeInterval,
                        spring: Bool = false, apply: () -> Void) {
        let from = layer.presentation()?.value(forKeyPath: keyPath) ?? layer.value(forKeyPath: keyPath)
        apply()
        let animation: CABasicAnimation
        if spring {
            let springAnimation = CASpringAnimation(perceptualDuration: duration, bounce: 0.04)
            springAnimation.keyPath = keyPath
            animation = springAnimation
        } else {
            animation = CABasicAnimation(keyPath: keyPath)
            animation.duration = duration
            animation.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.3, 1)
        }
        animation.fromValue = from
        animation.toValue = value
        layer.add(animation, forKey: keyPath)
    }
}
