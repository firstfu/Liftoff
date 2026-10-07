//
//  BackgroundRenderer.swift
//  Liftoff
//
//  啟動台背景圖的影像處理：依螢幕比例裁切 → 線性光高斯模糊 → 壓暗 → 算平均亮度，全部在 CPU 上做。
//  為什麼不用 Core Image：整個 App 只為了這一張約 640×360 的小圖，Core Image 卻要常駐 Metal 裝置、
//  核心函式庫與 Metal 的二進位快取資料庫（實測約 3MB 的 LMDB 加上 CoreImage 3MB），閒置時一直佔著記憶體。
//  這裡的運算量很小（三次 box blur 與模糊半徑無關，O(像素數)），CPU 幾毫秒就做完。
//  語意比照原本的 Core Image 版本：在線性光空間模糊（亮部不會被暗部吃掉）、邊緣延伸（等同 clampedToExtent）、
//  壓暗等同黑色以 dimming 透明度疊在上面、平均亮度取線性光平均色再換回 sRGB 計算。
//  不模糊（清晰桌布）時圖是螢幕原生解析度，改走 8 位元查表的路徑，不配置浮點緩衝。
//  純函式、可在任何執行緒呼叫，方便單元測試。
//

import CoreGraphics
import Foundation

nonisolated enum BackgroundRenderer {
    /// 處理後的結果。
    struct Output {
        let image: CGImage
        /// 平均亮度（0 黑 – 1 白）
        let luminance: Double
    }

    /// 把縮圖處理成背景圖。
    /// - Parameters:
    ///   - thumbnail: 來源縮圖（已縮到目標大小附近）
    ///   - screenSize: 螢幕點數大小（決定裁切比例與模糊半徑換算）
    ///   - blurRadius: 模糊程度，以螢幕點數為單位（高斯 sigma）
    ///   - dimming: 壓暗程度 0…1
    /// - Returns: 不透明的 sRGB 點陣圖與平均亮度；尺寸無效或無法建立點陣時為 nil
    static func render(thumbnail: CGImage, screenSize: CGSize, blurRadius: Double, dimming: Double) -> Output? {
        // 依螢幕長寬比置中裁切（等同桌布的「填滿螢幕」）
        let crop = centerCrop(width: thumbnail.width, height: thumbnail.height, aspect: screenSize.width / max(screenSize.height, 1))
        guard crop.width > 0, crop.height > 0, let cropped = thumbnail.cropping(to: crop) else { return nil }
        let width = cropped.width, height = cropped.height
        guard let srgb = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: srgb,
                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
              ),
              let bytes = context.data?.assumingMemoryBound(to: UInt8.self) else { return nil }
        // 畫進 sRGB 點陣：來源若是 Display P3 等其他色域，由 CoreGraphics 一次轉好
        context.draw(cropped, in: CGRect(x: 0, y: 0, width: width, height: height))

        let count = width * height
        // 壓暗：黑色以 dimming 透明度疊上去，在線性光下等於乘上 (1 - dimming)
        let keep = Float(1 - min(max(dimming, 0), 1))
        // 模糊半徑以「螢幕點數」為單位設定，換算到縮圖像素
        let sigma = blurRadius * Double(width) / max(screenSize.width, 1)
        guard sigma > 0.5 else {
            // 不模糊（清晰桌布）：圖可能是螢幕原生解析度（5K 約 1,470 萬像素），
            // 浮點緩衝要 3 倍 Float × 2 份，直接在 8 位元上查表處理，結果與浮點路徑相同
            return dimInPlace(bytes, count: count, keep: keep, context: context)
        }

        var pixels = [Float](repeating: 0, count: count * 3)
        let decode = linearTable
        for i in 0..<count {
            pixels[i * 3] = decode[Int(bytes[i * 4])]
            pixels[i * 3 + 1] = decode[Int(bytes[i * 4 + 1])]
            pixels[i * 3 + 2] = decode[Int(bytes[i * 4 + 2])]
        }

        gaussianBlur(&pixels, width: width, height: height, sigma: sigma)

        var sum: (Double, Double, Double) = (0, 0, 0)
        for i in 0..<count {
            let r = pixels[i * 3] * keep, g = pixels[i * 3 + 1] * keep, b = pixels[i * 3 + 2] * keep
            sum.0 += Double(r); sum.1 += Double(g); sum.2 += Double(b)
            bytes[i * 4] = encode(r)
            bytes[i * 4 + 1] = encode(g)
            bytes[i * 4 + 2] = encode(b)
            bytes[i * 4 + 3] = 255
        }
        guard let image = context.makeImage() else { return nil }
        return Output(image: image, luminance: luminance(linearSum: sum, count: count))
    }

    /// 不模糊時的壓暗：每個 8 位元值的結果只有 256 種，先算成表再逐位元組替換；
    /// 平均亮度改用直方圖累計，不必逐像素做浮點加總。
    /// - Parameters:
    ///   - bytes: RGBX 點陣（就地修改）
    ///   - count: 像素數
    ///   - keep: 線性光保留比例（1 − dimming）
    ///   - context: 擁有 `bytes` 的點陣 context
    /// - Returns: 處理後的圖與平均亮度；無法產生圖時為 nil
    private static func dimInPlace(_ bytes: UnsafeMutablePointer<UInt8>, count: Int, keep: Float, context: CGContext) -> Output? {
        let decode = linearTable
        let dimmed = decode.map { $0 * keep }
        let table = dimmed.map { encode($0) }
        // 三個通道的直方圖放在同一個陣列：[R 0…255, G 0…255, B 0…255]
        var histogram = [Int](repeating: 0, count: 768)
        histogram.withUnsafeMutableBufferPointer { h in
            table.withUnsafeBufferPointer { t in
                for i in 0..<count {
                    let o = i * 4
                    let r = Int(bytes[o]), g = Int(bytes[o + 1]), b = Int(bytes[o + 2])
                    h[r] += 1; h[256 + g] += 1; h[512 + b] += 1
                    bytes[o] = t[r]; bytes[o + 1] = t[g]; bytes[o + 2] = t[b]
                    bytes[o + 3] = 255
                }
            }
        }
        guard let image = context.makeImage() else { return nil }
        func channelSum(_ offset: Int) -> Double {
            (0..<256).reduce(0) { $0 + Double(histogram[offset + $1]) * Double(dimmed[$1]) }
        }
        let sum = (channelSum(0), channelSum(256), channelSum(512))
        return Output(image: image, luminance: luminance(linearSum: sum, count: count))
    }

    /// 平均色在線性光下取平均，再換回 sRGB 以 Rec.709 權重算亮度（與文字顏色判斷的門檻一致）。
    /// - Parameters:
    ///   - linearSum: 各通道線性光總和
    ///   - count: 像素數
    /// - Returns: 平均亮度 0…1
    private static func luminance(linearSum sum: (Double, Double, Double), count: Int) -> Double {
        let n = Double(max(count, 1))
        return (0.2126 * Double(encode(Float(sum.0 / n)))
            + 0.7152 * Double(encode(Float(sum.1 / n)))
            + 0.0722 * Double(encode(Float(sum.2 / n)))) / 255
    }

    /// 依目標長寬比計算置中裁切範圍（像素、取整）。
    /// - Parameters:
    ///   - width: 來源寬
    ///   - height: 來源高
    ///   - aspect: 目標寬高比
    /// - Returns: 裁切範圍
    static func centerCrop(width: Int, height: Int, aspect: Double) -> CGRect {
        let w = Double(width), h = Double(height)
        guard w > 0, h > 0, aspect > 0 else { return .zero }
        if w / h > aspect {
            let cropWidth = (h * aspect).rounded()
            return CGRect(x: ((w - cropWidth) / 2).rounded(.down), y: 0, width: cropWidth, height: h)
        } else {
            let cropHeight = (w / aspect).rounded()
            return CGRect(x: 0, y: ((h - cropHeight) / 2).rounded(.down), width: w, height: cropHeight)
        }
    }

    // MARK: - 色彩轉換

    /// sRGB 8 位元 → 線性光（查表）
    private static let linearTable: [Float] = (0..<256).map { value in
        let c = Float(value) / 255
        return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
    }

    /// 線性光 → sRGB 8 位元的查表解析度。每像素 3 次 pow 是整個處理最貴的一步；
    /// 65536 格時最暗處（斜率最大 12.92）的誤差約 0.05 個色階，與直接計算無法分辨
    private static let encodeSteps = 65535
    private static let encodeTable: [UInt8] = (0...encodeSteps).map { exactEncode(Float($0) / Float(encodeSteps)) }

    /// 線性光 → sRGB 8 位元（查表；超出範圍時截斷）。
    static func encode(_ linear: Float) -> UInt8 {
        let l = min(max(linear, 0), 1)
        return encodeTable[Int(l * Float(encodeSteps) + 0.5)]
    }

    /// 線性光 → sRGB 8 位元的精確公式（四捨五入）。
    static func exactEncode(_ linear: Float) -> UInt8 {
        let l = min(max(linear, 0), 1)
        let s = l <= 0.0031308 ? 12.92 * l : 1.055 * pow(l, 1 / 2.4) - 0.055
        return UInt8((s * 255).rounded())
    }

    // MARK: - 模糊

    /// 以三次 box blur 近似高斯模糊（中央極限定理；三次即與真高斯幾乎無法分辨）。
    /// 每次 box blur 以滑動視窗累加，成本與半徑無關。邊緣以最近的像素延伸。
    /// - Parameters:
    ///   - pixels: 交錯排列的 RGB 浮點像素（就地修改）
    ///   - width: 寬（像素）
    ///   - height: 高（像素）
    ///   - sigma: 高斯標準差（像素）
    static func gaussianBlur(_ pixels: inout [Float], width: Int, height: Int, sigma: Double) {
        var scratch = [Float](repeating: 0, count: pixels.count)
        pixels.withUnsafeMutableBufferPointer { a in
            scratch.withUnsafeMutableBufferPointer { b in
                for size in boxSizes(sigma: sigma, passes: 3) {
                    let radius = (size - 1) / 2
                    guard radius > 0 else { continue }
                    // 水平：a → b；垂直：b → a（結果回到 pixels）
                    horizontalPass(from: a, to: b, width: width, height: height, radius: radius)
                    verticalPass(from: b, to: a, width: width, height: height, radius: radius)
                }
            }
        }
    }

    /// 讓 n 次 box blur 的總變異數等於 sigma² 的各次寬度（皆為奇數）。
    /// 做法：取最接近理想寬度的兩個奇數 wl、wl+2，決定各用幾次（Kovesi, "Fast Almost-Gaussian Filtering"）。
    /// - Parameters:
    ///   - sigma: 高斯標準差
    ///   - passes: 次數
    /// - Returns: 每次 box 的寬度
    static func boxSizes(sigma: Double, passes: Int) -> [Int] {
        let ideal = (12 * sigma * sigma / Double(passes) + 1).squareRoot()
        var lower = Int(ideal.rounded(.down))
        if lower % 2 == 0 { lower -= 1 }
        lower = max(lower, 1)
        let upper = lower + 2
        let n = Double(passes), wl = Double(lower)
        let lowerCount = Int(((12 * sigma * sigma - n * wl * wl - 4 * n * wl - 3 * n) / (-4 * wl - 4)).rounded())
        return (0..<passes).map { $0 < lowerCount ? lower : upper }
    }

    /// 水平方向一次 box blur：逐列處理，三個通道一起累加（記憶體連續存取）。
    private static func horizontalPass(
        from source: UnsafeMutableBufferPointer<Float>, to destination: UnsafeMutableBufferPointer<Float>,
        width: Int, height: Int, radius: Int
    ) {
        let scale = 1 / Float(2 * radius + 1)
        let last = width - 1
        for y in 0..<height {
            let row = y * width * 3
            // 視窗初值：以邊緣像素延伸填滿 [-radius, radius]
            var r: Float = 0, g: Float = 0, b: Float = 0
            for k in -radius...radius {
                let i = row + min(max(k, 0), last) * 3
                r += source[i]; g += source[i + 1]; b += source[i + 2]
            }
            for x in 0..<width {
                let o = row + x * 3
                destination[o] = r * scale; destination[o + 1] = g * scale; destination[o + 2] = b * scale
                let add = row + min(x + radius + 1, last) * 3
                let remove = row + max(x - radius, 0) * 3
                r += source[add] - source[remove]
                g += source[add + 1] - source[remove + 1]
                b += source[add + 2] - source[remove + 2]
            }
        }
    }

    /// 垂直方向一次 box blur：不逐行跳著讀，而是整列一起往下滑——每欄一個累加值，
    /// 每往下一列就加入新進視窗的那列、扣掉離開的那列，全程循序存取（跨列讀取對快取很不友善）。
    private static func verticalPass(
        from source: UnsafeMutableBufferPointer<Float>, to destination: UnsafeMutableBufferPointer<Float>,
        width: Int, height: Int, radius: Int
    ) {
        let scale = 1 / Float(2 * radius + 1)
        let last = height - 1
        let rowLength = width * 3
        var acc = [Float](repeating: 0, count: rowLength)
        acc.withUnsafeMutableBufferPointer { acc in
            for k in -radius...radius {
                let row = min(max(k, 0), last) * rowLength
                for i in 0..<rowLength { acc[i] += source[row + i] }
            }
            for y in 0..<height {
                let out = y * rowLength
                let add = min(y + radius + 1, last) * rowLength
                let remove = max(y - radius, 0) * rowLength
                for i in 0..<rowLength {
                    destination[out + i] = acc[i] * scale
                    acc[i] += source[add + i] - source[remove + i]
                }
            }
        }
    }
}
