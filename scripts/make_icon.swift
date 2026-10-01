// make_icon.swift：以 CoreGraphics 繪製 Liftoff App 圖示（1024px）：深色漸層圓角方塊上排列 3×3 彩色圖示格，
// 呼應經典啟動台「一眼看完所有 App」的意象。
// 用法：swift scripts/make_icon.swift <輸出 png 路徑>
import AppKit

let size: CGFloat = 1024
let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
    // macOS 圖示網格：824pt 圓角方塊置中，四周留 100pt
    let tile = rect.insetBy(dx: 100, dy: 100)
    let squircle = NSBezierPath(roundedRect: tile, xRadius: 185, yRadius: 185)
    NSGraphicsContext.saveGraphicsState()
    squircle.addClip()
    NSGradient(colors: [
        NSColor(red: 0.10, green: 0.12, blue: 0.30, alpha: 1),
        NSColor(red: 0.27, green: 0.16, blue: 0.52, alpha: 1),
        NSColor(red: 0.12, green: 0.38, blue: 0.75, alpha: 1),
    ])!.draw(in: tile, angle: -65)
    // 左上柔光（放射漸層，邊緣完全透明，不會出現硬邊）
    let cg = NSGraphicsContext.current!.cgContext
    let glow = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                          colors: [NSColor.white.withAlphaComponent(0.20).cgColor, NSColor.white.withAlphaComponent(0).cgColor] as CFArray,
                          locations: [0, 1])!
    cg.drawRadialGradient(glow, startCenter: CGPoint(x: tile.minX + 120, y: tile.maxY - 80), startRadius: 0,
                          endCenter: CGPoint(x: tile.minX + 120, y: tile.maxY - 80), endRadius: 620, options: [])
    NSGraphicsContext.restoreGraphicsState()

    // 3×3 圖示格
    let colors: [(NSColor, NSColor)] = [
        (.systemPink, .systemOrange), (.systemYellow, .systemOrange), (.systemGreen, .systemTeal),
        (.systemTeal, .systemBlue), (.white, NSColor(white: 0.85, alpha: 1)), (.systemPurple, .systemPink),
        (.systemBlue, .systemIndigo), (.systemOrange, .systemRed), (.systemMint, .systemGreen),
    ]
    let cell: CGFloat = 170, gap: CGFloat = 52
    let gridSize = cell * 3 + gap * 2
    let origin = CGPoint(x: rect.midX - gridSize / 2, y: rect.midY - gridSize / 2)
    for row in 0..<3 {
        for col in 0..<3 {
            let r = NSRect(x: origin.x + CGFloat(col) * (cell + gap), y: origin.y + CGFloat(2 - row) * (cell + gap), width: cell, height: cell)
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
            shadow.shadowBlurRadius = 18
            shadow.shadowOffset = NSSize(width: 0, height: -8)
            NSGraphicsContext.saveGraphicsState()
            shadow.set()
            let p = NSBezierPath(roundedRect: r, xRadius: 44, yRadius: 44)
            let (a, b) = colors[row * 3 + col]
            NSGradient(colors: [a, b])!.draw(in: p, angle: -90)
            NSGraphicsContext.restoreGraphicsState()
            // 上半部高光（裁切在圖示格內），做出玻璃感
            NSGraphicsContext.saveGraphicsState()
            p.addClip()
            NSGradient(colors: [NSColor.white.withAlphaComponent(0.40), NSColor.white.withAlphaComponent(0)])!
                .draw(in: NSRect(x: r.minX, y: r.midY, width: r.width, height: r.height / 2), angle: -90)
            NSGraphicsContext.restoreGraphicsState()
        }
    }
    return true
}
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
image.draw(in: NSRect(x: 0, y: 0, width: size, height: size))
NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
