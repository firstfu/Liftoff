//
//  PagerState.swift
//  Liftoff
//
//  翻頁狀態與輸入處理：
//  - 觸控板雙指橫滑：頁面 1:1 跟手，放開時依位移與速度決定翻頁，以彈簧動畫歸位
//  - 滑鼠滾輪（非連續捲動）：每一格翻一頁，並有冷卻時間避免一次滾太多頁
//  - 觸控板直向滑動：累積到門檻翻一頁
//  - 滑鼠在空白處按住左右拖：與觸控板相同的跟手與放開判斷（經典啟動台可用滑鼠拖動翻頁）
//  所有捲動事件在 NSPanel.sendEvent 就攔下直接送到這裡，不經過 SwiftUI 的捲動系統。
//  `offset` 每個事件都會變，只有頁面容器依賴它，其他畫面不會因此重算。
//

import AppKit
import Observation
import SwiftUI

@Observable
final class PagerState {
    /// 目前頁碼
    var page = 0
    /// 跟手中的水平位移（points，正值 = 往右拖、看前一頁）
    var offset: CGFloat = 0

    /// 頁面寬度：跟手位移的上限與翻頁門檻都以它為準。每次捲動前由面板依目前版面設定（見 LaunchpadWindowController）
    @ObservationIgnored var pageWidth: CGFloat = 1
    @ObservationIgnored private var isTracking = false
    /// 是否正在跟手（滑鼠拖動翻頁用來分辨「點擊」與「拖動」）
    var isMouseTracking: Bool { isTracking }
    @ObservationIgnored private var verticalAccumulator: CGFloat = 0
    @ObservationIgnored private var verticalFlipped = false
    @ObservationIgnored private var lastWheelFlip = ContinuousClock.now - .seconds(1)
    /// 最近的位移樣本（時間, dx），估算放開瞬間的速度
    @ObservationIgnored private var samples: [(time: TimeInterval, dx: CGFloat)] = []

    static let pageAnimation = Animation.spring(response: 0.38, dampingFraction: 0.9)

    /// 翻到指定頁（夾在有效範圍內）。
    func go(to target: Int, pageCount: Int, animated: Bool = true) {
        let clamped = max(0, min(target, max(pageCount - 1, 0)))
        guard clamped != page || offset != 0 else { return }
        if animated {
            withAnimation(Self.pageAnimation) {
                page = clamped
                offset = 0
            }
        } else {
            page = clamped
            offset = 0
        }
    }

    /// 處理捲動事件。
    /// - Parameters:
    ///   - event: scrollWheel 事件
    ///   - pageCount: 總頁數
    /// - Returns: 是否已處理
    func handleScroll(_ event: NSEvent, pageCount: Int) -> Bool {
        guard pageCount > 0 else { return false }
        if event.hasPreciseScrollingDeltas {
            handleTrackpad(event, pageCount: pageCount)
        } else {
            handleWheel(event, pageCount: pageCount)
        }
        return true
    }

    private func handleTrackpad(_ event: NSEvent, pageCount: Int) {
        // 慣性捲動（手指離開後系統補發的事件）一律忽略，由我們自己的彈簧動畫收尾
        guard event.momentumPhase.isEmpty else { return }

        switch event.phase {
        case .began, .mayBegin:
            isTracking = true
            samples.removeAll()
            verticalAccumulator = 0
            verticalFlipped = false
        case .changed:
            guard isTracking else { return }
            let dx = event.scrollingDeltaX
            let dy = event.scrollingDeltaY
            if abs(dx) >= abs(dy) {
                applyDrag(dx, pageCount: pageCount, timestamp: event.timestamp)
            } else if offset == 0, !verticalFlipped {
                // 直向滑動：累積到門檻翻一頁（往上滑 = 下一頁）
                verticalAccumulator += dy
                if abs(verticalAccumulator) > 50 {
                    verticalFlipped = true
                    go(to: page + (verticalAccumulator < 0 ? 1 : -1), pageCount: pageCount)
                }
            }
        case .ended, .cancelled:
            guard isTracking else { return }
            isTracking = false
            settle(pageCount: pageCount)
        default:
            break
        }
    }

    // MARK: 滑鼠拖動翻頁

    /// 滑鼠按住拖動中：位移 1:1 跟手。
    /// - Parameters:
    ///   - dx: 這次事件的水平位移（往右為正）
    ///   - timestamp: 事件時間（估算放開速度）
    func mouseDragged(_ dx: CGFloat, pageCount: Int, timestamp: TimeInterval) {
        guard pageCount > 0 else { return }
        if !isTracking {
            isTracking = true
            samples.removeAll()
        }
        applyDrag(dx, pageCount: pageCount, timestamp: timestamp)
    }

    /// 滑鼠放開：依位移與速度翻頁或彈回。
    func mouseDragEnded(pageCount: Int) {
        guard isTracking else { return }
        isTracking = false
        settle(pageCount: max(pageCount, 1))
    }

    private func applyDrag(_ dx: CGFloat, pageCount: Int, timestamp: TimeInterval) {
        var next = offset + dx
        // 第一頁往右、最後一頁往左：橡皮筋阻尼
        let atStart = page == 0 && next > 0
        let atEnd = page >= pageCount - 1 && next < 0
        if atStart || atEnd { next = offset + dx * 0.3 }
        offset = max(-pageWidth, min(pageWidth, next))
        samples.append((timestamp, dx))
        if samples.count > 8 { samples.removeFirst(samples.count - 8) }
    }

    /// 放開手指：位移超過 15% 頁寬或速度夠快就翻頁，否則彈回。
    private func settle(pageCount: Int) {
        let velocity = recentVelocity()
        var target = page
        if offset < -pageWidth * 0.15 || velocity < -600 { target = page + 1 }
        if offset > pageWidth * 0.15 || velocity > 600 { target = page - 1 }
        target = max(0, min(target, pageCount - 1))
        withAnimation(Self.pageAnimation) {
            page = target
            offset = 0
        }
    }

    /// 最近 80ms 內的平均速度（points/秒）。
    private func recentVelocity() -> CGFloat {
        guard let last = samples.last else { return 0 }
        let recent = samples.filter { last.time - $0.time < 0.08 }
        guard let first = recent.first, last.time > first.time else { return 0 }
        return recent.map(\.dx).reduce(0, +) / CGFloat(last.time - first.time)
    }

    private func handleWheel(_ event: NSEvent, pageCount: Int) {
        let delta = abs(event.scrollingDeltaY) > abs(event.scrollingDeltaX) ? event.scrollingDeltaY : event.scrollingDeltaX
        guard abs(delta) > 0.1, ContinuousClock.now - lastWheelFlip > .milliseconds(260) else { return }
        lastWheelFlip = .now
        go(to: page + (delta < 0 ? 1 : -1), pageCount: pageCount)
    }
}
