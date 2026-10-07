//
//  WallpaperPresets.swift
//  Liftoff
//
//  內建背景：幾組漸層與純色，全部在執行時用 CoreGraphics 畫，不附圖檔（App 不變大、沒有授權問題）。
//  漸層平滑、沒有細節，畫在約螢幕 1/3 的解析度再由圖層放大就看不出差別，每螢幕約 1.5MB。
//  畫好的圖仍交給 `BackgroundRenderer` 做壓暗與平均亮度，和桌布走同一條路徑。
//

import CoreGraphics

/// 一組內建背景。
nonisolated struct WallpaperPreset: Identifiable, Sendable {
    /// 存進設定的識別字（不可更改，改了會讓使用者的選擇失效）
    let id: String
    /// sRGB 色碼（0xRRGGBB）；一個色碼為純色，多個為由左上到右下的漸層
    let colors: [UInt32]

    static let all: [WallpaperPreset] = [
        WallpaperPreset(id: "midnight", colors: [0x0F2027, 0x203A43, 0x2C5364]),
        WallpaperPreset(id: "aurora", colors: [0x134E5E, 0x71B280]),
        WallpaperPreset(id: "ocean", colors: [0x1A2980, 0x26D0CE]),
        WallpaperPreset(id: "grape", colors: [0x2F0743, 0x41295A, 0x8E54E9]),
        WallpaperPreset(id: "ember", colors: [0x3A1C71, 0xD76D77, 0xFFAF7B]),
        WallpaperPreset(id: "peach", colors: [0xFFD3A5, 0xFD6585]),
        WallpaperPreset(id: "graphite", colors: [0x1E1E20]),
        WallpaperPreset(id: "slate", colors: [0x34495E]),
        WallpaperPreset(id: "forest", colors: [0x1F3B2D]),
        WallpaperPreset(id: "sand", colors: [0xD8CBB5]),
    ]

    /// 預設選用的內建背景
    static let defaultID = "midnight"

    /// 依識別字找內建背景；找不到（例如之後移除了某組）時退回第一組。
    /// - Parameter id: 設定裡存的識別字
    /// - Returns: 對應的內建背景
    static func named(_ id: String) -> WallpaperPreset {
        all.first { $0.id == id } ?? all[0]
    }

    /// 畫成指定像素大小的不透明 sRGB 點陣圖。
    /// 漸層另外在左上角疊一層很淡的白色光暈，避免整面平塗看起來像未載入。
    /// - Parameters:
    ///   - width: 寬（像素）
    ///   - height: 高（像素）
    /// - Returns: 點陣圖；尺寸無效時為 nil
    func render(width: Int, height: Int) -> CGImage? {
        guard width > 0, height > 0, let srgb = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: srgb,
                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
              ) else { return nil }
        let cgColors = colors.map(Self.color)
        let w = CGFloat(width), h = CGFloat(height)
        if cgColors.count == 1 {
            context.setFillColor(cgColors[0])
            context.fill(CGRect(x: 0, y: 0, width: w, height: h))
            return context.makeImage()
        }
        guard let gradient = CGGradient(colorsSpace: srgb, colors: cgColors as CFArray, locations: nil) else { return nil }
        // CoreGraphics 原點在左下：從左上 (0, h) 畫到右下 (w, 0)
        context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: h), end: CGPoint(x: w, y: 0), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        let glow = [CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.12), CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0)]
        if let halo = CGGradient(colorsSpace: srgb, colors: glow as CFArray, locations: nil) {
            let center = CGPoint(x: w * 0.2, y: h * 0.85)
            context.drawRadialGradient(halo, startCenter: center, startRadius: 0, endCenter: center, endRadius: max(w, h) * 0.7, options: [])
        }
        return context.makeImage()
    }

    /// 0xRRGGBB → sRGB CGColor。
    private static func color(_ hex: UInt32) -> CGColor {
        CGColor(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: 1
        )
    }
}
