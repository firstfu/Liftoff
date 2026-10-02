//
//  SettingsView.swift
//  Liftoff
//
//  設定視窗（SwiftUI Settings 場景）：一般、觸發方式、外觀、視窗預覽、佈局。
//  所有選項直接綁定 AppSettings，修改即時生效（協調者會觀察變化並套用）。
//

import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    let coordinator: AppCoordinator

    var body: some View {
        TabView {
            Tab("一般", systemImage: "gearshape") {
                GeneralSettings(settings: coordinator.settings)
            }
            Tab("觸發方式", systemImage: "hand.tap") {
                TriggerSettings(coordinator: coordinator, settings: coordinator.settings)
            }
            Tab("外觀", systemImage: "paintpalette") {
                AppearanceSettings(settings: coordinator.settings)
            }
            Tab("視窗預覽", systemImage: "rectangle.on.rectangle") {
                PreviewSettings(settings: coordinator.settings, permissions: coordinator.permissions)
            }
            Tab("佈局", systemImage: "square.grid.3x3") {
                LayoutSettings(coordinator: coordinator, settings: coordinator.settings)
            }
        }
        .frame(width: 560, height: 640)
    }
}

// MARK: - 一般

private struct GeneralSettings: View {
    @Bindable var settings: AppSettings

    var body: some View {
        Form {
            Section {
                Toggle("登入時自動啟動", isOn: $settings.launchAtLogin)
                Toggle("在 Dock 顯示圖示（點一下打開啟動台）", isOn: $settings.showsDockIcon)
                Toggle("在選單列顯示圖示", isOn: $settings.showsMenuBarIcon)
            }
            Section {
                Picker("顯示在", selection: $settings.displayTarget) {
                    Text("游標所在的螢幕").tag(DisplayTarget.mouse)
                    Text("主螢幕").tag(DisplayTarget.primary)
                }
                Toggle("再次打開時回到上次的頁面", isOn: $settings.remembersPage)
            }
            Section {
                Label("Dock 與選單列圖示至少保留一個，避免找不到啟動台的入口。", systemImage: "info.circle")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - 觸發方式

private struct TriggerSettings: View {
    let coordinator: AppCoordinator
    @Bindable var settings: AppSettings

    var body: some View {
        Form {
            Section("快速鍵") {
                LabeledContent("打開/收起啟動台") {
                    HotKeyRecorder(combo: $settings.hotKey, hotKeys: coordinator.hotKeys)
                }
                if !coordinator.hotKeyRegistered {
                    Label("這組快速鍵已被其他 App 占用，請換一組。", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
            }
            Section("觸控板") {
                Toggle("拇指與三指捏合打開、張開收起", isOn: $settings.pinchGesture)
                    .disabled(!TrackpadGesture.shared.isAvailable)
                if settings.pinchGesture {
                    Text("開啟時會自動關閉系統的捏合手勢（「App」），關閉或結束 Liftoff 時還原。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            Section("熱角") {
                Picker("游標移到螢幕角落時打開", selection: $settings.hotCorner) {
                    Text("關閉").tag(HotCorner.none)
                    Text("左上角").tag(HotCorner.topLeft)
                    Text("右上角").tag(HotCorner.topRight)
                    Text("左下角").tag(HotCorner.bottomLeft)
                    Text("右下角").tag(HotCorner.bottomRight)
                }
            }
            Section("其他") {
                LabeledContent("Dock 圖示", value: "點一下打開或收起")
                LabeledContent("捷徑 / 腳本") {
                    Text("open liftoff://toggle").font(.system(.body, design: .monospaced)).textSelection(.enabled)
                }
            }
        }
        .formStyle(.grouped)
    }
}

/// 系統觸控板捏合手勢（「App」／啟動台）的讀取與開關。
///
/// 我們的捏合手勢開啟時會關掉系統的，避免兩者同時觸發；關閉或結束 App 時還原成使用者原本的值。
/// 實測只改觸控板 domain 不夠：Dock 另看 `com.apple.dock` 的 `showLaunchpadGestureEnabled`，
/// 系統設定切換「App」時三處一起改，我們也得照做才會真的失效。
enum SystemGesture {
    /// 一個要改的系統偏好設定：關閉值與「沒設定過時」的預設值
    private struct Pref {
        let domain: String, key: String, off: Int, fallback: Int
        var id: String { "\(domain)|\(key)" }
    }

    private static let prefs: [Pref] = {
        // 內建觸控板與「藏在藍牙驅動」的外接觸控板各一份
        let trackpad = ["com.apple.AppleMultitouchTrackpad", "com.apple.driver.AppleBluetoothMultitouch.trackpad"].flatMap { domain in
            ["TrackpadFourFingerPinchGesture", "TrackpadFiveFingerPinchGesture"].map { Pref(domain: domain, key: $0, off: 0, fallback: 2) }
        }
        return trackpad + [Pref(domain: "com.apple.dock", key: "showLaunchpadGestureEnabled", off: 0, fallback: 1)]
    }()
    /// 備份原值的 key（存在 Liftoff 自己的 UserDefaults；有值＝目前由我們代為關閉中）
    private static let backupKey = "systemPinchBackup"

    /// 讀目前值；沒設定過視為系統預設（開啟）
    private static func current(_ pref: Pref) -> Int {
        CFPreferencesCopyAppValue(pref.key as CFString, pref.domain as CFString) as? Int ?? pref.fallback
    }

    /// 系統捏合手勢是否仍有任何一處開著（開著就會與我們的手勢同時觸發）
    static var systemPinchEnabled: Bool {
        prefs.contains { current($0) != $0.off }
    }

    /// 關掉系統捏合手勢，並備份原值供 `restoreSystemPinch()` 還原。
    /// 已備份過就只補上缺的項目，不覆蓋（否則會把「已關閉」的值當成原值而永遠還原不回去）。
    static func disableSystemPinch() {
        guard systemPinchEnabled else { return }
        var backup = UserDefaults.standard.dictionary(forKey: backupKey) as? [String: Int] ?? [:]
        for pref in prefs where backup[pref.id] == nil {
            backup[pref.id] = current(pref)
        }
        UserDefaults.standard.set(backup, forKey: backupKey)
        write { $0.off }
    }

    /// 還原成備份的原值；沒有備份代表不是我們關的，什麼都不動。
    static func restoreSystemPinch() {
        guard let backup = UserDefaults.standard.dictionary(forKey: backupKey) as? [String: Int] else { return }
        write { backup[$0.id] ?? $0.fallback }
        UserDefaults.standard.removeObject(forKey: backupKey)
    }

    /// 寫入所有偏好設定並讓它即時生效：
    /// `activateSettings -u` 通知觸控板驅動重讀設定，重啟 Dock 讓它重讀 `showLaunchpadGestureEnabled`。
    private static func write(_ value: (Pref) -> Int) {
        for pref in prefs {
            let number = value(pref)
            // Dock 的開關是 Bool，觸控板的是數字（0 關、2 開），型別照系統設定寫入
            let object: CFPropertyList = pref.domain == "com.apple.dock" ? (number != 0) as CFBoolean : number as CFNumber
            CFPreferencesSetAppValue(pref.key as CFString, object, pref.domain as CFString)
        }
        Set(prefs.map(\.domain)).forEach { CFPreferencesAppSynchronize($0 as CFString) }
        run("/System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings", ["-u"])
        run("/usr/bin/killall", ["Dock"])
    }

    /// 同步執行外部指令（結束 App 時呼叫也要等它跑完，否則行程先退出就沒套用）
    private static func run(_ path: String, _ arguments: [String]) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: path)
        task.arguments = arguments
        try? task.run()
        task.waitUntilExit()
    }

    static func openTrackpadSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Trackpad-Settings.extension")!)
    }
}

// MARK: - 外觀

private struct AppearanceSettings: View {
    @Bindable var settings: AppSettings

    var body: some View {
        Form {
            Section("格線") {
                Stepper("每頁欄數：\(settings.columns)", value: $settings.columns, in: 4...12)
                Stepper("每頁列數：\(settings.rows)", value: $settings.rows, in: 3...8)
                LabeledContent("圖示大小") {
                    Slider(value: $settings.iconScale, in: 0.6...1.4) { Text("圖示大小") }
                        .labelsHidden()
                }
                Toggle("緊湊版面（減少四周留白）", isOn: $settings.compactMargins)
            }
            Section("App 名稱") {
                Toggle("顯示名稱", isOn: $settings.showsLabels)
                LabeledContent("字級：\(Int(settings.labelFontSize)) pt") {
                    Slider(value: $settings.labelFontSize, in: 10...18, step: 1) { Text("字級") }
                        .labelsHidden()
                }
                .disabled(!settings.showsLabels)
                Picker("文字顏色", selection: $settings.labelColor) {
                    Text("依背景自動").tag(LabelColorMode.auto)
                    Text("白色").tag(LabelColorMode.light)
                    Text("黑色").tag(LabelColorMode.dark)
                }
                Picker("圖示樣式", selection: $settings.iconAppearance) {
                    Text("跟隨系統").tag(IconAppearance.system)
                    Text("淺色").tag(IconAppearance.light)
                    Text("深色").tag(IconAppearance.dark)
                }
            }
            Section("背景") {
                Picker("樣式", selection: $settings.backgroundStyle) {
                    Text("模糊桌布（最省電）").tag(BackgroundStyle.wallpaper)
                    Text("即時模糊（透出視窗）").tag(BackgroundStyle.liveBlur)
                    Text("自選圖片").tag(BackgroundStyle.customImage)
                }
                if settings.backgroundStyle == .customImage {
                    LabeledContent("圖片") {
                        HStack {
                            Text(settings.customImagePath.map { ($0 as NSString).lastPathComponent } ?? "未選擇")
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            Button("選擇…") { chooseImage() }
                        }
                    }
                }
                if settings.backgroundStyle != .liveBlur {
                    LabeledContent("模糊程度") {
                        Slider(value: $settings.blurRadius, in: 0...100) { Text("模糊程度") }.labelsHidden()
                    }
                    LabeledContent("變暗程度") {
                        Slider(value: $settings.dimming, in: 0...0.8) { Text("變暗程度") }.labelsHidden()
                    }
                }
                Toggle("蓋住 Dock 與選單列", isOn: $settings.coversDock)
            }
            Section {
                Button("還原預設外觀") { settings.resetAppearance() }
            }
        }
        .formStyle(.grouped)
    }

    private func chooseImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            settings.customImagePath = url.path
        }
    }
}

// MARK: - 視窗預覽

private struct PreviewSettings: View {
    @Bindable var settings: AppSettings
    let permissions: Permissions

    var body: some View {
        Form {
            Section {
                Toggle("游標停在執行中的 App 上時顯示視窗縮圖", isOn: $settings.windowPreview)
                LabeledContent("顯示延遲：\(settings.previewDelay, format: .number.precision(.fractionLength(1))) 秒") {
                    Slider(value: $settings.previewDelay, in: 0.1...1.5, step: 0.1) { Text("延遲") }.labelsHidden()
                }
                .disabled(!settings.windowPreview)
                Text("也可以用方向鍵選到 App 後按空白鍵預覽；點縮圖直接切換到該視窗。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Section("權限") {
                PermissionRow(
                    title: "螢幕錄製", detail: "擷取視窗縮圖（必要）",
                    granted: permissions.screenRecording, action: Permissions.openScreenRecordingSettings
                )
                PermissionRow(
                    title: "輔助使用", detail: "顯示最小化視窗、精準切換到指定視窗（選用）",
                    granted: permissions.accessibility, action: Permissions.openAccessibilitySettings
                )
            }
        }
        .formStyle(.grouped)
        .onAppear {
            permissions.refresh()
            permissions.startPolling()
        }
    }
}

private struct PermissionRow: View {
    let title: LocalizedStringKey
    let detail: LocalizedStringKey
    let granted: Bool
    let action: () -> Void

    var body: some View {
        HStack {
            Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.circle")
                .foregroundStyle(granted ? .green : .orange)
            VStack(alignment: .leading) {
                Text(title)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if !granted { Button("授權…", action: action) }
        }
    }
}

// MARK: - 佈局

private struct LayoutSettings: View {
    let coordinator: AppCoordinator
    @Bindable var settings: AppSettings
    @State private var backups: [LayoutStore.Backup] = []
    @State private var pendingAction: PendingAction?
    @State private var message: String?

    private enum PendingAction: Identifiable {
        case importLegacy, alphabetical, restore(LayoutStore.Backup)
        var id: String {
            switch self {
            case .importLegacy: "import"
            case .alphabetical: "alphabetical"
            case .restore(let backup): backup.url.path
            }
        }
    }

    var body: some View {
        Form {
            Section("整理") {
                Button("匯入舊版啟動台的排列…") { pendingAction = .importLegacy }
                    .disabled(LaunchpadImporter.databaseURL == nil)
                Button("依名稱重新排列…") { pendingAction = .alphabetical }
                Button("填滿各頁空位") {
                    coordinator.layoutStore.update { $0.compact(capacity: settings.pageCapacity) }
                    message = String(localized: "已整理頁面")
                }
                if let message { Text(message).font(.callout).foregroundStyle(.secondary) }
            }
            Section("備份") {
                Button("立即備份目前排列") {
                    _ = try? coordinator.layoutStore.createBackup()
                    reloadBackups()
                }
                ForEach(backups) { backup in
                    HStack {
                        Text(backup.name)
                        Spacer()
                        Button("還原") { pendingAction = .restore(backup) }
                        Button(role: .destructive) {
                            coordinator.layoutStore.deleteBackup(backup)
                            reloadBackups()
                        } label: { Image(systemName: "trash") }
                            .buttonStyle(.borderless)
                    }
                }
            }
            Section("隱藏的 App") {
                if settings.hiddenApps.isEmpty {
                    Text("沒有隱藏的 App（在啟動台的 App 上按右鍵可隱藏）").foregroundStyle(.secondary)
                }
                ForEach(settings.hiddenApps.sorted(), id: \.self) { id in
                    HStack {
                        if let image = coordinator.icons.icon(for: id).cgImage {
                            Image(decorative: image, scale: 1).resizable().frame(width: 20, height: 20)
                        }
                        Text(coordinator.catalog.entry(id)?.name ?? id)
                        Spacer()
                        Button("恢復顯示") { settings.hiddenApps.remove(id) }
                    }
                }
            }
            Section("額外掃描的資料夾") {
                ForEach(settings.extraDirectories, id: \.self) { path in
                    HStack {
                        Text(path).lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Button(role: .destructive) {
                            settings.extraDirectories.removeAll { $0 == path }
                        } label: { Image(systemName: "minus.circle") }
                            .buttonStyle(.borderless)
                    }
                }
                Button("加入資料夾…（例如外接硬碟上的 App）") { addDirectory() }
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: reloadBackups)
        .alert(item: $pendingAction) { action in
            Alert(
                title: Text(title(for: action)),
                message: Text("目前的排列會先自動備份，之後可在這裡還原。"),
                primaryButton: .default(Text("繼續")) { perform(action) },
                secondaryButton: .cancel(Text("取消"))
            )
        }
    }

    private func title(for action: PendingAction) -> String {
        switch action {
        case .importLegacy: String(localized: "要改用舊版啟動台的排列嗎？")
        case .alphabetical: String(localized: "要依名稱重新排列所有 App 嗎？")
        case .restore(let backup): String(localized: "要還原「\(backup.name)」的排列嗎？")
        }
    }

    private func perform(_ action: PendingAction) {
        let store = coordinator.layoutStore
        let entries = coordinator.catalog.entries
        let capacity = settings.pageCapacity
        _ = try? store.createBackup()
        do {
            switch action {
            case .importLegacy:
                guard let url = LaunchpadImporter.databaseURL else { return }
                let imported = try LaunchpadImporter.read(at: url)
                store.replace(with: LaunchpadImporter.makeLayout(from: imported, entries: entries, hidden: settings.hiddenApps, capacity: capacity))
                message = String(localized: "已匯入舊版啟動台的排列")
            case .alphabetical:
                store.replace(with: .alphabetical(entries: entries, capacity: capacity, hidden: settings.hiddenApps))
                message = String(localized: "已依名稱重新排列")
            case .restore(let backup):
                try store.restore(backup, entries: entries, hidden: settings.hiddenApps, capacity: capacity)
                message = String(localized: "已還原")
            }
        } catch {
            message = error.localizedDescription
        }
        reloadBackups()
    }

    private func reloadBackups() {
        backups = coordinator.layoutStore.backups()
    }

    private func addDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url, !settings.extraDirectories.contains(url.path) {
            settings.extraDirectories.append(url.path)
        }
    }
}

#Preview("設定") {
    SettingsView(coordinator: AppCoordinator.shared)
}

#Preview("觸發方式") {
    TriggerSettings(coordinator: AppCoordinator.shared, settings: AppSettings.shared)
        .frame(width: 560, height: 520)
}

#Preview("外觀") {
    AppearanceSettings(settings: AppSettings.shared)
        .frame(width: 560, height: 720)
}

#Preview("佈局") {
    LayoutSettings(coordinator: AppCoordinator.shared, settings: AppSettings.shared)
        .frame(width: 560, height: 620)
}
