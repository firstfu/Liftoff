//
//  TrackpadGesture.swift
//  Liftoff
//
//  觸控板「拇指＋三指捏合」開啟啟動台、張開關閉——重現經典啟動台手勢。
//  系統不會把四/五指手勢當事件送給一般 App，只能讀觸控板原始觸點：私有框架 MultitouchSupport
//  （BetterTouchTool、MiddleClick 等工具長年使用的作法）。以 dlopen/dlsym 動態載入，符號不存在時直接停用此功能。
//
//  捏合或滑動：四指左右滑動（切換桌面）收手時手指會收攏，看起來像捏合；由 `PinchIntent` 以手部重心平移分辨，
//  判定為滑動的整個手勢都不回報（issue #10）。
//
//  跟手：手勢進行中每幀回報「目前張開程度 ÷ 起始張開程度」（ratio），放手時回報 ended，
//  由呼叫端讓整個視窗隨 ratio 連續縮放/淡入，放手再依進度決定完成或回彈（和經典啟動台一樣）。
//
//  效能：觸控板有手指時系統每幀（約 90–120Hz）回呼一次；少於 4 指時第一時間返回，只花幾微秒。
//  沒有手指接觸時完全沒有回呼。
//

import Foundation
import Synchronization

nonisolated final class TrackpadGesture: Sendable {
    enum Event: Sendable {
        /// 手勢進行中：ratio < 1 表示手指往內收（開啟方向）、> 1 表示往外張（關閉方向）；
        /// time 是觸控板回報的時間戳（秒），供放手時算速度
        case changed(ratio: Double, time: Double)
        /// 手指離開（少於 4 指），手勢結束
        case ended
    }

    static let shared = TrackpadGesture()

    // MARK: 私有框架函式

    private typealias ContactCallback = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, Int32, Double, Int32) -> Int32
    private typealias CreateListFn = @convention(c) () -> Unmanaged<CFMutableArray>?
    private typealias RegisterFn = @convention(c) (UnsafeMutableRawPointer, ContactCallback) -> Void
    private typealias StartFn = @convention(c) (UnsafeMutableRawPointer, Int32) -> Int32
    private typealias StopFn = @convention(c) (UnsafeMutableRawPointer) -> Int32

    private struct Functions: @unchecked Sendable {
        let createList: CreateListFn
        let register: RegisterFn
        let unregister: RegisterFn
        let start: StartFn
        let stop: StopFn
    }

    private static let functions: Functions? = {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport", RTLD_LAZY),
              let createList = dlsym(handle, "MTDeviceCreateList"),
              let register = dlsym(handle, "MTRegisterContactFrameCallback"),
              let unregister = dlsym(handle, "MTUnregisterContactFrameCallback"),
              let start = dlsym(handle, "MTDeviceStart"),
              let stop = dlsym(handle, "MTDeviceStop") else { return nil }
        return Functions(
            createList: unsafeBitCast(createList, to: CreateListFn.self),
            register: unsafeBitCast(register, to: RegisterFn.self),
            unregister: unsafeBitCast(unregister, to: RegisterFn.self),
            start: unsafeBitCast(start, to: StartFn.self),
            stop: unsafeBitCast(stop, to: StopFn.self)
        )
    }()

    // MARK: 狀態

    private struct Devices: @unchecked Sendable {
        var list: CFMutableArray?
        var refs: [UnsafeMutableRawPointer] = []
    }

    private struct Tracking: Sendable {
        var active = false
        var fingers = 0
        var baseline: Double = 0
        /// 取基準時的手部重心，用來量平移距離分辨捏合與滑動
        var originX: Double = 0
        var originY: Double = 0
        /// 是否已回報過 changed（決定放手時要不要補發 ended）
        var reported = false
        var intent = PinchIntent()
        /// 上一次回呼的時間戳，用來認出「新的一次觸碰」
        var lastTime: Double = 0
    }

    private let devices = Mutex(Devices())
    private let tracking = Mutex(Tracking())
    private let handler = Mutex<(@Sendable (Event) -> Void)?>(nil)

    var isAvailable: Bool { Self.functions != nil }

    /// 開始監聽所有觸控板。
    /// - Parameter onPinch: 手勢進行與結束時呼叫（在觸控板執行緒上，呼叫端需自行切回主執行緒）
    /// - Returns: 是否成功啟動（私有框架不可用或沒有觸控板時為 false）
    @discardableResult
    func start(onPinch: @escaping @Sendable (Event) -> Void) -> Bool {
        stop()
        guard let fn = Self.functions, let list = fn.createList()?.takeRetainedValue() else { return false }
        handler.withLock { $0 = onPinch }
        var refs: [UnsafeMutableRawPointer] = []
        for index in 0..<CFArrayGetCount(list) {
            guard let raw = CFArrayGetValueAtIndex(list, index) else { continue }
            let device = UnsafeMutableRawPointer(mutating: raw)
            fn.register(device, Self.callback)
            _ = fn.start(device, 0)
            refs.append(device)
        }
        // 保留 CFArray 讓裝置物件存活到 stop()
        devices.withLock { $0 = Devices(list: list, refs: refs) }
        Log.input.info("觸控板手勢啟動，裝置 \(refs.count) 個")
        return !refs.isEmpty
    }

    func stop() {
        guard let fn = Self.functions else { return }
        let current = devices.withLock { state -> Devices in
            let old = state
            state = Devices()
            return old
        }
        for device in current.refs {
            fn.unregister(device, Self.callback)
            _ = fn.stop(device)
        }
        handler.withLock { $0 = nil }
    }

    /// C 回呼：不能捕捉任何狀態，所以轉給單例處理。
    private static let callback: ContactCallback = { _, touches, count, timestamp, _ in
        TrackpadGesture.shared.process(touches: touches, count: Int(count), timestamp: timestamp)
        return 0
    }

    // MARK: 手勢判斷

    /// MTTouch 結構（96 bytes）中用到的欄位位移：identifier@16、state@20、normalized.x@32、normalized.y@36。
    private static let touchStride = 96
    /// 觸控板寬高比（正規化座標兩軸都是 0…1，算距離前要把 x 拉回實際比例）
    private static let aspect = 1.6
    /// 捏合到起始張開程度的這個比例時視為「完全開啟」；張開到這個比例時視為「完全關閉」（視窗進度 0…1 的兩端）
    static let inwardRatio = 0.68
    static let outwardRatio = 1.45

    private func process(touches: UnsafeMutableRawPointer?, count: Int, timestamp: Double) {
        // 絕大多數回呼是單指移動游標：最快速的路徑直接返回
        guard count >= 4, let touches else {
            finishIfNeeded(allLifted: count == 0, time: timestamp)
            return
        }

        var xs: [Double] = []
        var ys: [Double] = []
        xs.reserveCapacity(count)
        ys.reserveCapacity(count)
        for index in 0..<count {
            let base = touches + index * Self.touchStride
            let state = base.load(fromByteOffset: 20, as: Int32.self)
            // 3 = 接觸開始、4 = 接觸中；懸停與離開的觸點不算
            guard state == 3 || state == 4 else { continue }
            xs.append(Double(base.load(fromByteOffset: 32, as: Float.self)) * Self.aspect)
            ys.append(Double(base.load(fromByteOffset: 36, as: Float.self)))
        }
        let fingers = xs.count
        // 有手指開始離開（剩不到 4 指）= 放手
        guard fingers >= 4 else {
            finishIfNeeded(allLifted: false, time: timestamp)
            return
        }
        let spread = Self.spread(xs: xs, ys: ys)
        let cx = xs.reduce(0, +) / Double(fingers)
        let cy = ys.reduce(0, +) / Double(fingers)

        var swipeDetected = false
        let ratio = tracking.withLock { state -> Double? in
            Self.expireIfStale(&state, time: timestamp)
            // 新手勢，或手指數改變（中心點與張開程度會跳動）→ 重新取基準；
            // 已做出的捏合／滑動判定與 reported 保留，換指數不會讓滑動變回「未判定」
            if !state.active || state.fingers != fingers {
                state.active = true
                state.fingers = fingers
                state.baseline = spread
                state.originX = cx
                state.originY = cy
                return nil
            }
            guard state.baseline > 0.01 else { return nil }
            let ratio = spread / state.baseline
            let travel = ((cx - state.originX) * (cx - state.originX) + (cy - state.originY) * (cy - state.originY)).squareRoot() / state.baseline
            let wasUndecided = state.intent.phase == .undecided
            let allowed = state.intent.update(ratio: ratio, travel: travel)
            guard allowed else {
                swipeDetected = wasUndecided && state.intent.phase == .swipe
                return nil
            }
            state.reported = true
            return ratio
        }
        if swipeDetected { Log.input.debug("四指手勢判定為滑動，不當作捏合") }
        if let ratio, let handler = handler.withLock({ $0 }) { handler(.changed(ratio: ratio, time: timestamp)) }
    }

    /// 兩次回呼間隔超過這個秒數就視為新的一次觸碰（回呼只在有手指接觸時才來）
    private static let sessionGap = 0.3

    /// 新的一次觸碰：清掉上一次留下的滑動判定。
    /// 平常靠「所有手指離開」那一幀（count == 0）清除，這裡是保險，萬一沒收到那一幀也不會讓捏合從此失效。
    private static func expireIfStale(_ state: inout Tracking, time: Double) {
        if time - state.lastTime > sessionGap { state.intent = PinchIntent() }
        state.lastTime = time
    }

    /// 手勢結束（少於 4 指）：若這次手勢回報過進度，補發 ended 讓呼叫端決定完成或回彈。
    /// - Parameters:
    ///   - allLifted: 所有手指都已離開觸控板
    ///   - time: 觸控板時間戳（秒）
    private func finishIfNeeded(allLifted: Bool, time: Double) {
        let reported = tracking.withLock { state -> Bool in
            Self.expireIfStale(&state, time: time)
            let was = state.active && state.reported
            // 滑動判定要撐到所有手指離開才解除：收手時手指陸續離開，剩下的若又湊滿四指並收攏，
            // 會被當成全新的手勢重新判定，正是 issue #10 要擋的情況
            let keepSwipe = !allLifted && state.intent.phase == .swipe
            let previous = state
            state = Tracking()
            if keepSwipe { state.intent = previous.intent }
            state.lastTime = previous.lastTime
            return was
        }
        if reported, let handler = handler.withLock({ $0 }) { handler(.ended) }
    }

    /// 張開程度：各指到重心的平均距離。
    static func spread(xs: [Double], ys: [Double]) -> Double {
        guard !xs.isEmpty else { return 0 }
        let cx = xs.reduce(0, +) / Double(xs.count)
        let cy = ys.reduce(0, +) / Double(ys.count)
        var total = 0.0
        for (x, y) in zip(xs, ys) { total += ((x - cx) * (x - cx) + (y - cy) * (y - cy)).squareRoot() }
        return total / Double(xs.count)
    }
}
