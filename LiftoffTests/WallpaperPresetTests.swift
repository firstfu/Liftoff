//
//  WallpaperPresetTests.swift
//  LiftoffTests
//
//  內建背景：識別字穩定且不重複、純色與漸層畫得出來、亮度判斷符合預期（淺色背景要換黑字）。
//

import CoreGraphics
import Foundation
import Testing
@testable import Liftoff

struct WallpaperPresetTests {
    /// 讀回指定像素的 RGB。
    private func pixel(_ image: CGImage, x: Int, y: Int) -> (Int, Int, Int) {
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let context = CGContext(
            data: &bytes, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        )!
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        // 點陣第 0 列是圖的最上方
        let i = (y * image.width + x) * 4
        return (Int(bytes[i]), Int(bytes[i + 1]), Int(bytes[i + 2]))
    }

    @Test func idsAreUniqueAndDefaultExists() {
        let ids = WallpaperPreset.all.map(\.id)
        #expect(Set(ids).count == ids.count)
        #expect(ids.contains(WallpaperPreset.defaultID))
        #expect(WallpaperPreset.named("不存在").id == WallpaperPreset.all[0].id)
    }

    @Test func solidPresetIsUniform() {
        let graphite = WallpaperPreset.named("graphite").render(width: 40, height: 24)!
        #expect(pixel(graphite, x: 0, y: 0) == (0x1E, 0x1E, 0x20))
        #expect(pixel(graphite, x: 39, y: 23) == (0x1E, 0x1E, 0x20))
    }

    /// 漸層由左上往右下：midnight 左上偏暗、右下偏亮。
    @Test func gradientRunsTopLeftToBottomRight() {
        let image = WallpaperPreset.named("midnight").render(width: 120, height: 80)!
        let topLeft = pixel(image, x: 2, y: 2), bottomRight = pixel(image, x: 117, y: 77)
        #expect(topLeft.2 < bottomRight.2)
    }

    @Test func everyPresetRendersAtScreenAspect() {
        for preset in WallpaperPreset.all {
            let prepared = WallpaperProvider.render(preset: preset, screenSize: CGSize(width: 1512, height: 982), backingScale: 2, dimming: 0)
            #expect(prepared != nil, "\(preset.id)")
            guard let prepared else { continue }
            #expect(abs(Double(prepared.image.width) / Double(prepared.image.height) - 1512.0 / 982) < 0.01)
            #expect(prepared.image.width <= 1512)
        }
    }

    /// 文字顏色門檻是 0.62：sand、peach 要判為淺色（黑字），深色系判為深色（白字）。
    @Test func luminanceDecidesLabelColor() {
        func luminance(_ id: String) -> Double {
            WallpaperProvider.render(preset: .named(id), screenSize: CGSize(width: 1440, height: 900), backingScale: 1, dimming: 0)!.luminance
        }
        #expect(luminance("sand") > 0.62)
        #expect(luminance("midnight") < 0.62)
        #expect(luminance("graphite") < 0.62)
    }
}
