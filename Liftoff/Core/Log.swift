//
//  Log.swift
//  Liftoff
//
//  統一的 os.Logger 與 signpost 入口。所有分類共用同一個 subsystem，
//  方便用 `/usr/bin/log stream --predicate 'subsystem == "com.firstfu.Liftoff"'` 一次看完。
//

import os

nonisolated enum Log {
    static let subsystem = "com.firstfu.Liftoff"

    static let app = Logger(subsystem: subsystem, category: "app")
    static let catalog = Logger(subsystem: subsystem, category: "catalog")
    static let icons = Logger(subsystem: subsystem, category: "icons")
    static let layout = Logger(subsystem: subsystem, category: "layout")
    static let ui = Logger(subsystem: subsystem, category: "ui")
    static let input = Logger(subsystem: subsystem, category: "input")
    static let preview = Logger(subsystem: subsystem, category: "preview")
    static let perf = Logger(subsystem: subsystem, category: "perf")

    /// Instruments「Points of Interest」軌道用的 signposter（顯示/隱藏、掃描、圖示載入的區間）
    static let signposter = OSSignposter(subsystem: subsystem, category: .pointsOfInterest)
}

/// 以毫秒表示的經過時間，log 用。
nonisolated func milliseconds(since start: ContinuousClock.Instant) -> Double {
    let elapsed = ContinuousClock.now - start
    return Double(elapsed.components.seconds) * 1000 + Double(elapsed.components.attoseconds) / 1e15
}
