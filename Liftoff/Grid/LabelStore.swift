//
//  LabelStore.swift
//  Liftoff
//
//  App 名稱文字的預先渲染：在背景執行緒用 CoreText 把每個名稱（含陰影、中間截斷）畫成一張小點陣圖，
//  格線圖層直接貼圖。與 SwiftUI Text 相比，翻頁、搜尋、拖曳時完全不需要重新排版文字。
//

import AppKit
import CoreText
import Observation

/// 文字外觀（任何一項改變都要全部重畫）。
nonisolated struct LabelStyle: Hashable, Sendable {
    var fontSize: CGFloat
    var maxWidth: CGFloat
    var scale: CGFloat
}

@Observable
final class LabelStore {
    /// 每批渲染完成 +1（格線觀察它來換上新圖）
    private(set) var revision = 0

    @ObservationIgnored private var images: [Key: CGImage] = [:]
    @ObservationIgnored private var pending: Set<Key> = []
    @ObservationIgnored private var style: LabelStyle?
    @ObservationIgnored private var renderScheduled = false

    private struct Key: Hashable {
        let text: String
        let dark: Bool
    }

    /// 取得名稱圖；尚未渲染時回傳 nil 並排入背景渲染（完成後 revision 會變）。
    /// - Parameters:
    ///   - text: 名稱
    ///   - dark: 深色字（淺色背景用）或白字加陰影
    ///   - style: 字級、最大寬度、螢幕倍率
    func image(for text: String, dark: Bool, style: LabelStyle) -> CGImage? {
        if style != self.style {
            // 字級或格子寬度變了：舊圖全部作廢（渲染完成前先沿用舊圖會尺寸不對，寧可短暫空白）
            images.removeAll()
            pending.removeAll()
            self.style = style
        }
        let key = Key(text: text, dark: dark)
        if let image = images[key] { return image }
        if !pending.contains(key) {
            pending.insert(key)
            scheduleRender()
        }
        return nil
    }

    /// 丟掉指定文字的名稱圖（搜尋到的視窗標題：內容一直在變，留著只會讓快取無限增長）。
    /// - Parameter texts: 要丟掉的文字（深淺兩種都丟）
    func discard(_ texts: Set<String>) {
        guard !texts.isEmpty else { return }
        images = images.filter { !texts.contains($0.key.text) }
        pending = pending.filter { !texts.contains($0.text) }
    }

    /// 同一輪 run loop 內的請求合併成一批，在背景並行渲染。
    private func scheduleRender() {
        guard !renderScheduled else { return }
        renderScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self, let style = self.style else { return }
            self.renderScheduled = false
            let keys = Array(self.pending)
            guard !keys.isEmpty else { return }
            Task {
                let start = ContinuousClock.now
                let results = await Task.detached(priority: .userInitiated) {
                    LabelRenderer.renderBatch(keys.map { ($0.text, $0.dark) }, style: style)
                }.value
                // 渲染期間樣式若已改變，這批作廢
                guard self.style == style else { return }
                for (key, image) in zip(keys, results.images) {
                    self.pending.remove(key)
                    if let image { self.images[key] = image }
                }
                self.revision += 1
                Log.ui.debug("名稱渲染 \(keys.count) 個，\(milliseconds(since: start), format: .fixed(precision: 1))ms")
            }
        }
    }
}

nonisolated enum LabelRenderer {
    private struct FontBox: @unchecked Sendable {
        let font: CTFont
    }

    /// 可跨執行緒回傳的結果包裝（CGImage 建立後不可變）。
    struct Batch: @unchecked Sendable {
        let images: [CGImage?]
    }

    static func renderBatch(_ items: [(String, Bool)], style: LabelStyle) -> Batch {
        let results = UnsafeResultBuffer<CGImage>(count: items.count)
        // CTFont 不可變且執行緒安全，包一層讓並行閉包可以共用同一個字體物件
        let font = FontBox(font: labelFont(size: style.fontSize))
        DispatchQueue.concurrentPerform(iterations: items.count) { index in
            results[index] = render(items[index].0, dark: items[index].1, font: font.font, style: style)
        }
        return Batch(images: (0..<items.count).map { results[$0] })
    }

    /// 系統字體 Medium 字重（與 SwiftUI `.system(size:weight: .medium)` 相同）。
    static func labelFont(size: CGFloat) -> CTFont {
        let base = CTFontCreateUIFontForLanguage(.system, size, nil) ?? CTFontCreateWithName("Helvetica" as CFString, size, nil)
        let traits = [kCTFontWeightTrait: 0.23] as CFDictionary
        let descriptor = CTFontDescriptorCreateCopyWithAttributes(
            CTFontCopyFontDescriptor(base), [kCTFontTraitsAttribute: traits] as CFDictionary
        )
        return CTFontCreateWithFontDescriptor(descriptor, size, nil)
    }

    /// 把一行文字畫成點陣圖（超出寬度時中間以「…」截斷）。
    /// - Returns: 圖片（像素 = 點 × scale）；空字串時為 nil
    static func render(_ text: String, dark: Bool, font: CTFont, style: LabelStyle) -> CGImage? {
        guard !text.isEmpty else { return nil }
        let color = dark ? CGColor(gray: 0, alpha: 0.85) : CGColor(gray: 1, alpha: 1)
        let attributes: [CFString: Any] = [kCTFontAttributeName: font, kCTForegroundColorAttributeName: color]
        let attributed = CFAttributedStringCreate(nil, text as CFString, attributes as CFDictionary)!
        var line = CTLineCreateWithAttributedString(attributed)
        if CTLineGetTypographicBounds(line, nil, nil, nil) > style.maxWidth {
            let ellipsis = CTLineCreateWithAttributedString(CFAttributedStringCreate(nil, "…" as CFString, attributes as CFDictionary)!)
            line = CTLineCreateTruncatedLine(line, style.maxWidth, .middle, ellipsis) ?? line
        }
        var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
        let width = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, &leading))
        // 四周留 2pt 給陰影
        let pad: CGFloat = 2
        let size = CGSize(width: ceil(width) + pad * 2, height: ceil(ascent + descent) + pad * 2)
        let scale = style.scale
        guard let context = CGContext(
            data: nil, width: Int(size.width * scale), height: Int(size.height * scale), bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }
        context.scaleBy(x: scale, y: scale)
        context.setShouldSmoothFonts(false)
        if !dark {
            context.setShadow(offset: CGSize(width: 0, height: -0.5), blur: 1.5, color: CGColor(gray: 0, alpha: 0.5))
        }
        context.textPosition = CGPoint(x: pad, y: pad + descent)
        CTLineDraw(line, context)
        return context.makeImage()
    }
}
