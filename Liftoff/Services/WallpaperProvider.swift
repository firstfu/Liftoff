//
//  WallpaperProvider.swift
//  Liftoff
//
//  啟動台背景：把桌布（或自選圖片）預先縮小、高斯模糊、壓暗，算好一張小圖快取起來。
//  為什麼不用即時模糊：即時模糊要 WindowServer 每一幀對整個螢幕取樣合成；預算好的圖只是一張靜態貼圖，
//  顯示/翻頁時 GPU 幾乎不用做事。模糊後的圖在低解析度下放大看不出差異，所以只算螢幕 1/4 大小。
//  同時計算平均亮度，讓 App 名稱自動選擇黑字或白字。影像處理本身在 `BackgroundRenderer`（CPU，不用 Core Image）。
//

import AppKit

/// 算好的背景。
nonisolated struct PreparedBackground: @unchecked Sendable {
    let image: CGImage
    /// 平均亮度（0 黑 – 1 白），決定文字顏色
    let luminance: Double
}

final class WallpaperProvider {
    private struct CacheKey: Hashable {
        let displayID: CGDirectDisplayID
        let source: String
        let blur: Int
        let dim: Int
        let aspect: Int
    }

    private var cache: [CacheKey: PreparedBackground] = [:]
    /// 計算中的背景 → 等待它完成的回呼（同一張圖可能同時被預熱與顯示要求）
    private var inFlight: [CacheKey: [@MainActor (PreparedBackground) -> Void]] = [:]

    /// 立即回傳快取中的背景；沒有或來源已變時回傳 nil，並在背景開始計算（完成後呼叫 `onReady`）。
    /// - Parameters:
    ///   - screen: 目標螢幕
    ///   - settings: 使用者設定（背景樣式、模糊、壓暗、自選圖片）
    ///   - onReady: 背景算好時在主執行緒呼叫
    /// - Returns: 可立即使用的背景；即時模糊樣式或無法取得圖片時為 nil
    func background(
        for screen: NSScreen, settings: AppSettings, onReady: @escaping @MainActor (PreparedBackground) -> Void
    ) -> PreparedBackground? {
        guard let (key, url) = cacheKey(for: screen, settings: settings) else { return nil }
        if let cached = cache[key] { return cached }
        if inFlight[key] != nil {
            inFlight[key]?.append(onReady)
            return nil
        }
        inFlight[key] = [onReady]

        let size = screen.frame.size
        let blur = settings.blurRadius
        let dim = settings.dimming
        Task { [weak self] in
            let start = ContinuousClock.now
            let prepared = await Task.detached(priority: .userInitiated) {
                Self.render(url: url, screenSize: size, blurRadius: blur, dimming: dim)
            }.value
            guard let self else { return }
            let waiters = self.inFlight.removeValue(forKey: key) ?? []
            guard let prepared else {
                Log.ui.error("背景圖產生失敗：\(url.path, privacy: .public)")
                return
            }
            // 同一螢幕只留最新的一張，避免換桌布後舊圖一直占記憶體
            self.cache = self.cache.filter { $0.key.displayID != key.displayID }
            self.cache[key] = prepared
            Log.ui.info("背景圖完成 \(prepared.image.width)×\(prepared.image.height)，\(milliseconds(since: start), format: .fixed(precision: 1))ms")
            waiters.forEach { $0(prepared) }
        }
        return nil
    }

    /// 預先為所有螢幕算好背景（啟動時、換桌布後呼叫），第一次打開就不必等。
    func prewarm(settings: AppSettings) {
        for screen in NSScreen.screens {
            _ = background(for: screen, settings: settings) { _ in }
        }
    }

    func invalidate() {
        cache.removeAll()
    }

    /// 等待指定螢幕的背景算好（最多 timeout）；即時模糊樣式或沒有桌布時立即返回。
    func waitUntilReady(for screen: NSScreen, settings: AppSettings, timeout: Duration) async {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            guard let (key, _) = cacheKey(for: screen, settings: settings), cache[key] == nil else { return }
            try? await Task.sleep(for: .milliseconds(15))
        }
    }

    private func cacheKey(for screen: NSScreen, settings: AppSettings) -> (CacheKey, URL)? {
        let url: URL?
        switch settings.backgroundStyle {
        case .liveBlur: return nil
        case .wallpaper: url = NSWorkspace.shared.desktopImageURL(for: screen)
        case .customImage: url = settings.customImagePath.map { URL(fileURLWithPath: $0) }
        }
        guard let url, !url.hasDirectoryPath else { return nil }
        let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)?
            .timeIntervalSinceReferenceDate ?? 0
        let key = CacheKey(
            displayID: screen.displayID,
            source: "\(url.path)|\(modified)",
            blur: Int(settings.blurRadius.rounded()),
            dim: Int((settings.dimming * 100).rounded()),
            aspect: Int((screen.frame.width / max(screen.frame.height, 1) * 1000).rounded())
        )
        return (key, url)
    }

    // MARK: - 影像處理（背景執行緒）

    /// 縮圖 → 依螢幕比例裁切 → 模糊 → 壓暗 → 算平均亮度。
    nonisolated static func render(url: URL, screenSize: CGSize, blurRadius: Double, dimming: Double) -> PreparedBackground? {
        // 只取約 1/3 螢幕寬的縮圖（至少 480px）：模糊後看不出差別，運算量與記憶體少約 9 倍
        let targetWidth = max(480, screenSize.width / 3)
        let maxPixel = targetWidth * 1.3
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceThumbnailMaxPixelSize: maxPixel,
                  kCGImageSourceCreateThumbnailWithTransform: true,
              ] as CFDictionary),
              let output = BackgroundRenderer.render(
                  thumbnail: thumbnail, screenSize: screenSize, blurRadius: blurRadius, dimming: dimming
              ) else { return nil }
        return PreparedBackground(image: output.image, luminance: output.luminance)
    }
}

extension NSScreen {
    /// 螢幕的 CGDirectDisplayID（跨次啟動不一定相同，只做執行期快取鍵）。
    var displayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }
}
