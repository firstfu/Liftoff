//
//  RenderingTests.swift
//  LiftoffTests
//
//  圖示與名稱的點陣渲染：尺寸正確、長名稱截斷、快取鍵隨 App 更新而改變。
//

import AppKit
import Testing
@testable import Liftoff

@MainActor
struct RenderingTests {
    @Test func iconRendersAtRequestedPixelSize() throws {
        let image = try #require(IconRenderer.render(image: NSWorkspace.shared.icon(for: .application), pixelSize: 96, dark: false))
        #expect(image.width == 96 && image.height == 96)
    }

    @Test func labelTruncatesToMaxWidth() throws {
        let style = LabelStyle(fontSize: 13, maxWidth: 80, scale: 2)
        let font = LabelRenderer.labelFont(size: 13)
        let long = try #require(LabelRenderer.render(String(repeating: "Very Long Application Name ", count: 4), dark: false, font: font, style: style))
        // 寬度 = 最大寬度 + 陰影留白（左右各 2pt），再乘以倍率
        #expect(CGFloat(long.width) <= (80 + 4 + 1) * 2)
        let short = try #require(LabelRenderer.render("Mail", dark: true, font: font, style: style))
        #expect(short.width < long.width)
    }

    @Test func iconCacheKeyChangesWhenAppUpdates() {
        let old = AppEntry(id: "a", bundleID: "a", path: "/a.app", resolvedPath: "/a.app", name: "A", altNames: [],
                           category: nil, modified: Date(timeIntervalSince1970: 1))
        let new = AppEntry(id: "a", bundleID: "a", path: "/a.app", resolvedPath: "/a.app", name: "A", altNames: [],
                           category: nil, modified: Date(timeIntervalSince1970: 2))
        #expect(IconRenderer.cacheKey(for: old, pixelSize: 64, dark: false) != IconRenderer.cacheKey(for: new, pixelSize: 64, dark: false))
        #expect(IconRenderer.cacheKey(for: old, pixelSize: 64, dark: false) != IconRenderer.cacheKey(for: old, pixelSize: 64, dark: true))
    }

    @Test func scannerFindsSymlinkedHiddenApps() throws {
        // 仿 /Applications/Safari.app：隱藏旗標的符號連結指向真正的 App
        let root = FileManager.default.temporaryDirectory.appending(path: "scan-\(UUID().uuidString)")
        let real = root.appending(path: "Real/Fake.app/Contents")
        try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
        let plist: [String: Any] = ["CFBundleIdentifier": "com.example.fake", "CFBundleName": "Fake"]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: real.appending(path: "Info.plist"))
        let apps = root.appending(path: "Apps")
        try FileManager.default.createDirectory(at: apps, withIntermediateDirectories: true)
        let link = apps.appending(path: "Fake.app")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: root.appending(path: "Real/Fake.app"))
        var values = URLResourceValues()
        values.isHidden = true
        var mutableLink = link
        try? mutableLink.setResourceValues(values)
        defer { try? FileManager.default.removeItem(at: root) }

        let found = AppScanner.scan(directories: [apps])
        #expect(found.map(\.bundleID) == ["com.example.fake"])
        // 暫存目錄 /var 是 /private/var 的連結，比較時兩邊都解析成實際路徑
        #expect(found.first.map { URL(fileURLWithPath: $0.path).deletingLastPathComponent().resolvingSymlinksInPath().path }
                == apps.resolvingSymlinksInPath().path)
        #expect(found.first?.path.hasSuffix("/Apps/Fake.app") == true)
    }
}
