//
//  MultitouchDeviceWatcher.swift
//  Liftoff
//
//  觸控板裝置被系統重建時通知呼叫端。
//  MultitouchSupport 的回呼是註冊在「某一個裝置物件」上；核心會把觸控板的 AppleMultitouchDevice 整個砍掉重建
//  （閒置時約每 15 分鐘一次、休眠喚醒、藍牙觸控板重連），舊物件上的回呼從此不再被呼叫，捏合就失效。
//  這裡用公開的 IOKit 配對通知盯著新裝置出現，由呼叫端重新註冊。沒有裝置變動時完全不耗資源。
//

import Foundation
import IOKit

final class MultitouchDeviceWatcher {
    /// 有新的觸控板裝置出現（已合併短時間內的連續重建）
    var onDeviceAppeared: (() -> Void)?

    private var port: IONotificationPortRef?
    private var iterator: io_iterator_t = 0
    private var pending: DispatchWorkItem?
    /// 核心重建時會連續拆裝好幾次，等穩定一下再通知
    private static let settleDelay = 1.0

    func start() {
        guard port == nil, let port = IONotificationPortCreate(kIOMainPortDefault) else { return }
        IONotificationPortSetDispatchQueue(port, .main)
        let context = Unmanaged.passUnretained(self).toOpaque()
        let result = IOServiceAddMatchingNotification(
            port, kIOFirstMatchNotification, IOServiceMatching("AppleMultitouchDevice"),
            Self.callback, context, &iterator
        )
        guard result == KERN_SUCCESS else {
            IONotificationPortDestroy(port)
            Log.input.error("無法監聽觸控板裝置變動：\(result)")
            return
        }
        self.port = port
        // 必須先把既有裝置取完，通知才會開始；既有裝置不算「新出現」
        Self.drain(iterator)
    }

    func stop() {
        pending?.cancel()
        pending = nil
        if iterator != 0 {
            IOObjectRelease(iterator)
            iterator = 0
        }
        if let port {
            IONotificationPortDestroy(port)
            self.port = nil
        }
    }

    private func deviceAppeared() {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in
            Log.input.info("觸控板裝置重新出現，重新註冊手勢")
            self?.onDeviceAppeared?()
        }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.settleDelay, execute: work)
    }

    /// 通知送在主佇列上（`IONotificationPortSetDispatchQueue(.main)`）
    private static let callback: IOServiceMatchingCallback = { context, iterator in
        MultitouchDeviceWatcher.drain(iterator)
        // 指標本身不是 Sendable，轉成位址帶進主執行緒區塊
        guard let address = context.map({ UInt(bitPattern: $0) }) else { return }
        MainActor.assumeIsolated {
            guard let pointer = UnsafeRawPointer(bitPattern: address) else { return }
            Unmanaged<MultitouchDeviceWatcher>.fromOpaque(pointer).takeUnretainedValue().deviceAppeared()
        }
    }

    private nonisolated static func drain(_ iterator: io_iterator_t) {
        while case let service = IOIteratorNext(iterator), service != 0 { IOObjectRelease(service) }
    }
}
