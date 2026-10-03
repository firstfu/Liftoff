//
//  AppSettings.swift
//  Liftoff
//
//  使用者設定：以 @Observable 提供 SwiftUI 綁定，每次修改立即寫回 UserDefaults。
//  服務層（快速鍵、熱角、手勢、背景）以 `observe(_:onChange:)` 訂閱需要的欄位，設定一改就即時生效。
//

import AppKit
import Observation
import ServiceManagement

/// 背景樣式。
nonisolated enum BackgroundStyle: String, CaseIterable, Codable, Sendable {
    /// 目前桌布 + 預先算好的高斯模糊（最省效能，與經典啟動台相同效果）
    case wallpaper
    /// 即時模糊（透出後方視窗，WindowServer 每幀合成）
    case liveBlur
    /// 自選圖片 + 模糊
    case customImage
}

/// App 名稱文字顏色。
nonisolated enum LabelColorMode: String, CaseIterable, Codable, Sendable {
    /// 依背景亮度自動選黑或白
    case auto
    case light
    case dark
}

/// App 圖示的明暗樣式（macOS 26 起部分圖示有深色版本）。
nonisolated enum IconAppearance: String, CaseIterable, Codable, Sendable {
    case system
    case light
    case dark
}

/// 啟動台要出現在哪個螢幕。
nonisolated enum DisplayTarget: String, CaseIterable, Codable, Sendable {
    /// 游標所在的螢幕
    case mouse
    /// 主螢幕（選單列所在）
    case primary
}

/// 螢幕熱角。
nonisolated enum HotCorner: String, CaseIterable, Codable, Sendable {
    case none
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight
}

/// 全域快速鍵組合（虛擬鍵碼 + NSEvent 修飾鍵）。
nonisolated struct HotKeyCombo: Codable, Equatable, Hashable, Sendable {
    var keyCode: UInt16
    var modifiers: UInt

    var modifierFlags: NSEvent.ModifierFlags { NSEvent.ModifierFlags(rawValue: modifiers) }

    /// 預設 ⌃⌘L：系統與常見 App（Safari/Chrome 的 ⌥⌘L 下載項目、ChatGPT 的 ⌥Space）都沒有占用
    static let defaultCombo = HotKeyCombo(keyCode: 37, modifiers: NSEvent.ModifierFlags([.control, .command]).rawValue)
}

@Observable
final class AppSettings {
    static let shared = AppSettings()

    @ObservationIgnored private let defaults: UserDefaults

    // MARK: 版面與外觀

    /// 每頁欄數
    var columns: Int { didSet { defaults.set(columns, forKey: Key.columns) } }
    /// 每頁列數
    var rows: Int { didSet { defaults.set(rows, forKey: Key.rows) } }
    /// 圖示大小倍率（1.0 = 依格子大小自動計算的標準尺寸）
    var iconScale: Double { didSet { defaults.set(iconScale, forKey: Key.iconScale) } }
    /// App 名稱字級（pt）
    var labelFontSize: Double { didSet { defaults.set(labelFontSize, forKey: Key.labelFontSize) } }
    var showsLabels: Bool { didSet { defaults.set(showsLabels, forKey: Key.showsLabels) } }
    var labelColor: LabelColorMode { didSet { defaults.set(labelColor.rawValue, forKey: Key.labelColor) } }
    var iconAppearance: IconAppearance { didSet { defaults.set(iconAppearance.rawValue, forKey: Key.iconAppearance) } }
    /// 緊湊模式：縮小頁面四周留白
    var compactMargins: Bool { didSet { defaults.set(compactMargins, forKey: Key.compactMargins) } }

    var backgroundStyle: BackgroundStyle { didSet { defaults.set(backgroundStyle.rawValue, forKey: Key.backgroundStyle) } }
    /// 背景模糊半徑（0–100）
    var blurRadius: Double { didSet { defaults.set(blurRadius, forKey: Key.blurRadius) } }
    /// 背景變暗程度（0–0.8）
    var dimming: Double { didSet { defaults.set(dimming, forKey: Key.dimming) } }
    /// 自選背景圖片路徑
    var customImagePath: String? { didSet { defaults.set(customImagePath, forKey: Key.customImagePath) } }
    /// 是否蓋住 Dock 與選單列（false 時 Dock 與選單列浮在啟動台之上，和經典啟動台一樣可見）
    var coversDock: Bool { didSet { defaults.set(coversDock, forKey: Key.coversDock) } }
    /// 再次打開時回到上次的頁面
    var remembersPage: Bool { didSet { defaults.set(remembersPage, forKey: Key.remembersPage) } }

    // MARK: 觸發方式

    var hotKey: HotKeyCombo? {
        didSet {
            if let hotKey, let data = try? JSONEncoder().encode(hotKey) {
                defaults.set(data, forKey: Key.hotKey)
            } else {
                defaults.set(Data(), forKey: Key.hotKey)
            }
        }
    }
    var hotCorner: HotCorner { didSet { defaults.set(hotCorner.rawValue, forKey: Key.hotCorner) } }
    /// 觸控板四/五指捏合開啟、張開關閉
    var pinchGesture: Bool { didSet { defaults.set(pinchGesture, forKey: Key.pinchGesture) } }
    var displayTarget: DisplayTarget { didSet { defaults.set(displayTarget.rawValue, forKey: Key.displayTarget) } }

    // MARK: 視窗縮圖預覽

    var windowPreview: Bool { didSet { defaults.set(windowPreview, forKey: Key.windowPreview) } }
    /// 游標停在執行中 App 上多久顯示預覽（秒）
    var previewDelay: Double { didSet { defaults.set(previewDelay, forKey: Key.previewDelay) } }

    // MARK: 一般

    /// Dock 與選單列圖示至少要留一個，否則使用者找不到入口：關掉其中一個時若另一個也是關的，自動把另一個打開。
    var showsDockIcon: Bool {
        didSet {
            defaults.set(showsDockIcon, forKey: Key.showsDockIcon)
            if !showsDockIcon && !showsMenuBarIcon { showsMenuBarIcon = true }
        }
    }
    var showsMenuBarIcon: Bool {
        didSet {
            defaults.set(showsMenuBarIcon, forKey: Key.showsMenuBarIcon)
            if !showsMenuBarIcon && !showsDockIcon { showsDockIcon = true }
        }
    }
    /// 隱藏的 App（識別鍵）
    var hiddenApps: Set<String> { didSet { defaults.set(Array(hiddenApps).sorted(), forKey: Key.hiddenApps) } }
    /// 額外掃描的資料夾（外接硬碟、自訂位置）
    var extraDirectories: [String] { didSet { defaults.set(extraDirectories, forKey: Key.extraDirectories) } }

    /// 每週自動向 GitHub 查詢新版本（預設關閉，符合「不主動連網」的承諾）
    var autoChecksForUpdates: Bool { didSet { defaults.set(autoChecksForUpdates, forKey: Key.autoChecksForUpdates) } }
    /// 上次成功查詢新版本的時間
    var lastUpdateCheck: Date? { didSet { defaults.set(lastUpdateCheck, forKey: Key.lastUpdateCheck) } }

    /// 開機自動啟動（直接讀寫 SMAppService，不另存）
    var launchAtLogin: Bool {
        get {
            access(keyPath: \.launchAtLogin)
            return SMAppService.mainApp.status == .enabled
        }
        set {
            withMutation(keyPath: \.launchAtLogin) {
                do {
                    if newValue { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                } catch {
                    Log.app.error("登入項目設定失敗：\(error.localizedDescription, privacy: .public)")
                }
            }
        }
    }

    /// 每頁容量
    var pageCapacity: Int { max(1, columns * rows) }

    private enum Key {
        static let columns = "columns", rows = "rows", iconScale = "iconScale", labelFontSize = "labelFontSize"
        static let showsLabels = "showsLabels", labelColor = "labelColor", iconAppearance = "iconAppearance"
        static let compactMargins = "compactMargins", backgroundStyle = "backgroundStyle", blurRadius = "blurRadius"
        static let dimming = "dimming", customImagePath = "customImagePath", coversDock = "coversDock"
        static let remembersPage = "remembersPage", hotKey = "hotKey", hotCorner = "hotCorner"
        static let pinchGesture = "pinchGesture", displayTarget = "displayTarget", windowPreview = "windowPreview"
        static let previewDelay = "previewDelay", showsDockIcon = "showsDockIcon", showsMenuBarIcon = "showsMenuBarIcon"
        static let hiddenApps = "hiddenApps", extraDirectories = "extraDirectories"
        static let autoChecksForUpdates = "autoChecksForUpdates", lastUpdateCheck = "lastUpdateCheck"
    }

    /// - Parameter defaults: 測試可注入獨立的 UserDefaults
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.columns: 7, Key.rows: 5, Key.iconScale: 1.0, Key.labelFontSize: 13.0, Key.showsLabels: true,
            Key.labelColor: LabelColorMode.auto.rawValue, Key.iconAppearance: IconAppearance.system.rawValue,
            Key.compactMargins: false, Key.backgroundStyle: BackgroundStyle.wallpaper.rawValue,
            Key.blurRadius: 45.0, Key.dimming: 0.22, Key.coversDock: true, Key.remembersPage: true,
            Key.hotCorner: HotCorner.none.rawValue, Key.pinchGesture: true, Key.displayTarget: DisplayTarget.mouse.rawValue,
            Key.windowPreview: true, Key.previewDelay: 0.5, Key.showsDockIcon: true, Key.showsMenuBarIcon: true,
        ])
        columns = defaults.integer(forKey: Key.columns)
        rows = defaults.integer(forKey: Key.rows)
        iconScale = defaults.double(forKey: Key.iconScale)
        labelFontSize = defaults.double(forKey: Key.labelFontSize)
        showsLabels = defaults.bool(forKey: Key.showsLabels)
        labelColor = LabelColorMode(rawValue: defaults.string(forKey: Key.labelColor) ?? "") ?? .auto
        iconAppearance = IconAppearance(rawValue: defaults.string(forKey: Key.iconAppearance) ?? "") ?? .system
        compactMargins = defaults.bool(forKey: Key.compactMargins)
        backgroundStyle = BackgroundStyle(rawValue: defaults.string(forKey: Key.backgroundStyle) ?? "") ?? .wallpaper
        blurRadius = defaults.double(forKey: Key.blurRadius)
        dimming = defaults.double(forKey: Key.dimming)
        customImagePath = defaults.string(forKey: Key.customImagePath)
        coversDock = defaults.bool(forKey: Key.coversDock)
        remembersPage = defaults.bool(forKey: Key.remembersPage)
        if let data = defaults.data(forKey: Key.hotKey) {
            // 空資料代表使用者刻意清除了快速鍵
            hotKey = data.isEmpty ? nil : (try? JSONDecoder().decode(HotKeyCombo.self, from: data))
        } else {
            hotKey = .defaultCombo
        }
        hotCorner = HotCorner(rawValue: defaults.string(forKey: Key.hotCorner) ?? "") ?? .none
        pinchGesture = defaults.bool(forKey: Key.pinchGesture)
        displayTarget = DisplayTarget(rawValue: defaults.string(forKey: Key.displayTarget) ?? "") ?? .mouse
        windowPreview = defaults.bool(forKey: Key.windowPreview)
        previewDelay = defaults.double(forKey: Key.previewDelay)
        showsDockIcon = defaults.bool(forKey: Key.showsDockIcon)
        showsMenuBarIcon = defaults.bool(forKey: Key.showsMenuBarIcon)
        hiddenApps = Set(defaults.stringArray(forKey: Key.hiddenApps) ?? [])
        extraDirectories = defaults.stringArray(forKey: Key.extraDirectories) ?? []
        autoChecksForUpdates = defaults.bool(forKey: Key.autoChecksForUpdates)
        lastUpdateCheck = defaults.object(forKey: Key.lastUpdateCheck) as? Date
        // 舊版本可能已存成兩個都關；補上不變式
        if !showsDockIcon && !showsMenuBarIcon { showsMenuBarIcon = true }
    }

    /// 還原外觀相關設定為預設值。
    func resetAppearance() {
        columns = 7; rows = 5; iconScale = 1.0; labelFontSize = 13; showsLabels = true
        labelColor = .auto; iconAppearance = .system; compactMargins = false
        backgroundStyle = .wallpaper; blurRadius = 45; dimming = 0.22; coversDock = true
    }
}

/// 持續觀察 @Observable 屬性：值改變後（在下一輪 MainActor）以新值呼叫 `onChange`。
/// `withObservationTracking` 只通知一次、且在「將要改變」時通知，所以要在下一輪重新讀值並重新註冊。
/// 觀察會持續到 App 結束（服務層都是 App 生命週期等長的物件）。
/// - Parameters:
///   - value: 讀取要觀察的值（closure 內讀到的所有 @Observable 屬性都會被追蹤）
///   - onChange: 值真的改變後呼叫（相同值的重複通知會被濾掉）
func observe<T: Equatable>(_ value: @escaping @MainActor () -> T, onChange: @escaping @MainActor (T) -> Void) {
    _ = ObservationLoop(value: value, onChange: onChange)
}

private final class ObservationLoop<T: Equatable> {
    private let value: @MainActor () -> T
    private let onChange: @MainActor (T) -> Void
    private var previous: T

    init(value: @escaping @MainActor () -> T, onChange: @escaping @MainActor (T) -> Void) {
        self.value = value
        self.onChange = onChange
        previous = value()
        track()
    }

    /// 註冊一次追蹤；註冊用的 closure 持有 self，因此不需外部保留。
    private func track() {
        _ = withObservationTracking {
            value()
        } onChange: { [self] in
            Task { @MainActor in self.fire() }
        }
    }

    private func fire() {
        let next = value()
        if next != previous {
            previous = next
            onChange(next)
        }
        track()
    }
}
