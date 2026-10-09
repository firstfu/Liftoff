//
//  AppCoordinator.swift
//  Liftoff
//
//  統籌所有服務：App 清單、版面、圖示、背景、觸發方式（快速鍵/熱角/手勢/Dock 圖示/URL），
//  以及設定變更後的即時套用。
//
//  啟動順序刻意安排成「先能用、再變準」：
//  1. 同步讀取磁碟上的 App 索引與版面（數毫秒）→ 馬上可以打開
//  2. 圖示從磁碟快取並行載入（~20ms）、背景桌布模糊預先計算
//  3. 背景重掃 App 資料夾、比對差異，之後以 FSEvents 監看變動
//

import AppKit
import Observation
import ServiceManagement

final class AppCoordinator {
    static let shared = AppCoordinator()

    let settings = AppSettings.shared
    let catalog = AppCatalog()
    let layoutStore = LayoutStore()
    let icons = IconStore()
    let running = RunningApps()
    let usage = UsageStore()
    let wallpapers = WallpaperProvider()
    let labels = LabelStore()
    let permissions = Permissions()
    let updates = UpdateChecker(settings: AppSettings.shared)
    let hotKeys = HotKeyService()
    let hotCorners = HotCornerService()

    private(set) lazy var model = LaunchpadModel(
        settings: settings, catalog: catalog, layoutStore: layoutStore, icons: icons, running: running, usage: usage
    )
    private(set) lazy var controller = LaunchpadWindowController(model: model, settings: settings, wallpapers: wallpapers, labels: labels)

    /// 顯示啟動台時我們是否是前景 App（點 Dock 圖示開啟時會是），收起時要把焦點還回去
    private var activatedForShow = false
    private(set) var isLaunched = false
    /// 快速鍵是否註冊成功（設定頁顯示衝突提示用）
    private(set) var hotKeyRegistered = true
    private var iconSyncTask: Task<Void, Never>?
    private var backgroundTask: Task<Void, Never>?

    // MARK: - 啟動

    func launch() {
        let start = ContinuousClock.now
        var mark = start
        func phase(_ name: StaticString) {
            Log.perf.debug("啟動階段 \(name, privacy: .public): \(milliseconds(since: mark), format: .fixed(precision: 1))ms")
            mark = .now
        }
        catalog.setDirectories(extra: settings.extraDirectories)
        catalog.onChange = { [weak self] in self?.catalogChanged() }
        layoutStore.load()
        phase("layout")
        catalog.loadIndex()
        phase("index+sync")

        running.start(catalog: catalog)
        model.requestDismiss = { [weak self] reason in self?.hide(reason: reason) }
        model.requestSettings = { [weak self] in self?.openSettings() }
        model.preview.onActivateWindow = { [weak self] window in
            self?.hide(reason: .switchedWindow)
            WindowActions.focus(window)
        }
        controller.onHide = { [weak self] reason in self?.didHide(reason: reason) }
        phase("model")
        observeWorkspace()
        configureTriggers()
        phase("triggers")
        // 在開始觀察設定之前：改指向副本不必觸發一次背景重算
        WallpaperLibrary.adoptLegacyPath(in: settings)
        observeSettings()
        // 設定頁在另一個 process 寫入 UserDefaults，以 KVO 接收後更新，上面的觀察者就會套用
        settings.startExternalSync()
        updates.applyAutoCheckSetting()
        applyActivationPolicy()
        phase("settings")

        if let screen = NSScreen.main { controller.prewarm(on: screen) }
        phase("prewarm")
        controller.prewarmBackgrounds()
        Task {
            await catalog.rescan()
            catalog.startWatching()
            icons.pruneDiskCache()
        }
        isLaunched = true
        Log.app.info("啟動完成（同步階段 \(milliseconds(since: start), format: .fixed(precision: 1))ms），App \(self.catalog.entries.count) 個")
    }

    /// App 清單變動：同步版面、圖示、執行狀態與搜尋索引。
    private func catalogChanged() {
        let start = ContinuousClock.now
        let origin = layoutStore.reconcile(entries: catalog.entries, hidden: settings.hiddenApps, capacity: settings.pageCapacity)
        if origin != "reconciled" { Log.layout.info("建立初始版面：\(origin, privacy: .public)") }
        let reconciled = milliseconds(since: start)
        syncIcons()
        running.refresh()
        let refreshed = milliseconds(since: start)
        model.rebuildSearchIndex()
        Log.perf.debug("清單同步：版面 \(reconciled, format: .fixed(precision: 1))ms、圖示+執行 \(refreshed - reconciled, format: .fixed(precision: 1))ms、搜尋索引 \(milliseconds(since: start) - refreshed, format: .fixed(precision: 1))ms")
    }

    // MARK: - 顯示/隱藏

    func toggle(screen: NSScreen? = nil) {
        if controller.isVisible { hide(reason: .user) } else { show(screen: screen) }
    }

    /// App 剛啟動時的第一次顯示：稍等背景模糊算好（最多 300ms），避免先閃一下即時模糊再換成桌布。
    func showAfterLaunch() async {
        let target = targetScreen()
        await wallpapers.waitUntilReady(for: target, settings: settings, timeout: .milliseconds(300))
        show(screen: target)
    }

    func show(screen: NSScreen? = nil) {
        guard !controller.isVisible else { return }
        let target = screen ?? targetScreen()
        activatedForShow = NSApp.isActive
        ensureIconsMatch(target)
        controller.show(on: target)
    }

    func hide(reason: DismissReason) {
        controller.hide(reason: reason)
    }

    private func didHide(reason: DismissReason) {
        // 由 Dock 圖示打開時我們成了前景 App；收起後交還焦點（開 App/切視窗時由目標 App 自己搶焦點）
        if activatedForShow, reason == .user, NSApp.isActive, !hasVisibleRegularWindows {
            NSApp.hide(nil)
        }
        activatedForShow = false
    }

    private var hasVisibleRegularWindows: Bool {
        NSApp.windows.contains { $0.isVisible && $0 !== controller.panel && $0.level == .normal && !($0 is NSPanel) }
    }

    /// 依設定決定出現在哪個螢幕。
    private func targetScreen() -> NSScreen {
        switch settings.displayTarget {
        case .mouse:
            let mouse = NSEvent.mouseLocation
            return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens[0]
        case .primary:
            return NSScreen.screens.first ?? NSScreen.main!
        }
    }

    // MARK: - 設定視窗

    /// 設定 process 的管理者（設定頁跑在另一個 process，見 `SettingsIPC.swift`）
    private lazy var settingsHost = SettingsHost(actions: .init(
        perform: { [weak self] command, argument in try self?.performLayoutCommand(command, argument: argument) },
        pauseHotKey: { [weak self] in self?.hotKeys.unregister() },
        resumeHotKey: { [weak self] in
            guard let self else { return }
            // 設定 process 剛寫入的新組合可能還沒經 KVO 同步過來，先主動讀一次
            self.settings.reload()
            self.hotKeyRegistered = self.hotKeys.register(self.settings.hotKey)
        },
        hotKeyRegistered: { [weak self] in self?.hotKeyRegistered ?? true },
        openURL: { [weak self] url in self?.handle(url: url) }
    ))

    /// 打開設定視窗（已開著就帶到最前）；會先收起啟動台。
    func openSettings() {
        hide(reason: .settings)
        settingsHost.open()
    }

    /// 執行設定頁送來的版面指令。會改動排列的指令都先自動備份目前排列，設定頁的提示文字也是這樣寫的。
    /// - Parameters:
    ///   - command: 版面指令
    ///   - argument: 指令參數（還原時為備份檔路徑）
    /// - Throws: 匯入、讀取備份失敗時的錯誤
    private func performLayoutCommand(_ command: SettingsIPC.Command, argument: String?) throws {
        let entries = catalog.entries
        let hidden = settings.hiddenApps
        let capacity = settings.pageCapacity
        switch command {
        case .compact:
            layoutStore.update { $0.compact(capacity: capacity) }
        case .backup:
            try layoutStore.createBackup()
        case .alphabetical:
            _ = try? layoutStore.createBackup()
            layoutStore.replace(with: .alphabetical(entries: entries, capacity: capacity, hidden: hidden))
        case .importLegacy:
            guard let url = LaunchpadImporter.databaseURL else { return }
            _ = try? layoutStore.createBackup()
            let imported = try LaunchpadImporter.read(at: url)
            layoutStore.replace(with: LaunchpadImporter.makeLayout(from: imported, entries: entries, hidden: hidden, capacity: capacity))
        case .organize:
            _ = try? layoutStore.createBackup()
            let plan = OrganizePlan(entries: entries, hidden: hidden, classifier: .bundled())
            layoutStore.replace(with: plan.layout(capacity: capacity))
        case .restore:
            guard let argument else { return }
            // 只接受備份資料夾裡的檔案：請求來自 distributed notification，任何本機程式都送得出來
            guard let backup = layoutStore.backups().first(where: { $0.url.path == argument }) else { return }
            _ = try? layoutStore.createBackup()
            try layoutStore.restore(backup, entries: entries, hidden: hidden, capacity: capacity)
        default:
            return
        }
        // 設定頁改的版面要立刻落地：使用者可能接著就關掉設定或結束 App
        layoutStore.saveNow()
    }

    // MARK: - 觸發方式

    private func configureTriggers() {
        hotKeys.onPress = { [weak self] in self?.toggle() }
        hotKeyRegistered = hotKeys.register(settings.hotKey)
        hotCorners.onTrigger = { [weak self] screen in self?.toggle(screen: screen) }
        hotCorners.configure(settings.hotCorner)
        applyGesture()
    }

    private func applyGesture() {
        guard settings.pinchGesture else {
            TrackpadGesture.shared.stop()
            SystemGesture.restoreSystemPinch()
            return
        }
        // 兩套手勢同時作用會一起觸發，所以我們接手時先關掉系統的
        SystemGesture.disableSystemPinch()
        TrackpadGesture.shared.start { event in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { AppCoordinator.shared.handlePinch(event) }
            }
        }
    }

    /// 捏合手勢的跟手狀態：nil = 沒有進行中的手勢。
    private enum PinchMode { case opening, closing }
    private var pinchMode: PinchMode?
    /// ratio 偏離 1 超過這個量才算手勢開始（避免手指微動就把視窗叫出來）；與 `TrackpadGesture` 判定捏合用同一個值
    private static let pinchDeadZone = PinchIntent.deadZone
    /// 這次手勢的進度樣本，放手時據以判斷完成或回彈（含速度）
    private var pinchRelease = PinchRelease()

    /// 手勢每幀把 ratio 換算成視窗進度（0 收起…1 展開）；放手時依進度與速度決定完成或回彈。
    private func handlePinch(_ event: TrackpadGesture.Event) {
        switch event {
        case .changed(let ratio, let time):
            if pinchMode == nil {
                if !controller.isVisible, ratio < 1 - Self.pinchDeadZone {
                    pinchMode = .opening
                    activatedForShow = NSApp.isActive
                    let target = targetScreen()
                    ensureIconsMatch(target)
                    controller.show(on: target, interactive: true)
                } else if controller.isVisible, ratio > 1 + Self.pinchDeadZone {
                    pinchMode = .closing
                    controller.beginInteractiveClose()
                }
                if pinchMode != nil { pinchRelease.reset() }
            }
            switch pinchMode {
            case .opening:
                controller.updateInteractive((1 - ratio) / (1 - TrackpadGesture.inwardRatio))
                pinchRelease.record(time: time, progress: controller.fraction)
            case .closing:
                controller.updateInteractive(1 - (ratio - 1) / (TrackpadGesture.outwardRatio - 1))
                pinchRelease.record(time: time, progress: 1 - controller.fraction)
            case nil:
                break
            }
        case .ended:
            guard let mode = pinchMode else { return }
            pinchMode = nil
            // 進度過 4 成，或放手前仍快速朝目標方向移動（又快又小的捏合）就完成，否則回彈
            let commit = pinchRelease.shouldCommit
            Log.input.info("捏合放手 \(mode == .opening ? "開啟" : "關閉", privacy: .public) 進度 \(self.pinchRelease.progress, format: .fixed(precision: 2)) 速度 \(self.pinchRelease.velocity, format: .fixed(precision: 2))/s → \(commit ? "完成" : "回彈", privacy: .public)")
            controller.endInteractive(opening: mode == .opening, commit: commit)
        }
    }

    /// 外部控制：liftoff://show、liftoff://hide、liftoff://toggle。
    func handle(url: URL) {
        switch url.host() {
        case "show": show()
        case "hide": hide(reason: .user)
        case "settings": openSettings()
        case "permissions":
            // 讓系統把 Liftoff 加進「螢幕與系統錄音」清單並跳出授權提示
            hide(reason: .settings)
            Permissions.openScreenRecordingSettings()
        default: toggle()
        }
    }

    // MARK: - 設定與系統變化

    private func observeSettings() {
        observe({ [settings] in settings.hotKey }) { [weak self] combo in
            guard let self else { return }
            self.hotKeyRegistered = self.hotKeys.register(combo)
            self.settingsHost.broadcastState()
        }
        observe({ [settings] in settings.hotCorner }) { [weak self] corner in self?.hotCorners.configure(corner) }
        observe({ [settings] in settings.autoChecksForUpdates }) { [weak self] _ in self?.updates.applyAutoCheckSetting() }
        observe({ [settings] in settings.pinchGesture }) { [weak self] _ in self?.applyGesture() }
        observe({ [settings] in settings.showsDockIcon }) { [weak self] _ in self?.applyActivationPolicy() }
        observe({ [settings] in settings.pageCapacity }) { [weak self] capacity in
            guard let self else { return }
            self.layoutStore.update { $0.normalize(capacity: capacity) }
            self.scheduleIconSync()
        }
        observe({ [settings] in [settings.iconScale, settings.labelFontSize, settings.showsLabels ? 1 : 0, settings.compactMargins ? 1 : 0] }) { [weak self] _ in
            self?.scheduleIconSync()
        }
        observe({ [settings] in settings.iconAppearance }) { [weak self] _ in self?.syncIcons() }
        observe({ [settings] in "\(settings.backgroundStyle.rawValue)|\(settings.blurRadius)|\(settings.dimming)|\(settings.customImagePath ?? "")|\(settings.presetWallpaper)" }) { [weak self] _ in
            self?.scheduleBackgroundRefresh()
        }
        observe({ [settings] in settings.hiddenApps }) { [weak self] hidden in
            guard let self else { return }
            self.layoutStore.update { $0.reconcile(installed: self.catalog.entries.map(\.id), hidden: hidden, capacity: self.settings.pageCapacity) }
            self.model.rebuildSearchIndex()
        }
        observe({ [settings] in settings.extraDirectories }) { [weak self] extra in
            guard let self else { return }
            self.catalog.setDirectories(extra: extra)
            Task { await self.catalog.rescan() }
        }
    }

    private func observeWorkspace() {
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            let pid = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier
            MainActor.assumeIsolated {
                if let pid { self?.model.preview.purge(pid: pid) }
            }
        }
        // 螢幕配置或系統外觀改變：圖示尺寸/深淺與背景都可能要重算
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.scheduleIconSync()
                self?.wallpapers.invalidate()
                self?.controller.invalidateBackground()
                self?.controller.prewarmBackgrounds()
            }
        }
        DistributedNotificationCenter.default().addObserver(forName: Notification.Name("AppleInterfaceThemeChangedNotification"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                if self?.settings.iconAppearance == .system { self?.syncIcons() }
            }
        }
    }

    private func applyActivationPolicy() {
        NSApp.setActivationPolicy(settings.showsDockIcon ? .regular : .accessory)
    }

    // MARK: - 圖示與背景

    /// 圖示要畫成的像素尺寸：該螢幕上的圖示顯示尺寸 × 該螢幕倍率。
    /// 刻意不再預留放大餘量、也不取 8 的倍數：靜態格線上貼圖大小要與實際顯示像素 1:1，
    /// 否則 Core Animation 以雙線性縮小會讓圖示邊緣發糊；拖曳中圖示放大 1.12 倍時只是略為放大。
    /// 也不取「所有螢幕的最大值」：Retina 筆電接 1x 外接螢幕時，1x 那邊會被縮小約一半而發糊；
    /// 改為依「這次要顯示的螢幕」決定，換螢幕時由 `syncIcons(for:)` 重載（磁碟快取鍵含像素尺寸，重載很快）。
    private func iconPixelSize(for screen: NSScreen) -> Int {
        // 容器要與 LaunchpadWindowController.layout 實際擺放的內容區一致（不蓋 Dock/選單列時是 visibleFrame），
        // 否則算出的 iconSize 會差幾個點，貼圖就不再與顯示像素 1:1
        let container = settings.coversDock ? screen.frame.size : screen.visibleFrame.size
        let metrics = GridMetrics(
            containerSize: container, columns: settings.columns, rows: settings.rows,
            iconScale: settings.iconScale, labelFontSize: settings.labelFontSize,
            showsLabels: settings.showsLabels, compact: settings.compactMargins,
            topInset: settings.coversDock ? screen.safeAreaInsets.top : 0
        )
        return max(32, Int((metrics.iconSize * screen.backingScaleFactor).rounded()))
    }

    private var iconsAreDark: Bool {
        switch settings.iconAppearance {
        case .system: NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        case .light: false
        case .dark: true
        }
    }

    /// 以指定螢幕（預設為下次會顯示的螢幕）的尺寸同步圖示。
    private func syncIcons(for screen: NSScreen? = nil) {
        icons.sync(entries: catalog.entries, pixelSize: iconPixelSize(for: screen ?? targetScreen()), dark: iconsAreDark)
    }

    /// 顯示前確認圖示尺寸對得上要顯示的螢幕；對不上（換到不同倍率／解析度的螢幕）才重載。
    /// 先比尺寸再決定要不要 sync：sync 會逐 App 算快取鍵，不放在每次打開的路徑上（show 同步 < 3ms 的紅線）。
    private func ensureIconsMatch(_ screen: NSScreen) {
        guard icons.pixelSize != iconPixelSize(for: screen) else { return }
        syncIcons(for: screen)
    }

    /// 拖動滑桿時設定連續變化，等停下來再重畫圖示。
    private func scheduleIconSync() {
        iconSyncTask?.cancel()
        iconSyncTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            self?.syncIcons()
        }
    }

    private func scheduleBackgroundRefresh() {
        backgroundTask?.cancel()
        backgroundTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard let self, !Task.isCancelled else { return }
            self.wallpapers.invalidate()
            self.controller.invalidateBackground()
            self.controller.prewarmBackgrounds()
        }
    }
}
