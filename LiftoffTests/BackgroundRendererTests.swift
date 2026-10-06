//
//  BackgroundRendererTests.swift
//  LiftoffTests
//
//  背景圖處理（CPU 版，取代原本的 Core Image）：裁切比例、box blur 寬度、模糊在線性光進行、
//  壓暗與平均亮度、sRGB 編碼查表的精度。與舊 Core Image 版的逐像素比對另見 docs/context/journal/process.md。
//

import CoreGraphics
import Testing
@testable import Liftoff

struct BackgroundRendererTests {
    /// 以函式產生 sRGB 不透明測試圖（回傳每個像素的 8 位元灰階值）。
    private func image(width: Int, height: Int, gray: (Int, Int) -> UInt8) -> CGImage {
        var bytes = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let v = gray(x, y), i = (y * width + x) * 4
                bytes[i] = v; bytes[i + 1] = v; bytes[i + 2] = v
            }
        }
        let context = CGContext(
            data: &bytes, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        )!
        return context.makeImage()!
    }

    /// 讀回輸出圖的 R 通道（灰階圖三通道相同）。
    private func reds(_ image: CGImage) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let context = CGContext(
            data: &bytes, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        )!
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return stride(from: 0, to: bytes.count, by: 4).map { bytes[$0] }
    }

    @Test func centerCropMatchesScreenAspect() {
        // 16:10 桌布放到 16:9 螢幕：上下各裁 80px
        #expect(BackgroundRenderer.centerCrop(width: 2560, height: 1600, aspect: 16.0 / 9) == CGRect(x: 0, y: 80, width: 2560, height: 1440))
        // 超寬桌布放到 16:10：左右裁
        #expect(BackgroundRenderer.centerCrop(width: 3200, height: 1000, aspect: 1.6) == CGRect(x: 800, y: 0, width: 1600, height: 1000))
        #expect(BackgroundRenderer.centerCrop(width: 0, height: 100, aspect: 1) == .zero)
    }

    /// 三次 box 的總變異數要等於 sigma²（box 寬 w 的變異數為 (w²−1)/12），模糊程度才與高斯一致。
    /// 已知限制：box 寬只能是奇數整數，sigma 很小時逼近較粗（sigma 2 約差 17%，對應設定約 4–5pt 的極輕模糊）；
    /// 預設 45pt 在 1920 寬螢幕上 sigma 約 19.5，誤差 < 2%。
    @Test(arguments: [(2.0, 0.2), (5.0, 0.08), (15.0, 0.03), (19.5, 0.02), (33.75, 0.02), (60.0, 0.02)])
    func boxSizesMatchGaussianVariance(sigma: Double, tolerance: Double) {
        let sizes = BackgroundRenderer.boxSizes(sigma: sigma, passes: 3)
        #expect(sizes.count == 3)
        #expect(sizes.allSatisfy { $0 % 2 == 1 })
        let variance = sizes.reduce(0.0) { $0 + Double($1 * $1 - 1) / 12 }
        #expect(abs(variance - sigma * sigma) / (sigma * sigma) < tolerance)
    }

    @Test func uniformImageStaysUniformAndDimsInLinearLight() {
        let source = image(width: 120, height: 80) { _, _ in 200 }
        let output = BackgroundRenderer.render(thumbnail: source, screenSize: CGSize(width: 1200, height: 800), blurRadius: 45, dimming: 0.5)!
        let values = Set(reds(output.image))
        // 線性光：200 → 0.5776，乘 0.5 → 0.2888 → sRGB 146.3 → 146（若誤在 gamma 空間壓暗會是 100）
        #expect(values == [146])
        #expect(abs(output.luminance - 146.0 / 255) < 0.001)
    }

    /// 黑白交界模糊後：單調遞增、左右對稱，交界處是線性光 50% 灰（sRGB 約 188，gamma 空間模糊會是 128）。
    @Test func blurIsInLinearLightAndSymmetric() {
        let width = 200
        let source = image(width: width, height: 20) { x, _ in x < width / 2 ? 0 : 255 }
        let output = BackgroundRenderer.render(thumbnail: source, screenSize: CGSize(width: 2000, height: 200), blurRadius: 100, dimming: 0)!
        let row = Array(reds(output.image).prefix(width))
        #expect(zip(row, row.dropFirst()).allSatisfy { $0 <= $1 })
        #expect(row.first! < 10 && row.last! > 245)
        let middle = (Int(row[width / 2 - 1]) + Int(row[width / 2])) / 2
        #expect(abs(middle - 188) <= 3)
    }

    /// 舊 Core Image 版在裁切範圍不是整數像素時（例如 14 吋 Retina 1512×982 配 16:10 桌布），
    /// 邊緣像素半透明、模糊後整圈變暗（實測右下角亮度 26 vs 45）。新版必須整張不透明、邊緣不變暗。
    @Test func fractionalCropHasNoDarkEdges() {
        let source = image(width: 655, height: 409) { _, _ in 120 }
        let output = BackgroundRenderer.render(thumbnail: source, screenSize: CGSize(width: 1512, height: 982), blurRadius: 45, dimming: 0)!
        #expect(output.image.alphaInfo == .noneSkipLast)
        #expect(Set(reds(output.image)) == [120])
    }

    @Test func noBlurKeepsPixels() {
        let source = image(width: 64, height: 36) { x, y in UInt8((x * 3 + y * 5) % 256) }
        let output = BackgroundRenderer.render(thumbnail: source, screenSize: CGSize(width: 640, height: 360), blurRadius: 0, dimming: 0)!
        #expect(reds(output.image) == reds(source))
    }

    @Test func luminanceExtremes() {
        let black = BackgroundRenderer.render(thumbnail: image(width: 32, height: 18) { _, _ in 0 }, screenSize: CGSize(width: 320, height: 180), blurRadius: 10, dimming: 0)!
        let white = BackgroundRenderer.render(thumbnail: image(width: 32, height: 18) { _, _ in 255 }, screenSize: CGSize(width: 320, height: 180), blurRadius: 10, dimming: 0)!
        #expect(abs(black.luminance) < 1e-9)
        #expect(abs(white.luminance - 1) < 1e-9)
    }

    /// 查表編碼與精確公式最多差 1 個色階（只在四捨五入的邊界），兩端完全一致。
    @Test func encodeTableMatchesExactFormula() {
        var worst = 0
        for i in 0...20_000 {
            let linear = Float(i) / 20_000
            worst = max(worst, abs(Int(BackgroundRenderer.encode(linear)) - Int(BackgroundRenderer.exactEncode(linear))))
        }
        #expect(worst <= 1)
        #expect(BackgroundRenderer.encode(0) == 0 && BackgroundRenderer.encode(1) == 255)
        #expect(BackgroundRenderer.encode(-1) == 0 && BackgroundRenderer.encode(2) == 255)
    }
}
