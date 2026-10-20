//
//  MenuBarIcon.swift
//  Liftoff
//
//  選單列圖示。有新版本時在右上角加小圓點（低調提醒，取代跳視窗，見 UpdateChecker.swift）。
//  MenuBarExtra 的 label 只會畫出圖片本身，SwiftUI overlay 不會出現在選單列，所以直接合成一張 template 圖。
//

import AppKit

enum MenuBarIcon {
    /// 選單列圖示。
    /// - Parameter badged: 是否在右上角加小圓點
    /// - Returns: template 圖，顏色由系統依選單列深淺決定
    static func image(badged: Bool) -> NSImage {
        let configuration = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        guard let base = NSImage(systemSymbolName: "square.grid.3x3.fill", accessibilityDescription: "Liftoff")?
            .withSymbolConfiguration(configuration) else { return NSImage() }
        guard badged else { return base }
        let image = NSImage(size: base.size, flipped: false) { rect in
            base.draw(in: rect)
            let diameter = rect.width * 0.36
            let dot = NSRect(x: rect.maxX - diameter, y: rect.maxY - diameter, width: diameter, height: diameter)
            // 先在圓點周圍挖一圈透明，圓點才不會和格子黏成一團
            NSGraphicsContext.current?.compositingOperation = .clear
            NSBezierPath(ovalIn: dot.insetBy(dx: -1.5, dy: -1.5)).fill()
            NSGraphicsContext.current?.compositingOperation = .sourceOver
            NSColor.black.setFill()
            NSBezierPath(ovalIn: dot).fill()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Liftoff"
        return image
    }
}
