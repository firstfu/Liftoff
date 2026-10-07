//
//  WallpaperProvider.swift
//  Liftoff
//
//  啟動台背景：把桌布（或自選圖片）預先縮小、高斯模糊、壓暗，算好一張圖快取起來。
//  為什麼不用即時模糊：即時模糊要 WindowServer 每一幀對整個螢幕取樣合成；預算好的圖只是一張靜態貼圖，
//  顯示/翻頁時 GPU 幾乎不用做事。解析度依模糊程度決定：模糊得夠重時低解析度放大看不出差異（約螢幕 1/3 寬，
//  每螢幕約 1.5MB）；模糊調到幾乎為 0（清晰桌布）時才用螢幕原生解析度，代價是每螢幕 15–60MB。
//  自選圖片會複製一份到 App 自己的資料夾（`WallpaperLibrary`），使用者搬走或刪掉原圖也不會失效。
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
        /// 模糊程度 ×10：清晰門檻在 1pt，取整數會把 0.6（清晰）與 1.4（模糊）算成同一張
        let blur: Int
        let dim: Int
        let aspect: Int
        /// 螢幕倍率 ×100：解析度依倍率決定，Retina 切換 1x/2x 要重算
        let scale: Int
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
        let scale = screen.backingScaleFactor
        let blur = settings.blurRadius
        let dim = settings.dimming
        Task { [weak self] in
            let start = ContinuousClock.now
            let prepared = await Task.detached(priority: .userInitiated) {
                Self.render(url: url, screenSize: size, backingScale: scale, blurRadius: blur, dimming: dim)
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
            blur: Int((settings.blurRadius * 10).rounded()),
            dim: Int((settings.dimming * 100).rounded()),
            aspect: Int((screen.frame.width / max(screen.frame.height, 1) * 1000).rounded()),
            scale: Int((screen.backingScaleFactor * 100).rounded())
        )
        return (key, url)
    }

    // MARK: - 影像處理（背景執行緒）

    /// 模糊程度低於此值（螢幕點數）視為「清晰桌布」：不模糊、用螢幕原生解析度。
    nonisolated static let clearThreshold = 1.0
    /// 模糊路徑的像素上限：浮點緩衝每像素 24 bytes（RGB Float × 2 份），約 60MB 的暫時記憶體
    nonisolated static let maxBlurPixels = 2_500_000.0

    /// 決定背景圖每個螢幕點數要幾個像素。
    /// 模糊在縮圖上至少要有 1.5px 的 sigma，放大後才看不出像素格；比這更細的解析度只是浪費。
    /// - Parameters:
    ///   - screenSize: 螢幕點數大小
    ///   - backingScale: 螢幕倍率（Retina 為 2）
    ///   - blurRadius: 模糊程度（螢幕點數）
    /// - Returns: 每點像素數；清晰模式為螢幕倍率，重度模糊約 1/3（至少 480px 寬）
    nonisolated static func pixelsPerPoint(screenSize: CGSize, backingScale: Double, blurRadius: Double) -> Double {
        let width = max(screenSize.width, 1), area = max(screenSize.width * screenSize.height, 1)
        if blurRadius < clearThreshold { return backingScale }
        var p = min(max(1.5 / blurRadius, 1.0 / 3), backingScale)
        p = min(p, (maxBlurPixels / area).squareRoot())
        return max(p, min(480 / width, backingScale))
    }

    /// 讀圖 → 縮到目標解析度 → 依螢幕比例裁切 → 模糊（清晰模式略過）→ 壓暗 → 算平均亮度。
    /// - Parameters:
    ///   - url: 圖片檔
    ///   - screenSize: 螢幕點數大小
    ///   - backingScale: 螢幕倍率
    ///   - blurRadius: 模糊程度（螢幕點數）
    ///   - dimming: 壓暗程度 0…1
    /// - Returns: 算好的背景；檔案讀不到或不是圖片時為 nil
    nonisolated static func render(url: URL, screenSize: CGSize, backingScale: Double, blurRadius: Double, dimming: Double) -> PreparedBackground? {
        let isClear = blurRadius < clearThreshold
        let p = pixelsPerPoint(screenSize: screenSize, backingScale: backingScale, blurRadius: blurRadius)
        let target = CGSize(width: screenSize.width * p, height: screenSize.height * p)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceThumbnailMaxPixelSize: maxPixelSize(source: source, covering: target),
                  kCGImageSourceCreateThumbnailWithTransform: true,
              ] as CFDictionary),
              let output = BackgroundRenderer.render(
                  thumbnail: thumbnail, screenSize: screenSize, blurRadius: isClear ? 0 : blurRadius, dimming: dimming
              ) else { return nil }
        return PreparedBackground(image: output.image, luminance: output.luminance)
    }

    /// 縮圖的最長邊要多大，裁成螢幕比例後才剛好蓋滿目標像素（不放大原圖）。
    /// - Parameters:
    ///   - source: 圖片來源
    ///   - target: 目標像素大小
    /// - Returns: 給 `kCGImageSourceThumbnailMaxPixelSize` 的值
    nonisolated static func maxPixelSize(source: CGImageSource, covering target: CGSize) -> Double {
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        guard var width = (properties?[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue,
              var height = (properties?[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue,
              width > 0, height > 0 else {
            // 讀不到原圖尺寸：沿用舊估算（目標寬 × 1.3 足以涵蓋常見的 16:10 與 16:9 差異）
            return target.width * 1.3
        }
        // EXIF 方向 5–8 是轉 90°，縮圖套用方向後寬高互換
        if let orientation = (properties?[kCGImagePropertyOrientation] as? NSNumber)?.intValue, orientation >= 5 {
            swap(&width, &height)
        }
        let scale = min(max(target.width / width, target.height / height), 1)
        return (max(width, height) * scale).rounded(.up)
    }
}

/// 自選圖片的存放處：選圖時複製一份到 ~/Library/Application Support/Liftoff/Wallpapers/，
/// 設定只記這份副本的路徑。原圖搬走、刪掉或在外接硬碟上拔掉，背景都不受影響。
nonisolated enum WallpaperLibrary {
    static var folder: URL { Paths.ensure(Paths.support.appending(path: "Wallpapers", directoryHint: .isDirectory)) }

    /// 是否已是資料夾內的副本。
    /// - Parameter path: 圖片路徑
    /// - Returns: 在 `folder` 內為 true
    static func contains(_ path: String) -> Bool {
        URL(fileURLWithPath: path).standardizedFileURL.deletingLastPathComponent().path
            == folder.standardizedFileURL.path
    }

    /// 把圖片複製進資料夾（每次加不同前綴，同名圖也不會互相覆蓋，快取鍵與設定值都會變，背景一定重算）。
    /// - Parameter url: 原圖
    /// - Returns: 副本位置
    /// - Throws: 讀不到原圖、不是可解碼的圖片，或寫入失敗
    static func importImage(from url: URL) throws -> URL {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), CGImageSourceGetCount(source) > 0 else {
            throw CocoaError(.fileReadCorruptFile, userInfo: [NSFilePathErrorKey: url.path])
        }
        let destination = folder.appending(path: "\(UUID().uuidString.prefix(8))-\(url.lastPathComponent)")
        try FileManager.default.copyItem(at: url, to: destination)
        return destination
    }

    /// 給設定頁顯示的檔名：副本名稱是「8 碼前綴-原檔名」，去掉前綴還原成使用者認得的名字。
    /// - Parameter path: 圖片路徑（副本或舊版的原圖路徑）
    /// - Returns: 原檔名
    static func displayName(_ path: String) -> String {
        let name = (path as NSString).lastPathComponent
        guard contains(path), name.count > 9, name[name.index(name.startIndex, offsetBy: 8)] == "-" else { return name }
        return String(name.dropFirst(9))
    }

    /// 刪掉資料夾內除了目前使用中以外的副本（換圖後清掉舊的，避免越積越多）。
    /// - Parameter keeping: 目前使用中的路徑；nil 代表全部刪除
    static func removeUnused(keeping path: String?) {
        let keep = path.map { URL(fileURLWithPath: $0).standardizedFileURL.path }
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        for file in files where file.standardizedFileURL.path != keep {
            try? FileManager.default.removeItem(at: file)
        }
    }

    /// 舊版只記原圖路徑：原圖還在就複製一份並改指向副本（啟動時呼叫一次）。
    /// - Parameter settings: 使用者設定
    @MainActor static func adoptLegacyPath(in settings: AppSettings) {
        guard let path = settings.customImagePath, !contains(path),
              FileManager.default.fileExists(atPath: path) else { return }
        do {
            settings.customImagePath = try importImage(from: URL(fileURLWithPath: path)).path
            removeUnused(keeping: settings.customImagePath)
        } catch {
            Log.ui.error("自選背景圖複製失敗：\(error.localizedDescription, privacy: .public)")
        }
    }
}

extension NSScreen {
    /// 螢幕的 CGDirectDisplayID（跨次啟動不一定相同，只做執行期快取鍵）。
    var displayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }
}
