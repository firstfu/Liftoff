//
//  GridMetricsTests.swift
//  LiftoffTests
//
//  格線幾何：格子位置、命中測試、插入位置、合併判定區。
//

import CoreGraphics
import Testing
@testable import Liftoff

@MainActor
struct GridMetricsTests {
    private let metrics = GridMetrics(
        containerSize: CGSize(width: 1920, height: 1080), columns: 7, rows: 5,
        iconScale: 1, labelFontSize: 13, showsLabels: true, compact: false
    )

    @Test func cellsTileTheGrid() {
        let first = metrics.cellFrame(0)
        let last = metrics.cellFrame(34)
        #expect(abs(first.minX - metrics.gridRect.minX) < 0.001)
        #expect(abs(last.maxX - metrics.gridRect.maxX) < 0.001)
        #expect(abs(last.maxY - metrics.gridRect.maxY) < 0.001)
    }

    @Test func iconSizeIsReasonableForFullHD() {
        #expect(metrics.iconSize > 70 && metrics.iconSize < 130)
    }

    @Test func hitTestFindsIconAndIgnoresGaps() {
        let index = 9
        #expect(metrics.cellIndex(atHotPoint: metrics.iconCenter(index)) == index)
        // 格子最右上角（圖示與名稱之外）不算點到
        let cell = metrics.cellFrame(index)
        #expect(metrics.cellIndex(atHotPoint: CGPoint(x: cell.maxX - 1, y: cell.minY + 1)) == nil)
        // 搜尋列所在的上方區域不算
        #expect(metrics.cellIndex(atHotPoint: CGPoint(x: 960, y: 20)) == nil)
    }

    @Test func insertionIndexClampsToItemCount() {
        let farBottomRight = CGPoint(x: metrics.gridRect.maxX - 1, y: metrics.gridRect.maxY - 1)
        #expect(metrics.insertionIndex(at: farBottomRight, count: 10) == 10)
        #expect(metrics.insertionIndex(at: metrics.cellCenter(3), count: 10) == 3)
    }

    @Test func mergeZoneIsTheIconCenter() {
        let center = metrics.iconCenter(5)
        #expect(metrics.isOverIconCenter(center, index: 5))
        #expect(!metrics.isOverIconCenter(CGPoint(x: center.x + metrics.iconSize * 0.45, y: center.y), index: 5))
    }

    @Test func iconScaleChangesIconSize() {
        let big = GridMetrics(containerSize: CGSize(width: 1920, height: 1080), columns: 7, rows: 5,
                              iconScale: 1.3, labelFontSize: 13, showsLabels: true, compact: false)
        #expect(big.iconSize > metrics.iconSize)
    }
}
