//
//  LaunchpadModel.swift
//  Liftoff
//
//  啟動台畫面的狀態與互動邏輯（搜尋、鍵盤選取、資料夾、拖曳排序、右鍵操作）。
//  畫面（SwiftUI）只負責呈現與把使用者動作轉給這裡；所有版面修改透過 LayoutStore 完成並自動存檔。
//
//  觀察粒度：頻繁變動的狀態各自獨立成物件——翻頁位移（PagerState）、拖曳游標位置（DragSession）、
//  預覽（WindowPreviewModel）——避免游標每動一下就讓整個格線重算。
//

import AppKit
import Observation
import SwiftUI

/// 拖曳中的狀態。游標位置每個滑鼠事件都會變，只有浮動圖示依賴它。
@Observable
final class DragSession {
    let item: LayoutItem
    /// 游標位置（根座標）
    var location: CGPoint
    /// 按下時游標相對於圖示中心的偏移（拖曳時圖示維持在手指抓住的位置）
    let grabOffset: CGSize
    /// 停在某圖示中心夠久、放開會合併成資料夾的目標
    var mergeTargetID: String?
    /// 從哪個資料夾拖出（仍在資料夾面板內時不為 nil）
    var folderID: UUID?
    /// 開始拖曳前的版面，按 Esc 取消時還原
    let snapshot: Layout

    var itemID: String { item.id }

    init(item: LayoutItem, location: CGPoint, grabOffset: CGSize, folderID: UUID?, snapshot: Layout) {
        self.item = item
        self.location = location
        self.grabOffset = grabOffset
        self.folderID = folderID
        self.snapshot = snapshot
    }

    /// 被拖曳圖示的中心（用來判斷落在哪一格）
    var iconCenter: CGPoint {
        CGPoint(x: location.x - grabOffset.width, y: location.y - grabOffset.height)
    }
}

/// 需要使用者確認的動作。
enum Confirmation: Identifiable, Equatable {
    case uninstall(appID: String)

    var id: String {
        switch self {
        case .uninstall(let appID): "uninstall:" + appID
        }
    }
}

/// 啟動台收起的原因（決定動畫快慢、是否把焦點還給原本的 App）。
enum DismissReason {
    case user
    case launched
    case switchedWindow
    case settings
}

@Observable
final class LaunchpadModel {
    let settings: AppSettings
    let catalog: AppCatalog
    let layoutStore: LayoutStore
    let icons: IconStore
    let running: RunningApps
    let usage: UsageStore
    let pager = PagerState()
    let folderPager = PagerState()
    let preview = WindowPreviewModel()

    // MARK: 畫面狀態

    /// 啟動台可用區域大小（由畫面回報）
    var containerSize = CGSize(width: 1440, height: 900)
    /// 內容區上方被瀏海遮住的高度（控制器依螢幕與「覆蓋選單列」設定回報）
    var topInset: CGFloat = 0
    /// 背景偏亮時 App 名稱改用深色字
    var backgroundIsLight = false
    /// 目前是否顯示中（控制器設定；隱藏時不處理 hover 等事件）
    var isShown = false

    var searchText = "" {
        didSet { if searchText != oldValue { searchChanged() } }
    }
    /// 搜尋結果：App 與標題相符的執行中視窗，依相關度混排
    private(set) var searchResults: [LayoutItem] = []
    /// 要求搜尋框取得焦點（每次 +1 觸發）
    var focusRequest = 0

    /// 鍵盤選取（顯示頁面中的位置）；資料夾開啟時為資料夾內索引
    var selection: ItemPosition?
    var folderSelection: Int?

    var openFolderID: UUID?
    var isRenamingFolder = false
    var confirmation: Confirmation?
    /// 「徹底移除」確認框的內容（殘留檔清單與勾選）
    var uninstallPlan: UninstallPlan?
    /// 短暫提示訊息
    var toast: String?

    /// 拖曳中（nil 表示沒有拖曳）
    var drag: DragSession?
    /// 按下中的格子（顯示按下效果）
    var pressedID: String?

    /// 按下但尚未放開（面板層的滑鼠處理用）
    @ObservationIgnored var press: PressState?
    /// 在格線空白處按下的位置（按住拖動 = 滑鼠翻頁；沒拖動就放開 = 點空白處）
    @ObservationIgnored var backgroundPress: CGPoint?
    /// 上一個拖動事件的 x（以位置差計算位移：合成事件沒有 deltaX）
    @ObservationIgnored var backgroundLastX: CGFloat = 0
    /// 游標目前停在哪個 App 上（視窗預覽用）
    @ObservationIgnored var hoveredID: String?

    @ObservationIgnored private var searchIndex: SearchIndex?
    /// 執行中視窗的標題索引：每次打開時在背景拍一次快照，收起後釋放
    @ObservationIgnored private var windowIndex: WindowSearchIndex?
    /// 快照世代：快照還在背景跑時又收起/重開，舊的結果不能蓋掉新的
    @ObservationIgnored private var windowSnapshotGeneration = 0
    /// 快照正在背景拍攝中（避免每個按鍵都再拍一次）
    @ObservationIgnored private var isCapturingWindows = false
    @ObservationIgnored private var mergeTask: Task<Void, Never>?
    @ObservationIgnored private var thumbnailPurgeTask: Task<Void, Never>?
    @ObservationIgnored private var mergeCandidate: String?
    @ObservationIgnored private var edgeTask: Task<Void, Never>?
    @ObservationIgnored private var reorderTask: Task<Void, Never>?
    @ObservationIgnored private var pendingReorder: ItemPosition?
    /// 自我測試用：記錄要開啟的 App 但不真的開（避免測試過程開啟使用者的 App）
    @ObservationIgnored var suppressLaunches = false
    @ObservationIgnored private(set) var lastLaunchRequest: String?
    @ObservationIgnored private var edgeDirection = 0
    @ObservationIgnored private var toastTask: Task<Void, Never>?
    /// 長按計時：按住不動超過門檻就觸發「徹底移除」
    @ObservationIgnored var longPressTask: Task<Void, Never>?

    /// 請控制器收起啟動台
    @ObservationIgnored var requestDismiss: ((DismissReason) -> Void)?
    /// 請控制器打開設定視窗
    @ObservationIgnored var requestSettings: (() -> Void)?

    init(settings: AppSettings, catalog: AppCatalog, layoutStore: LayoutStore, icons: IconStore, running: RunningApps, usage: UsageStore) {
        self.settings = settings
        self.catalog = catalog
        self.layoutStore = layoutStore
        self.icons = icons
        self.running = running
        self.usage = usage
    }

    // MARK: - 衍生資料

    var capacity: Int { settings.pageCapacity }
    var isSearching: Bool { !searchText.trimmingCharacters(in: .whitespaces).isEmpty }

    var metrics: GridMetrics {
        GridMetrics(
            containerSize: containerSize, columns: settings.columns, rows: settings.rows,
            iconScale: settings.iconScale, labelFontSize: settings.labelFontSize,
            showsLabels: settings.showsLabels, compact: settings.compactMargins,
            topInset: topInset
        )
    }

    /// 畫面上顯示的頁面：搜尋時是搜尋結果分頁，否則是版面。
    var displayPages: [[LayoutItem]] {
        if isSearching { return searchResults.chunked(into: capacity) }
        return layoutStore.layout.pages
    }

    /// 所有格子（身分固定）：資料夾 + 每個可見 App 各一格。
    /// 搜尋、拖曳、翻頁都只改變格子的「位置與可見度」，不建立或銷毀 view——這是打字搜尋與清除搜尋能在一幀內完成的關鍵。
    /// 例外是搜尋到的視窗：只在搜尋中、有相符時才多出幾格（數量少，建立成本可忽略）。
    var cellItems: [LayoutItem] {
        let layout = layoutStore.layout
        var items: [LayoutItem] = []
        for page in layout.pages {
            for item in page where item.folder != nil { items.append(item) }
        }
        let inLayout = Set(layout.allAppIDs)
        for entry in catalog.entries where inLayout.contains(entry.id) {
            items.append(.app(entry.id))
        }
        if isSearching {
            for item in searchResults { if case .window = item { items.append(item) } }
        }
        return items
    }

    /// 目前畫面上每個項目的位置（頁、格）；不在畫面上的（資料夾內的 App、不符合搜尋的）沒有位置。
    var placements: [String: ItemPosition] {
        var result: [String: ItemPosition] = [:]
        for (pageIndex, page) in displayPages.enumerated() {
            for (index, item) in page.enumerated() { result[item.id] = ItemPosition(page: pageIndex, index: index) }
        }
        return result
    }

    /// 項目顯示名稱。
    func title(for item: LayoutItem) -> String {
        switch item {
        case .app(let id): catalog.entry(id)?.name ?? (id as NSString).lastPathComponent
        case .folder(let folder): folder.name
        case .window(let hit): hit.title
        }
    }

    var openFolder: FolderData? {
        openFolderID.flatMap { layoutStore.layout.folder(id: $0) }
    }

    /// App 名稱是否用深色字
    var labelsAreDark: Bool {
        switch settings.labelColor {
        case .auto: backgroundIsLight
        case .light: false
        case .dark: true
        }
    }

    /// 資料夾面板每頁欄數與列數
    /// 資料夾一頁最多放幾個 App（超過才需要翻頁；自我測試用來找多頁資料夾）
    var folderCapacityLimit: Int { folderMaxColumns * 3 }
    /// 資料夾面板最多幾欄（每頁最多 3 列，超過才翻頁）
    private var folderMaxColumns: Int { max(3, min(settings.columns, 7)) }
    /// 依開啟中資料夾的 App 數決定欄數：面板貼合內容，3 個 App 就只有 3 格寬（至少 3 欄，標題才放得下）
    var folderColumns: Int {
        let count = openFolder?.apps.count ?? 0
        return max(3, min(count, folderMaxColumns))
    }
    /// 列數同樣貼合內容（1…3 列）
    var folderRows: Int {
        let count = openFolder?.apps.count ?? 0
        return max(1, min(3, (count + folderColumns - 1) / folderColumns))
    }
    var folderCapacity: Int { folderColumns * folderRows }

    // MARK: - 顯示週期

    /// 啟動台即將顯示：重設暫態、還原頁碼、要求搜尋框焦點。
    func prepareForShow() {
        isShown = true
        thumbnailPurgeTask?.cancel()
        isCapturingWindows = false
        // 正常情況下 resetTransientState 已在上次收起後做完；這裡只補做「可能被改過」的部分（例如收起期間 App 清單變動使頁數變少）
        let pageCount = displayPages.count
        if pager.page >= pageCount { pager.go(to: pageCount - 1, pageCount: pageCount, animated: false) }
        if isRenamingFolder || openFolderID != nil || !searchText.isEmpty { resetTransientState() }
    }

    /// 清除暫態（搜尋、選取、資料夾、預覽、頁面位移）。在收起「之後」執行：
    /// 畫面在看不見時就先更新好，下次打開的第一幀就是乾淨的狀態，打開時不必等 SwiftUI 重新排版。
    func resetTransientState() {
        searchText = ""
        selection = nil
        folderSelection = nil
        if openFolderID != nil { openFolderID = nil }
        isRenamingFolder = false
        confirmation = nil
        uninstallPlan = nil
        longPressTask?.cancel()
        drag = nil
        press = nil
        pressedID = nil
        hoveredID = nil
        preview.hide()
        let pageCount = displayPages.count
        if !settings.remembersPage { pager.go(to: 0, pageCount: pageCount, animated: false) }
        if pager.page >= pageCount { pager.go(to: pageCount - 1, pageCount: pageCount, animated: false) }
        pager.offset = 0
    }

    /// 啟動台已收起。
    func didHide() {
        isShown = false
        // 視窗快照只在顯示期間有意義（視窗隨時會開關），收起就釋放
        windowSnapshotGeneration += 1
        windowIndex = nil
        isCapturingWindows = false
        preview.hide()
        if drag != nil { cancelDrag() }
        mergeTask?.cancel()
        edgeTask?.cancel()
        // 收起 60 秒後清空視窗縮圖快取（最多 60 張、約 50MB）：短時間內再打開仍可立即顯示舊縮圖，
        // 長時間閒置則不佔記憶體
        thumbnailPurgeTask?.cancel()
        thumbnailPurgeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(60))
            guard let self, !Task.isCancelled, !self.isShown else { return }
            self.preview.purgeAll()
        }
    }

    // MARK: - 搜尋

    /// App 清單變動時重建搜尋索引。
    func rebuildSearchIndex() {
        let entries = catalog.entries.filter { !settings.hiddenApps.contains($0.id) }
        searchIndex = SearchIndex(apps: entries)
        if isSearching { searchChanged() }
    }

    private func searchChanged() {
        if openFolderID != nil { closeFolder() }
        preview.hide()
        if isSearching {
            if searchIndex == nil { rebuildSearchIndex() }
            if windowIndex == nil, !isCapturingWindows { refreshWindowSnapshot() }
            searchResults = mergedResults(for: searchText)
            selection = searchResults.isEmpty ? nil : ItemPosition(page: 0, index: 0)
            pager.go(to: 0, pageCount: max(1, displayPages.count), animated: false)
        } else {
            searchResults = []
            selection = nil
        }
    }

    /// App 與視窗結果依分數混排：App 分數已含使用頻率加權，視窗分數已打折（同樣相符時 App 在前）。
    private func mergedResults(for query: String) -> [LayoutItem] {
        let apps = searchIndex?.scored(query, boost: usage.boosts()) ?? []
        let windows = windowIndex?.search(query).prefix(Self.maxWindowResults) ?? []
        guard !windows.isEmpty else { return apps.map { .app($0.id) } }
        var merged: [(item: LayoutItem, score: Double)] = apps.map { (.app($0.id), $0.score) }
        merged += windows.map { (.window($0.hit), $0.score) }
        // 兩邊各自已排好序：穩定合併，同分時 App 在前
        var result: [LayoutItem] = []
        result.reserveCapacity(merged.count)
        var a = 0, w = apps.count
        while a < apps.count || w < merged.count {
            if w >= merged.count || (a < apps.count && merged[a].score >= merged[w].score) {
                result.append(merged[a].item); a += 1
            } else {
                result.append(merged[w].item); w += 1
            }
        }
        return result
    }

    /// 搜尋結果最多列出幾個視窗（避免一個常見字把整頁塞滿視窗）
    private static let maxWindowResults = 12

    /// 在背景拍下執行中 App 的視窗標題：每次打開後「開始搜尋時」拍一次，主執行緒只組 pid 對照表。
    /// 不在 show() 時拍：實測背景的 CGWindowList 會和 orderFront 搶 WindowServer，打開的同步時間從 ~3ms 變 5–50ms。
    /// 視窗比對至少要 2 個字，第一個字打下去到第二個字之間就足夠在背景拍完（~5ms）。
    private func refreshWindowSnapshot() {
        windowSnapshotGeneration += 1
        let generation = windowSnapshotGeneration
        // 收起動畫期間（searchText 還沒清掉）也可能走到這裡，那時拍的快照用不到
        guard isShown else { return }
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let hidden = settings.hiddenApps
        var apps: [pid_t: (id: String, name: String)] = [:]
        // 使用者在啟動台隱藏的 App，它的視窗也不列（與 App 搜尋一致）
        for (pid, id) in running.idsByPID where pid != ownPID && !hidden.contains(id) {
            apps[pid] = (id, catalog.entry(id)?.name ?? id)
        }
        guard !apps.isEmpty else { return }
        isCapturingWindows = true
        Task.detached(priority: .userInitiated) { [apps] in
            let start = ContinuousClock.now
            let hits = WindowSnapshot.capture(apps: apps)
            Log.perf.debug("視窗快照：\(apps.count) 個 App、\(hits.count) 個視窗，\(milliseconds(since: start), format: .fixed(precision: 2))ms")
            await MainActor.run { [weak self] in
                guard let self, self.windowSnapshotGeneration == generation else { return }
                self.isCapturingWindows = false
                guard self.isShown else { return }
                let index = WindowSearchIndex(hits: hits)
                self.windowIndex = index
                // 快照比使用者打字慢到時，把視窗結果補進目前的結果。只換結果、不走 searchChanged：
                // 那會關資料夾、收預覽、把選取與頁碼歸零，打斷使用者在這段時間做的事
                guard self.isSearching, !index.search(self.searchText).isEmpty else { return }
                self.searchResults = self.mergedResults(for: self.searchText)
                if let selection = self.selection,
                   !self.displayPages.indices.contains(selection.page) || !self.displayPages[selection.page].indices.contains(selection.index) {
                    self.selection = ItemPosition(page: 0, index: 0)
                }
            }
        }
    }

    // MARK: - 開啟

    /// 點擊項目：App 直接開啟，資料夾展開。
    func activate(_ item: LayoutItem) {
        switch item {
        case .app(let id): launch(id)
        case .folder(let folder): openFolder(folder.id)
        case .window(let hit): switchToWindow(hit)
        }
    }

    /// 切換到搜尋到的視窗：先收起啟動台，再在背景針對那個 App 取得視窗元素（AX，可取消最小化、可跨桌面）後前置。
    /// 視窗已經關掉時退回啟用整個 App。
    func switchToWindow(_ hit: WindowHit) {
        if suppressLaunches {
            lastLaunchRequest = LayoutItem.window(hit).id
            return
        }
        usage.recordLaunch(hit.appID)
        requestDismiss?(.switchedWindow)
        Task.detached(priority: .userInitiated) {
            let window = WindowEnumerator.windows(for: hit.pid, includeOtherSpaces: true).first { $0.id == hit.windowID }
            await MainActor.run { [weak self] in
                if let window {
                    WindowActions.focus(window)
                } else if let entry = self?.catalog.entry(hit.appID) {
                    // 視窗已經關掉：改為帶出整個 App。不用 NSRunningApplication.activate()——
                    // 協作式啟用會拒絕背景 agent 搶焦點，openApplication 對執行中的 App 就是帶到前景
                    AppActions.open(entry)
                }
            }
        }
    }

    func launch(_ id: String) {
        guard let entry = catalog.entry(id) else { return }
        if suppressLaunches {
            lastLaunchRequest = id
            return
        }
        usage.recordLaunch(id)
        requestDismiss?(.launched)
        AppActions.open(entry)
    }

    func openFolder(_ id: UUID) {
        preview.hide()
        folderPager.go(to: 0, pageCount: 1, animated: false)
        withAnimation(.smooth(duration: 0.3)) {
            openFolderID = id
            folderSelection = nil
            isRenamingFolder = false
        }
    }

    func closeFolder() {
        guard openFolderID != nil else { return }
        preview.hide()
        withAnimation(.smooth(duration: 0.24)) {
            openFolderID = nil
            isRenamingFolder = false
            folderSelection = nil
        }
    }

    /// 點擊空白處：資料夾開著就關資料夾，否則收起啟動台（與經典啟動台相同）。
    func backgroundClicked() {
        if confirmation != nil { confirmation = nil; return }
        if openFolderID != nil { closeFolder(); return }
        requestDismiss?(.user)
    }

    // MARK: - 右鍵操作

    func hideApp(_ id: String) {
        settings.hiddenApps.insert(id)
        withAnimation(.smooth(duration: 0.25)) {
            layoutStore.update { $0.reconcile(installed: catalog.entries.map(\.id), hidden: settings.hiddenApps, capacity: capacity) }
        }
        rebuildSearchIndex()
        showToast(String(localized: "已隱藏，可在「設定 › 佈局」恢復"))
    }

    /// 把 App 移出資料夾，放在資料夾後面。
    func removeFromFolder(_ appID: String, folderID: UUID) {
        withAnimation(.smooth(duration: 0.25)) {
            layoutStore.update { layout in
                guard let position = layout.position(of: LayoutItem.folderKey(folderID)) else { return }
                layout.removeApp(appID, fromFolder: folderID)
                layout.insert(.app(appID), at: ItemPosition(page: position.page, index: position.index + 1), capacity: capacity)
            }
        }
        if openFolder == nil { openFolderID = nil }
    }

    func dissolveFolder(_ folderID: UUID) {
        if openFolderID == folderID { closeFolder() }
        withAnimation(.smooth(duration: 0.25)) {
            layoutStore.update { $0.dissolveFolder(folderID, capacity: capacity) }
        }
    }

    func renameFolder(_ folderID: UUID, to name: String) {
        layoutStore.update { $0.renameFolder(folderID, to: name) }
    }

    /// 開啟「徹底移除」確認框，並在背景掃描殘留檔。系統 App 不允許。
    func requestUninstall(_ appID: String) {
        guard let entry = catalog.entry(appID) else { return }
        guard !entry.isSystemApp else { return showToast(String(localized: "系統 App 無法移除")) }
        preview.hide()
        let plan = UninstallPlan(appID: appID)
        uninstallPlan = plan
        withAnimation(.smooth(duration: 0.2)) { confirmation = .uninstall(appID: appID) }
        Task {
            // 列舉與計算大小是磁碟 I/O，丟到背景，避免卡住主執行緒
            let result = await Task.detached(priority: .userInitiated) { Uninstaller.scan(entry) }.value
            plan.leftovers = result.files
            plan.selected = result.preselected
            plan.appSize = result.appSize
            plan.isScanning = false
        }
    }

    /// 確認移除：先結束執行中的 App，再把 App 本體與勾選的殘留檔移到垃圾桶。
    func confirmUninstall() {
        guard let plan = uninstallPlan, let entry = catalog.entry(plan.appID), !plan.isRemoving else { return }
        plan.isRemoving = true
        let urls = plan.leftovers.map(\.url).filter { plan.selected.contains($0) }
        Task {
            if let app = running.application(for: entry.id) {
                app.terminate()
                // 等 App 收尾（最多 3 秒），否則它可能在被移除後又把設定檔寫回去
                for _ in 0..<30 where !app.isTerminated { try? await Task.sleep(for: .milliseconds(100)) }
                if !app.isTerminated { app.forceTerminate() }
            }
            if let error = await AppActions.moveToTrash(entry) {
                plan.isRemoving = false
                return showToast(String(localized: "無法移除：\(error)"))
            }
            let failed = await Task.detached { Uninstaller.trash(urls) }.value
            confirmation = nil
            uninstallPlan = nil
            if failed.isEmpty {
                showToast(String(localized: "已徹底移除「\(entry.name)」"))
            } else {
                showToast(String(localized: "已移除「\(entry.name)」；無法移除的殘留檔：\(failed.count)"))
            }
            await catalog.rescan()
        }
    }

    func showToast(_ text: String) {
        toastTask?.cancel()
        withAnimation(.smooth(duration: 0.2)) { toast = text }
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.4))
            guard !Task.isCancelled else { return }
            withAnimation(.smooth(duration: 0.3)) { self?.toast = nil }
        }
    }

    // MARK: - 視窗預覽

    /// 游標進出圖示。
    /// - Parameters:
    ///   - item: 圖示對應的項目
    ///   - inside: 進入或離開
    ///   - anchor: 圖示外框（根座標）
    func hover(_ item: LayoutItem, inside: Bool, anchor: CGRect) {
        guard case .app(let id) = item else { return }
        if !inside {
            preview.hoverEnded(appID: id)
            return
        }
        guard isShown, settings.windowPreview, drag == nil, confirmation == nil,
              let app = running.application(for: id), let entry = catalog.entry(id) else {
            preview.hoverEnded(appID: id)
            return
        }
        preview.hoverBegan(appID: id, app: app, name: entry.name, anchor: anchor, delay: settings.previewDelay)
    }

    // MARK: - 鍵盤

    /// 處理按鍵；回傳 false 表示交給搜尋框（一般文字輸入）。
    func handleKeyDown(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags.contains(.command) {
            switch event.charactersIgnoringModifiers?.lowercased() {
            case ",": requestSettings?(); return true
            case "w", "q": requestDismiss?(.user); return true
            case "f": focusRequest += 1; return true
            default: break
            }
            switch Int(event.keyCode) {
            case KeyCode.left: pager.go(to: pager.page - 1, pageCount: displayPages.count); return true
            case KeyCode.right: pager.go(to: pager.page + 1, pageCount: displayPages.count); return true
            default: return false
            }
        }

        switch Int(event.keyCode) {
        case KeyCode.escape:
            handleEscape()
            return true
        case KeyCode.returnKey, KeyCode.enter:
            if isRenamingFolder { return false }
            activateSelection()
            return true
        case KeyCode.left: moveSelection(dx: -1, dy: 0); return true
        case KeyCode.right: moveSelection(dx: 1, dy: 0); return true
        case KeyCode.up: moveSelection(dx: 0, dy: -1); return true
        case KeyCode.down: moveSelection(dx: 0, dy: 1); return true
        case KeyCode.pageUp: pager.go(to: pager.page - 1, pageCount: displayPages.count); return true
        case KeyCode.pageDown: pager.go(to: pager.page + 1, pageCount: displayPages.count); return true
        case KeyCode.tab:
            let delta = flags.contains(.shift) ? -1 : 1
            pager.go(to: pager.page + delta, pageCount: displayPages.count)
            return true
        case KeyCode.space:
            // 搜尋框有字時空白鍵是輸入的一部分；沒字時用來預覽選取的 App
            guard !isSearching, let selection, openFolderID == nil else { return false }
            previewSelection(selection)
            return true
        default:
            return false
        }
    }

    func handleEscape() {
        if drag != nil { cancelDrag(); return }
        if confirmation != nil { confirmation = nil; return }
        if preview.isVisible { preview.hide(); return }
        if isRenamingFolder { isRenamingFolder = false; return }
        if openFolderID != nil { closeFolder(); return }
        if !searchText.isEmpty { searchText = ""; return }
        requestDismiss?(.user)
    }

    private func activateSelection() {
        if let folder = openFolder {
            if let index = folderSelection, folder.apps.indices.contains(index) { launch(folder.apps[index]) }
            return
        }
        let pages = displayPages
        if let selection, pages.indices.contains(selection.page), pages[selection.page].indices.contains(selection.index) {
            activate(pages[selection.page][selection.index])
        } else if isSearching, let first = searchResults.first {
            activate(first)
        }
    }

    /// 方向鍵移動選取；左右跨頁時自動翻頁。
    private func moveSelection(dx: Int, dy: Int) {
        preview.hide()
        if let folder = openFolder {
            let count = folder.apps.count
            guard count > 0 else { return }
            let current = folderSelection ?? -1
            var next = current < 0 ? 0 : current + dx + dy * folderColumns
            next = max(0, min(count - 1, next))
            folderSelection = next
            folderPager.go(to: next / folderCapacity, pageCount: (count + folderCapacity - 1) / folderCapacity)
            return
        }
        let pages = displayPages
        guard !pages.isEmpty else { return }
        guard let current = selection, pages.indices.contains(current.page) else {
            selection = ItemPosition(page: min(pager.page, pages.count - 1), index: 0)
            return
        }
        let columns = settings.columns
        var page = current.page
        var index = current.index
        if dx != 0 {
            index += dx
            if index < 0 {
                if page > 0 { page -= 1; index = pages[page].count - 1 } else { index = 0 }
            } else if index >= pages[page].count {
                if page < pages.count - 1 { page += 1; index = 0 } else { index = pages[page].count - 1 }
            }
        }
        if dy != 0 {
            let next = index + dy * columns
            if next >= 0, next < pages[page].count { index = next }
        }
        selection = ItemPosition(page: page, index: index)
        if page != pager.page { pager.go(to: page, pageCount: pages.count) }
    }

    private func previewSelection(_ position: ItemPosition) {
        let pages = displayPages
        guard pages.indices.contains(position.page), pages[position.page].indices.contains(position.index),
              case .app(let id) = pages[position.page][position.index],
              let app = running.application(for: id), let entry = catalog.entry(id) else {
            NSSound.beep()
            return
        }
        let frame = metrics.cellFrame(position.index)
        preview.showNow(appID: id, app: app, name: entry.name, anchor: frame)
    }

    // MARK: - 拖曳排序

    /// 拖曳手勢更新。
    /// - Parameters:
    ///   - item: 被拖曳的項目
    ///   - folderID: 從哪個資料夾拖出（主格線為 nil）
    ///   - location: 游標目前位置（根座標）
    ///   - start: 按下時的位置
    ///   - iconCenter: 按下時圖示中心（根座標）
    func dragChanged(item: LayoutItem, folderID: UUID?, location: CGPoint, start: CGPoint, iconCenter: CGPoint) {
        guard !isSearching else { return }
        if drag == nil {
            guard hypot(location.x - start.x, location.y - start.y) > 5 else { return }
            preview.hide()
            selection = nil
            drag = DragSession(
                item: item, location: location,
                grabOffset: CGSize(width: start.x - iconCenter.x, height: start.y - iconCenter.y),
                folderID: folderID, snapshot: layoutStore.layout
            )
        }
        guard let drag else { return }
        drag.location = location
        updateDragTarget(drag)
    }

    func dragEnded() {
        guard let drag else { return }
        mergeTask?.cancel()
        edgeTask?.cancel()
        reorderTask?.cancel()
        edgeDirection = 0
        // 放開時游標仍停在等待換位的空隙：直接換到那裡（使用者不必等換位動畫才放開）
        if let pending = pendingReorder, drag.mergeTargetID == nil {
            layoutStore.update { $0.move(itemID: drag.itemID, to: pending, capacity: capacity) }
        }
        pendingReorder = nil
        if let target = drag.mergeTargetID, case .app(let appID) = drag.item {
            let name = FolderNaming.name(target: catalog.entry(target), dragged: catalog.entry(appID))
            withAnimation(.smooth(duration: 0.3)) {
                layoutStore.update { _ = $0.merge(appID: appID, into: target, folderName: name) }
            }
        }
        withAnimation(.smooth(duration: 0.3)) {
            layoutStore.update { $0.normalize(capacity: capacity) }
            self.drag = nil
        }
        let pageCount = displayPages.count
        if pager.page >= pageCount { pager.go(to: pageCount - 1, pageCount: pageCount) }
    }

    func cancelDrag() {
        guard let drag else { return }
        mergeTask?.cancel()
        edgeTask?.cancel()
        reorderTask?.cancel()
        pendingReorder = nil
        edgeDirection = 0
        // 取消後放開滑鼠不能被當成「點擊」而開啟 App
        press = nil
        pressedID = nil
        withAnimation(.smooth(duration: 0.3)) {
            layoutStore.replace(with: drag.snapshot)
            self.drag = nil
        }
    }

    private func updateDragTarget(_ drag: DragSession) {
        // 在資料夾面板內：資料夾內排序；拖出面板就把 App 移出資料夾，改在主格線上繼續拖
        if let folderID = drag.folderID, let folder = openFolder, folder.id == folderID, case .app(let appID) = drag.item {
            let panel = folderPanelFrame(for: folder)
            if panel.insetBy(dx: -24, dy: -24).contains(drag.location) {
                let local = CGPoint(x: drag.iconCenter.x - panel.minX, y: drag.iconCenter.y - panel.minY)
                let folderMetrics = folderGridMetrics
                let pageOffset = folderPager.page * folderCapacity
                let index = pageOffset + folderMetrics.insertionIndex(at: local, count: folderCapacity)
                let target = min(index, folder.apps.count - 1)
                if folder.apps.firstIndex(of: appID) != target {
                    withAnimation(.snappy(duration: 0.25)) {
                        layoutStore.update { $0.moveInFolder(folderID, appID: appID, to: target) }
                    }
                }
                return
            }
            // 移出資料夾：放到資料夾在主格線上的位置之後
            drag.folderID = nil
            withAnimation(.smooth(duration: 0.25)) {
                openFolderID = nil
                layoutStore.update { layout in
                    guard let position = layout.position(of: LayoutItem.folderKey(folderID)) else { return }
                    layout.removeApp(appID, fromFolder: folderID)
                    layout.insert(.app(appID), at: ItemPosition(page: position.page, index: position.index + 1), capacity: capacity)
                }
            }
            if let position = layoutStore.layout.position(of: appID), position.page != pager.page {
                pager.go(to: position.page, pageCount: layoutStore.layout.pages.count)
            }
            return
        }

        let metrics = metrics
        updateEdgeFlip(drag, metrics: metrics)

        let pages = layoutStore.layout.pages
        let page = pager.page
        let pageItems = pages.indices.contains(page) ? pages[page] : []
        let center = drag.iconCenter
        let hovered = metrics.insertionIndex(at: center, count: pageItems.count)

        // 停在另一個圖示中心：準備合併成資料夾（資料夾本身不能再放進資料夾）
        if drag.item.appID != nil, hovered < pageItems.count, pageItems[hovered].id != drag.itemID,
           metrics.isOverIconCenter(center, index: hovered) {
            let targetID = pageItems[hovered].id
            pendingReorder = nil
            reorderTask?.cancel()
            if mergeCandidate != targetID {
                mergeCandidate = targetID
                mergeTask?.cancel()
                mergeTask = Task { [weak self, weak drag] in
                    try? await Task.sleep(for: .milliseconds(320))
                    guard let self, let drag, !Task.isCancelled, self.mergeCandidate == targetID else { return }
                    withAnimation(.smooth(duration: 0.2)) { drag.mergeTargetID = targetID }
                }
            }
            return
        }
        if mergeCandidate != nil {
            mergeCandidate = nil
            mergeTask?.cancel()
            if drag.mergeTargetID != nil { withAnimation(.smooth(duration: 0.2)) { drag.mergeTargetID = nil } }
        }

        // 插入：被拖曳的項目移到游標所在的格子（它自己就是畫面上的空位）。
        // 游標要在同一個空隙停留一下（150ms）才換位：快速掠過其他圖示時不會一路把它們擠開，
        // 使用者才能把圖示拖到「隔壁」App 上合併成資料夾（與經典啟動台手感一致）。
        let current = layoutStore.layout.position(of: drag.itemID)
        let maxIndex = current?.page == page ? max(pageItems.count - 1, 0) : pageItems.count
        let target = ItemPosition(page: page, index: min(hovered, maxIndex))
        guard current != target else {
            pendingReorder = nil
            reorderTask?.cancel()
            return
        }
        guard pendingReorder != target else { return }
        pendingReorder = target
        reorderTask?.cancel()
        reorderTask = Task { [weak self, weak drag] in
            try? await Task.sleep(for: .milliseconds(150))
            guard let self, let drag, !Task.isCancelled, self.pendingReorder == target, self.drag === drag else { return }
            self.pendingReorder = nil
            self.layoutStore.update { $0.move(itemID: drag.itemID, to: target, capacity: self.capacity) }
        }
    }

    /// 拖到螢幕左右邊緣停留：翻頁（持續停留會一直翻），最後一頁往右可新增空白頁。
    private func updateEdgeFlip(_ drag: DragSession, metrics: GridMetrics) {
        let edge: CGFloat = max(40, metrics.gridRect.minX * 0.6)
        let direction = drag.location.x < edge ? -1 : (drag.location.x > containerSize.width - edge ? 1 : 0)
        guard direction != edgeDirection else { return }
        edgeDirection = direction
        edgeTask?.cancel()
        guard direction != 0 else { return }
        edgeTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(650))
                guard let self, !Task.isCancelled, self.drag != nil else { return }
                let pages = self.layoutStore.layout.pages
                let target = self.pager.page + direction
                if target < 0 { return }
                if target >= pages.count {
                    // 往最後一頁之後拖：新增一頁（被拖的項目不是最後一頁唯一的項目時才有意義）
                    guard pages.last?.count ?? 0 > 1 || self.layoutStore.layout.position(of: drag.itemID)?.page != pages.count - 1 else { return }
                    self.layoutStore.update { $0.pages.append([]) }
                }
                self.pager.go(to: target, pageCount: self.layoutStore.layout.pages.count)
                self.updateDragTarget(drag)
            }
        }
    }

    // MARK: - 資料夾面板幾何

    /// 資料夾面板內格線（面板座標）。
    var folderGridMetrics: GridMetrics {
        let main = metrics
        let size = CGSize(
            width: main.cellSize.width * CGFloat(folderColumns) + FolderPanelStyle.padding * 2,
            height: main.cellSize.height * CGFloat(folderRows) + FolderPanelStyle.titleHeight + FolderPanelStyle.padding * 2
        )
        return GridMetrics.folder(panelSize: size, main: main, columns: folderColumns, rows: folderRows)
    }

    /// 資料夾面板外框（根座標，置中）。
    func folderPanelFrame(for folder: FolderData) -> CGRect {
        let size = folderGridMetrics.containerSize
        return CGRect(x: (containerSize.width - size.width) / 2, y: (containerSize.height - size.height) / 2,
                      width: size.width, height: size.height)
    }
}

/// 資料夾面板的固定尺寸。
nonisolated enum FolderPanelStyle {
    static let padding: CGFloat = 22
    static let titleHeight: CGFloat = 56
}

extension GridMetrics {
    /// 資料夾面板用的格線：格子大小與主畫面相同，格線從標題下方開始。
    nonisolated static func folder(panelSize: CGSize, main: GridMetrics, columns: Int, rows: Int) -> GridMetrics {
        GridMetrics(
            containerSize: panelSize, columns: columns, rows: rows, iconSize: main.iconSize,
            labelFontSize: main.labelFontSize, showsLabels: main.showsLabels,
            gridRect: CGRect(
                x: FolderPanelStyle.padding, y: FolderPanelStyle.titleHeight + FolderPanelStyle.padding,
                width: main.cellSize.width * CGFloat(columns), height: main.cellSize.height * CGFloat(rows)
            )
        )
    }
}

/// 常用虛擬鍵碼。
nonisolated enum KeyCode {
    static let returnKey = 36, tab = 48, space = 49, escape = 53, enter = 76
    static let left = 123, right = 124, down = 125, up = 126, pageUp = 116, pageDown = 121
}
