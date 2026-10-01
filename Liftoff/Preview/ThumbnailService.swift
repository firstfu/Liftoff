//
//  ThumbnailService.swift
//  Liftoff（沿用自 DockLens，已在 DockLens 實測驗證）
//
//  視窗縮圖的擷取與快取，是整個 App 的效能核心。策略：
//  1. 「先給舊的、再換新的」（stale-while-revalidate）：快取命中立即顯示，同時背景重拍，拍好一張換一張。
//  2. 高速擷取：優先用 SkyLight `CGSHWCaptureWindowList`（~20ms/窗），失敗才退回 ScreenCaptureKit（~70ms/窗）。
//  3. 序列化：WindowServer 內部本就序列處理截圖，並行只會互搶；改用單一序列 queue，並以「世代編號」
//     讓游標移到下一個 Dock 圖示時，舊的擷取工作立即作廢，不浪費時間拍已經不需要的視窗。
//  4. 預熱：App 失去焦點時以低優先權先拍好它的視窗，之後游標移過去時快取已是新的。
//  5. 記憶體：擷取後立即縮小到顯示所需像素，並以 LRU 限制總量。
//

import AppKit
import ScreenCaptureKit
import Synchronization
import os

/// 可跨執行緒傳遞的縮圖影像。CGImage 建立後不可變，跨執行緒讀取安全。
nonisolated struct Thumbnail: @unchecked Sendable {
    let image: CGImage
    let capturedAt: ContinuousClock.Instant
}

nonisolated final class ThumbnailService: Sendable {
    private struct Entry {
        let thumbnail: Thumbnail
        let pid: pid_t
        var lastAccess: UInt64
    }

    private struct Cache {
        var entries: [CGWindowID: Entry] = [:]
        var accessCounter: UInt64 = 0
    }

    /// 快取上限（張）。單張約 0.5–1MB，上限約 50MB。
    private let capacity = 60
    /// 這個時間內拍過的縮圖視為新鮮，不重拍（游標在同一圖示附近晃動時省下重複擷取）
    private let freshness: Duration = .milliseconds(400)

    private let cache = Mutex(Cache())
    private let generation = Atomic<UInt64>(0)
    private let interactiveQueue = DispatchQueue(label: "Liftoff.capture.interactive", qos: .userInteractive)
    private let backgroundQueue = DispatchQueue(label: "Liftoff.capture.background", qos: .utility)
    private let fallback = ScreenCaptureKitFallback()
    /// 高速擷取結果不完整、需改用 ScreenCaptureKit 的視窗（視窗 ID → 所屬 pid，App 結束時一併清除）
    private let screenCaptureKitOnly = Mutex([CGWindowID: pid_t]())
    private let log = Logger(subsystem: "com.firstfu.Liftoff", category: "capture")

    // MARK: - 查詢

    /// 立即回傳快取中的縮圖（不觸發擷取）。
    func cached(_ windowID: CGWindowID) -> Thumbnail? {
        cache.withLock { cache in
            guard var entry = cache.entries[windowID] else { return nil }
            cache.accessCounter += 1
            entry.lastAccess = cache.accessCounter
            cache.entries[windowID] = entry
            return entry.thumbnail
        }
    }

    // MARK: - 擷取

    /// 互動式擷取：依序擷取視窗，每完成一張就在主執行緒回呼一次。
    /// 呼叫新的 `capture` 會讓先前尚未完成的互動擷取作廢。
    /// - Parameters:
    ///   - windows: 要擷取的視窗（依顯示順序，前面的先拍）
    ///   - maxPixelWidth: 縮圖最大像素寬（通常 = 卡片寬 × 螢幕 backingScale）
    ///   - onImage: 每張完成時在主執行緒呼叫
    func capture(
        _ windows: [WindowInfo],
        maxPixelWidth: Int,
        onImage: @escaping @MainActor @Sendable (CGWindowID, Thumbnail) -> Void
    ) {
        let token = generation.add(1, ordering: .relaxed).newValue
        interactiveQueue.async { [self] in
            let start = ContinuousClock.now
            var count = 0
            for window in windows {
                // 游標已移到別的 App：剩下的不用拍了
                guard generation.load(ordering: .relaxed) == token else { return }
                guard let thumbnail = captureIfNeeded(window, maxPixelWidth: maxPixelWidth) else { continue }
                count += 1
                DispatchQueue.main.async { onImage(window.id, thumbnail) }
            }
            if count > 0 {
                log.debug("互動擷取 \(count) 張，耗時 \(ContinuousClock.now - start, privacy: .public)")
            }
        }
    }

    /// 取消所有尚未開始的互動擷取。
    func cancelInteractive() {
        generation.add(1, ordering: .relaxed)
    }

    /// 背景預熱：以低優先權擷取某 App 所有非最小化視窗。
    /// - Parameters:
    ///   - pid: App 的 pid
    ///   - maxPixelWidth: 縮圖最大像素寬
    func prewarm(pid: pid_t, maxPixelWidth: Int) {
        backgroundQueue.async { [self] in
            let windows = WindowEnumerator.windows(for: pid, includeOtherSpaces: false)
            for window in windows where !window.isMinimized {
                _ = captureIfNeeded(window, maxPixelWidth: maxPixelWidth)
            }
        }
    }

    /// App 結束時清除它的所有縮圖，釋放記憶體。
    func purge(pid: pid_t) {
        cache.withLock { cache in
            cache.entries = cache.entries.filter { $0.value.pid != pid }
        }
        screenCaptureKitOnly.withLock { $0 = $0.filter { $0.value != pid } }
    }

    /// 清空所有縮圖（啟動台收起一段時間後呼叫，平常不佔記憶體）。
    func purgeAll() {
        cache.withLock { $0.entries.removeAll() }
    }

    /// 移除單一視窗的縮圖（例如視窗已被關閉）。
    func purge(windowID: CGWindowID) {
        _ = cache.withLock { $0.entries.removeValue(forKey: windowID) }
        _ = screenCaptureKitOnly.withLock { $0.removeValue(forKey: windowID) }
    }

    // MARK: - 內部

    /// 快取不夠新才擷取；最小化視窗的畫面不會變，已有快取就沿用。
    private func captureIfNeeded(_ window: WindowInfo, maxPixelWidth: Int) -> Thumbnail? {
        if let existing = cache.withLock({ $0.entries[window.id]?.thumbnail }) {
            let age = ContinuousClock.now - existing.capturedAt
            if age < freshness || window.isMinimized { return existing }
        }
        guard let raw = captureRaw(window, maxPixelWidth: maxPixelWidth),
              raw.width > 1, raw.height > 1,
              let scaled = Self.downscale(raw, maxPixelWidth: maxPixelWidth) else { return nil }
        let thumbnail = Thumbnail(image: scaled, capturedAt: .now)
        store(thumbnail, for: window)
        return thumbnail
    }

    /// 先用高速私有 API；若結果的長寬比與視窗不符就改用 ScreenCaptureKit，並記住該視窗之後直接走 ScreenCaptureKit。
    /// 為什麼要檢查：部分以 Metal/IOSurface 自繪的 App（例如 cmux 終端機）用私有 API 只截得到視窗邊的一小條
    /// （實測 1643×977 的視窗只截到 40×977），ScreenCaptureKit 則能拿到完整合成畫面。
    private func captureRaw(_ window: WindowInfo, maxPixelWidth: Int) -> CGImage? {
        let knownIncomplete = screenCaptureKitOnly.withLock { $0[window.id] != nil }
        if !knownIncomplete, let image = SkyLight.captureWindow(window.id) {
            if Self.matchesAspect(image, of: window.frame) { return image }
            screenCaptureKitOnly.withLock { $0[window.id] = window.pid }
            log.notice("視窗 \(window.id) 高速擷取不完整（\(image.width)×\(image.height)），改用 ScreenCaptureKit")
        }
        return fallback.capture(window.id, maxPixelWidth: maxPixelWidth)
    }

    /// 影像長寬比是否與視窗外框相符（容許 15% 誤差，涵蓋標題列/陰影等細微差異）。
    static func matchesAspect(_ image: CGImage, of frame: CGRect, tolerance: CGFloat = 0.15) -> Bool {
        guard frame.width > 0, frame.height > 0, image.width > 0, image.height > 0 else { return false }
        let expected = frame.width / frame.height
        let actual = CGFloat(image.width) / CGFloat(image.height)
        return abs(actual - expected) / expected <= tolerance
    }

    private func store(_ thumbnail: Thumbnail, for window: WindowInfo) {
        cache.withLock { cache in
            cache.accessCounter += 1
            cache.entries[window.id] = Entry(thumbnail: thumbnail, pid: window.pid, lastAccess: cache.accessCounter)
            // LRU 淘汰：超量時一次砍到 80%，避免每次插入都排序
            if cache.entries.count > capacity {
                let keep = cache.entries.sorted { $0.value.lastAccess > $1.value.lastAccess }.prefix(capacity * 4 / 5)
                cache.entries = Dictionary(uniqueKeysWithValues: keep.map { ($0.key, $0.value) })
            }
        }
    }

    /// 縮小影像到指定像素寬（保持比例）。原圖已夠小時直接回傳。
    /// 在擷取當下就縮小，可讓快取記憶體降到約 1/4，也讓 SwiftUI 繪製時不必再縮放大圖。
    static func downscale(_ image: CGImage, maxPixelWidth: Int) -> CGImage? {
        guard image.width > maxPixelWidth else { return image }
        let scale = CGFloat(maxPixelWidth) / CGFloat(image.width)
        let width = maxPixelWidth
        let height = max(1, Int((CGFloat(image.height) * scale).rounded()))
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return image }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage() ?? image
    }
}

// MARK: - ScreenCaptureKit 備援

/// 私有 API 不可用時的公開 API 備援。只會在擷取序列 queue 上被呼叫，
/// 內部以 semaphore 把非同步 API 轉成同步（在自有 DispatchQueue 上阻塞是安全的，不會卡住 Swift concurrency 執行緒池）。
nonisolated final class ScreenCaptureKitFallback: Sendable {
    private struct ContentBox: @unchecked Sendable {
        var content: SCShareableContent?
        var fetchedAt: ContinuousClock.Instant?
    }

    private let box = Mutex(ContentBox())

    /// 以 ScreenCaptureKit 擷取單一視窗，直接輸出縮圖大小（由 GPU 縮放，省下 CPU 縮圖與記憶體）。
    /// - Parameters:
    ///   - windowID: 目標視窗
    ///   - maxPixelWidth: 輸出影像最大像素寬
    /// - Returns: 影像；無權限或視窗不存在時為 nil
    func capture(_ windowID: CGWindowID, maxPixelWidth: Int) -> CGImage? {
        guard let window = scWindow(windowID), window.frame.width > 0, window.frame.height > 0 else { return nil }
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let config = SCStreamConfiguration()
        let width = min(CGFloat(maxPixelWidth), window.frame.width * CGFloat(filter.pointPixelScale))
        config.width = max(1, Int(width))
        config.height = max(1, Int((width * window.frame.height / window.frame.width).rounded()))
        config.showsCursor = false
        config.ignoreShadowsSingleWindow = true

        let semaphore = DispatchSemaphore(value: 0)
        let result = Mutex<CGImage?>(nil)
        SCScreenshotManager.captureImage(contentFilter: filter, configuration: config) { image, _ in
            if let image { result.withLock { $0 = image } }
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + 0.5)
        return result.withLock { $0 }
    }

    /// 取得 SCWindow；SCShareableContent 查詢約 50ms，快取 2 秒，找不到才強制重抓。
    private func scWindow(_ windowID: CGWindowID) -> SCWindow? {
        let cached = box.withLock { box -> SCShareableContent? in
            guard let fetchedAt = box.fetchedAt, ContinuousClock.now - fetchedAt < .seconds(2) else { return nil }
            return box.content
        }
        if let window = cached?.windows.first(where: { $0.windowID == windowID }) { return window }

        let semaphore = DispatchSemaphore(value: 0)
        let fetched = Mutex<ContentBox>(ContentBox())
        SCShareableContent.getExcludingDesktopWindows(true, onScreenWindowsOnly: false) { content, _ in
            fetched.withLock { $0 = ContentBox(content: content, fetchedAt: .now) }
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + 1)
        let fresh = fetched.withLock { $0 }
        box.withLock { $0 = fresh }
        return fresh.content?.windows.first { $0.windowID == windowID }
    }
}
