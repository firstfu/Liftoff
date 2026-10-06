//
//  PinchRelease.swift
//  Liftoff
//
//  捏合放手時「完成或回彈」的判斷：除了進度門檻，也看放手前的速度。
//  只看進度的話，又快又小的捏合（進度不到門檻、但明顯是想開）會先淡入一點再回彈，看起來閃一下就消失（issue #9）。
//  經典啟動台與 iOS 的滑動手勢都把「快速甩一下」當成要完成，這裡比照辦理。
//  純邏輯、不碰視窗，方便單元測試。
//

import Foundation

nonisolated struct PinchRelease {
    /// 進度（朝這次手勢方向，0…1）到這個值，放手就完成
    static let commitProgress = 0.4
    /// 放手前朝目標方向的速度（進度/秒）到這個值，進度不足也完成
    static let flickVelocity = 1.0
    /// 速度取放手前這段時間的平均（秒）：太短會被單幀雜訊左右，太長會被手勢前段的速度稀釋
    static let velocityWindow = 0.1

    private var samples: [(time: Double, progress: Double)] = []

    /// 新手勢開始時清掉上一次的樣本。
    mutating func reset() { samples.removeAll(keepingCapacity: true) }

    /// 記錄一幀。
    /// - Parameters:
    ///   - time: 觸控板回報的時間戳（秒，只需單調遞增）
    ///   - progress: 朝這次手勢方向的進度（開啟 = 展開程度；關閉 = 收起程度）
    mutating func record(time: Double, progress: Double) {
        samples.append((time, progress))
        // 只需要窗口內的樣本＋窗口起點前一筆（當作速度的起點），更舊的丟掉避免陣列一直長
        while samples.count > 2, samples[1].time <= time - Self.velocityWindow { samples.removeFirst() }
    }

    /// 最後一幀的進度；沒有樣本時為 0。
    var progress: Double { samples.last?.progress ?? 0 }

    /// 放手前約 `velocityWindow` 秒內的平均速度（進度/秒）；樣本不足或時間差過小時為 0。
    var velocity: Double {
        guard let last = samples.last, let first = samples.first else { return 0 }
        let dt = last.time - first.time
        // 少於約一幀的時間差算出來的速度不可信
        guard dt >= 0.008 else { return 0 }
        return (last.progress - first.progress) / dt
    }

    /// 放手時是否完成這次手勢（否則回彈）。
    var shouldCommit: Bool {
        progress >= Self.commitProgress || (progress > 0 && velocity >= Self.flickVelocity)
    }
}
