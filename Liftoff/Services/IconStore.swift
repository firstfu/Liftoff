//
//  IconStore.swift
//  Liftoff
//
//  App 圖示的載入、快取與提供。效能策略：
//  1. 預先把圖示畫成「剛好顯示尺寸」的點陣 CGImage（已解碼），SwiftUI 繪製時零解碼、零縮放。
//  2. 兩層快取：記憶體（整個 App 生命週期）+ 磁碟 PNG（Caches，鍵含 App 路徑、更新時間、像素尺寸、明暗）。
//     系統圖示服務冷啟動時單張要 ~20ms，讀磁碟快取只要 ~0.3ms。
//  3. 多核並行渲染：`NSWorkspace.icon(forFile:)` 官方保證執行緒安全，每條執行緒各自畫進自己的 CGContext。
//  4. 每個 App 一個 @Observable 的 `IconImage`：圖示載入完成只會讓用到它的那一格重繪，而非整頁。
//

import AppKit
import ImageIO
import Observation
import UniformTypeIdentifiers

/// 單一 App 圖示的可觀察容器。
@Observable
final class IconImage {
    var cgImage: CGImage?
    init(_ cgImage: CGImage? = nil) { self.cgImage = cgImage }
}

final class IconStore {
    private var handles: [String: IconImage] = [:]
    /// 每個 App 目前圖示對應的快取鍵，用來判斷是否需要重新渲染
    private var loadedKeys: [String: String] = [:]
    private var loadTask: Task<Void, Never>?

    /// 目前渲染的像素尺寸（顯示點數 × 螢幕倍率）
    private(set) var pixelSize = 0
    private(set) var isDark = false

    /// 圖示還沒載入前的通用 App 圖示
    let placeholder: CGImage? = IconRenderer.render(
        image: NSWorkspace.shared.icon(for: .application), pixelSize: 128, dark: false
    )

    /// 取得某 App 的圖示容器（第一次呼叫時建立，內容可能稍後才載入）。
    func icon(for id: String) -> IconImage {
        if let handle = handles[id] { return handle }
        let handle = IconImage()
        handles[id] = handle
        return handle
    }

    /// 同步已安裝 App 的圖示：載入缺少或過期的圖示；尺寸或明暗變更時全部重畫（舊圖先頂著，畫好再換）。
    /// - Parameters:
    ///   - entries: 所有 App
    ///   - pixelSize: 目標像素尺寸
    ///   - dark: 是否使用深色版本圖示
    func sync(entries: [AppEntry], pixelSize: Int, dark: Bool) {
        self.pixelSize = pixelSize
        isDark = dark
        var jobs: [IconJob] = []
        for entry in entries {
            let key = IconRenderer.cacheKey(for: entry, pixelSize: pixelSize, dark: dark)
            if loadedKeys[entry.id] == key { continue }
            // 用解析後的實際路徑取圖示：符號連結（例如 /Applications/Safari.app）的圖示會帶捷徑箭頭
            jobs.append(IconJob(id: entry.id, path: entry.resolvedPath, key: key))
            _ = icon(for: entry.id)
        }
        guard !jobs.isEmpty else { return }

        loadTask?.cancel()
        loadTask = Task { [weak self] in
            let signpost = Log.signposter.beginInterval("IconLoad")
            let start = ContinuousClock.now
            var loaded = 0
            // 分批：第一批（通常是第一頁的量）越快出現越好，後續批次在背景陸續補上
            for batch in jobs.chunked(into: 48) {
                guard !Task.isCancelled else { break }
                let results = await Task.detached(priority: .userInitiated) {
                    IconRenderer.load(batch, pixelSize: pixelSize, dark: dark)
                }.value
                guard let self, !Task.isCancelled else { break }
                for (job, image) in zip(batch, results) {
                    guard let image else { continue }
                    self.icon(for: job.id).cgImage = image
                    self.loadedKeys[job.id] = job.key
                    loaded += 1
                }
            }
            Log.signposter.endInterval("IconLoad", signpost)
            Log.icons.info("圖示載入 \(loaded)/\(jobs.count) 張（\(pixelSize)px），\(milliseconds(since: start), format: .fixed(precision: 1))ms")
        }
    }

    /// 等待目前的載入工作完成（自我測試與首次顯示前使用）。
    func waitUntilLoaded() async {
        await loadTask?.value
    }

    /// 清除磁碟上已不再使用的圖示快取（例如 App 已刪除、尺寸改過）。
    func pruneDiskCache() {
        let valid = Set(loadedKeys.values)
        Task.detached(priority: .background) {
            let directory = Paths.iconCache
            guard let files = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else { return }
            for file in files where !valid.contains((file as NSString).deletingPathExtension) {
                try? FileManager.default.removeItem(at: directory.appending(path: file))
            }
        }
    }
}

/// 一個待載入的圖示。
nonisolated struct IconJob: Sendable {
    let id: String
    let path: String
    let key: String
}

/// 圖示渲染與磁碟快取（全部 nonisolated，可在任何執行緒呼叫）。
nonisolated enum IconRenderer {
    /// 快取鍵：App 路徑 + Info.plist 修改時間 + 像素尺寸 + 明暗，任何一項改變都視為不同圖。
    static func cacheKey(for entry: AppEntry, pixelSize: Int, dark: Bool) -> String {
        stableHash("\(entry.resolvedPath)|\(entry.modified.timeIntervalSinceReferenceDate)|\(pixelSize)|\(dark ? "d" : "l")|v2")
    }

    /// 並行載入一批圖示：先讀磁碟快取，沒有才向系統要圖示並渲染、寫回快取。
    static func load(_ jobs: [IconJob], pixelSize: Int, dark: Bool) -> [CGImage?] {
        let results = UnsafeResultBuffer<CGImage>(count: jobs.count)
        DispatchQueue.concurrentPerform(iterations: jobs.count) { index in
            let job = jobs[index]
            let file = Paths.iconCache.appending(path: job.key + ".png")
            if let cached = readPNG(file) {
                results[index] = cached
                return
            }
            let image = render(image: NSWorkspace.shared.icon(forFile: job.path), pixelSize: pixelSize, dark: dark)
            if let image {
                results[index] = image
                writePNG(image, to: file)
            }
        }
        return (0..<jobs.count).map { results[$0] }
    }

    /// 把 NSImage 畫成指定像素尺寸的已解碼點陣圖（Display P3、premultiplied BGRA，GPU 可直接上傳）。
    static func render(image: NSImage, pixelSize: Int, dark: Bool) -> CGImage? {
        guard pixelSize > 0,
              let space = CGColorSpace(name: CGColorSpace.displayP3),
              let context = CGContext(
                  data: nil, width: pixelSize, height: pixelSize, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
              ) else { return nil }
        context.interpolationQuality = .high
        let draw = {
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
            image.draw(in: NSRect(x: 0, y: 0, width: pixelSize, height: pixelSize), from: .zero, operation: .copy, fraction: 1)
            NSGraphicsContext.restoreGraphicsState()
        }
        // 部分系統圖示（macOS 26 起的 .icon 格式）依繪製時的外觀輸出淺色或深色版本
        NSAppearance(named: dark ? .darkAqua : .aqua)?.performAsCurrentDrawingAppearance(draw)
        return context.makeImage()
    }

    /// 讀取 PNG 並立即解碼（避免把解碼成本留到主執行緒第一次繪製時）。
    static func readPNG(_ url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options = [kCGImageSourceShouldCacheImmediately: true] as CFDictionary
        return CGImageSourceCreateImageAtIndex(source, 0, options)
    }

    static func writePNG(_ image: CGImage, to url: URL) {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationFinalize(destination)
    }
}

extension Array {
    /// 切成固定大小的區塊（最後一塊可能較小）。
    nonisolated func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        return stride(from: 0, to: count, by: size).map { Array(self[$0..<Swift.min($0 + size, count)]) }
    }
}
