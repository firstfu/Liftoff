//
//  GridMetrics.swift
//  Liftoff
//
//  格線幾何：由容器大小與設定算出每一格的位置與圖示大小。
//  全部以數學計算（不靠 GeometryReader 量測每一格），拖曳時「游標在哪一格」只要一次除法，
//  SwiftUI 也不必為了量尺寸多跑一輪 layout。
//

import AppKit

/// 視窗模式（issue #17）的卡片尺寸與版面常數：照 macOS 內建「App」視窗——
/// 上方一列大字搜尋、細分隔線、緊密的格線、圖示約 64pt，卡片大小由格線推算而不是佔螢幕的固定比例。
nonisolated enum WindowModeCard {
    static let horizontalMargin: CGFloat = 22
    /// 搜尋列那一列的高度（分隔線畫在這條線上）
    static let headerHeight: CGFloat = 60
    /// 格線起點（分隔線下方留一點空）
    static let gridTop: CGFloat = 72
    /// 頁碼點那一列
    static let bottomMargin: CGFloat = 34
    static let cornerRadius: CGFloat = 26
    /// 玻璃淡染：不加的話玻璃很透，後方視窗的文字清楚透出、畫面雜亂；
    /// 內建「App」視窗是霧白（淺色）／霧黑（深色），後方只剩模糊色塊
    static func glassTint(light: Bool) -> NSColor {
        light ? NSColor.white.withAlphaComponent(0.55) : NSColor.black.withAlphaComponent(0.35)
    }
    /// 標準格子：圖示 64pt 時的格寬與「圖示區」高度
    private static let cellWidth: CGFloat = 110
    private static let iconAreaHeight: CGFloat = 80

    /// 卡片大小；超出可用區域時等比例縮小。
    /// - Parameter available: 螢幕扣掉選單列與 Dock 的區域
    static func size(columns: Int, rows: Int, iconScale: Double, labelFontSize: Double, showsLabels: Bool, available: CGSize) -> CGSize {
        let scale = CGFloat(iconScale)
        let labelHeight = showsLabels ? labelFontSize * 1.35 + 7 : 0
        let width = CGFloat(max(1, columns)) * cellWidth * scale + horizontalMargin * 2
        let height = gridTop + CGFloat(max(1, rows)) * (iconAreaHeight * scale + labelHeight) + bottomMargin
        let fit = min(1, available.width * 0.92 / width, available.height * 0.9 / height)
        return CGSize(width: (width * fit).rounded(), height: (height * fit).rounded())
    }
}

nonisolated struct GridMetrics: Equatable, Sendable {
    let containerSize: CGSize
    let columns: Int
    let rows: Int
    /// 格線區域（頁面座標，原點在左上）
    let gridRect: CGRect
    let cellSize: CGSize
    let iconSize: CGFloat
    let labelFontSize: CGFloat
    let showsLabels: Bool
    /// 圖示與名稱的間距
    let labelSpacing: CGFloat
    /// 搜尋列中心的 y
    let searchBarY: CGFloat
    /// 頁碼點中心的 y
    let pageDotsY: CGFloat

    /// - Parameters:
    ///   - containerSize: 啟動台可用區域（整個螢幕，或扣掉未被覆蓋的選單列/Dock）
    ///   - columns: 欄數
    ///   - rows: 列數
    ///   - iconScale: 圖示大小倍率
    ///   - labelFontSize: 名稱字級
    ///   - showsLabels: 是否顯示名稱
    ///   - compact: 緊湊模式（四周留白較少）
    ///   - topInset: 上方被硬體遮住的高度（瀏海機型的 safeAreaInsets.top；內容區已避開選單列時為 0）
    ///   - windowed: 視窗模式（見 `WindowCard`）：固定的窄邊距，圖示大小由格子決定（倍率已反映在卡片大小上）
    init(containerSize: CGSize, columns: Int, rows: Int, iconScale: Double, labelFontSize: Double, showsLabels: Bool, compact: Bool,
         topInset: CGFloat = 0, windowed: Bool = false) {
        self.containerSize = containerSize
        self.columns = max(1, columns)
        self.rows = max(1, rows)
        self.labelFontSize = labelFontSize
        self.showsLabels = showsLabels
        labelSpacing = 7

        let width = max(containerSize.width, 200)
        let height = max(containerSize.height, 200)
        // 上方留給搜尋列、下方留給頁碼點；比例參考經典啟動台
        let horizontalMargin = windowed ? WindowModeCard.horizontalMargin : width * (compact ? 0.05 : 0.10)
        var topMargin = windowed ? WindowModeCard.gridTop : compact ? 76.0 : min(118, height * 0.11)
        let bottomMargin = windowed ? WindowModeCard.bottomMargin : compact ? 58.0 : min(96, height * 0.09)
        var barY = windowed ? WindowModeCard.headerHeight / 2 : compact ? 38 : max(40, topMargin * 0.42)
        // 瀏海會遮住螢幕最上緣：搜尋列整個移到瀏海下方（高度 32 → 中心 = 瀏海 + 8 + 16），格線跟著下移避免與搜尋列重疊
        if topInset > 0 {
            barY = max(barY, topInset + 8 + 16)
            topMargin = max(topMargin, barY + 16 + 24)
        }
        searchBarY = barY
        pageDotsY = windowed ? height - bottomMargin / 2 : height - bottomMargin * 0.52

        // 格子尺寸取整點、格線原點取整點：圖示與名稱圖都是整數像素的點陣圖，
        // 只要格子落在小數座標，Core Animation 取樣時就會插值，邊緣與文字因此發糊
        let cellWidth = ((width - horizontalMargin * 2) / CGFloat(self.columns)).rounded(.down)
        let cellHeight = ((height - topMargin - bottomMargin) / CGFloat(self.rows)).rounded(.down)
        let gridWidth = cellWidth * CGFloat(self.columns)
        let gridHeight = cellHeight * CGFloat(self.rows)
        gridRect = CGRect(
            x: ((width - gridWidth) / 2).rounded(), y: topMargin.rounded(),
            width: gridWidth, height: gridHeight
        )
        cellSize = CGSize(width: cellWidth, height: cellHeight)

        let labelHeight = showsLabels ? labelFontSize * 1.35 + labelSpacing : 0
        if windowed {
            iconSize = max(24, min(256, min(cellSize.width * 0.58, (cellSize.height - labelHeight) * 0.8).rounded()))
        } else {
            let base = min(cellSize.width * 0.5, (cellSize.height - labelHeight) * 0.66)
            iconSize = max(24, min(256, (base * iconScale).rounded()))
        }
    }

    /// 直接指定格線區域與圖示大小（資料夾面板用：格子大小沿用主畫面）。
    init(containerSize: CGSize, columns: Int, rows: Int, iconSize: CGFloat, labelFontSize: Double, showsLabels: Bool, gridRect: CGRect) {
        self.containerSize = containerSize
        self.columns = max(1, columns)
        self.rows = max(1, rows)
        self.iconSize = iconSize
        self.labelFontSize = labelFontSize
        self.showsLabels = showsLabels
        self.gridRect = gridRect
        labelSpacing = 7
        cellSize = CGSize(width: gridRect.width / CGFloat(self.columns), height: gridRect.height / CGFloat(self.rows))
        searchBarY = 0
        pageDotsY = containerSize.height - 16
    }

    /// 名稱文字區高度。
    var labelHeight: CGFloat { showsLabels ? (labelFontSize * 1.35).rounded(.up) : 0 }

    // MARK: - 位置

    /// 第 index 格的外框（頁面座標）。
    func cellFrame(_ index: Int) -> CGRect {
        let column = index % columns
        let row = index / columns
        return CGRect(
            x: gridRect.minX + CGFloat(column) * cellSize.width,
            y: gridRect.minY + CGFloat(row) * cellSize.height,
            width: cellSize.width, height: cellSize.height
        )
    }

    func cellCenter(_ index: Int) -> CGPoint {
        let frame = cellFrame(index)
        return CGPoint(x: frame.midX, y: frame.midY)
    }

    /// 第 index 格圖示的中心（圖示+名稱整組在格子內垂直置中，圖示在上半）。
    func iconCenter(_ index: Int) -> CGPoint {
        let center = cellCenter(index)
        let block = iconSize + (showsLabels ? labelSpacing + labelHeight : 0)
        return CGPoint(x: center.x, y: center.y - block / 2 + iconSize / 2)
    }

    /// 第 index 格圖示本體的外框。
    func iconFrame(_ index: Int) -> CGRect {
        let center = iconCenter(index)
        // 原點取整到整點：奇偶不同的 iconSize 與格子尺寸會讓圖示落在半個點上，1x 螢幕會被插值而發糊
        return CGRect(x: (center.x - iconSize / 2).rounded(), y: (center.y - iconSize / 2).rounded(), width: iconSize, height: iconSize)
    }

    /// 第 index 格可點擊的範圍：圖示＋名稱，四周多留一點，點在格子間的空白處不算（會收起啟動台，與經典啟動台相同）。
    func hotRect(_ index: Int) -> CGRect {
        var rect = iconFrame(index)
        if showsLabels {
            rect.size.height += labelSpacing + labelHeight
            let labelWidth = min(cellSize.width - 12, max(iconSize, cellSize.width * 0.8))
            rect = rect.union(CGRect(x: rect.midX - labelWidth / 2, y: rect.maxY - labelHeight, width: labelWidth, height: labelHeight))
        }
        return rect.insetBy(dx: -8, dy: -6)
    }

    /// 點擊命中測試：點落在哪一格的可點擊範圍內。
    /// - Parameter point: 頁面座標
    /// - Returns: 格子索引（不保證該格有項目）；落在格線外或格子空白處時為 nil
    func cellIndex(atHotPoint point: CGPoint) -> Int? {
        guard gridRect.contains(point) else { return nil }
        let column = min(columns - 1, Int((point.x - gridRect.minX) / cellSize.width))
        let row = min(rows - 1, Int((point.y - gridRect.minY) / cellSize.height))
        let index = row * columns + column
        return hotRect(index).contains(point) ? index : nil
    }

    /// 游標所在的格子（依列、欄計算，超出格線範圍時夾到最近的一格）。
    /// - Parameters:
    ///   - point: 頁面座標
    ///   - count: 此頁目前的項目數；落在最後一個項目之後的空白區時回傳 `count`（代表放在最後）
    /// - Returns: 格子索引（0…count）
    func insertionIndex(at point: CGPoint, count: Int) -> Int {
        let column = min(columns - 1, max(0, Int((point.x - gridRect.minX) / cellSize.width)))
        let row = min(rows - 1, max(0, Int((point.y - gridRect.minY) / cellSize.height)))
        return min(row * columns + column, count)
    }

    /// 游標是否落在某格圖示的「中心區」（放開會合併成資料夾，而不是插入）。
    func isOverIconCenter(_ point: CGPoint, index: Int) -> Bool {
        let center = iconCenter(index)
        let radius = iconSize * 0.34
        return abs(point.x - center.x) < radius && abs(point.y - center.y) < radius
    }
}
