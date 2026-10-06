//
//  SelfTest.swift
//  Liftoff
//
//  端到端效能自我測試（以 `--selftest` 啟動參數觸發，正常使用不會執行）。
//  App 自己開關啟動台、翻頁、搜尋、開資料夾並量測：
//  - 顯示延遲：呼叫 show → 視窗上屏後的第一個 vsync
//  - 翻頁/顯示動畫的幀間隔（CADisplayLink 在主執行緒回呼；主執行緒卡住就會掉幀，能反映 SwiftUI 的負擔）
//  - 搜尋延遲、記憶體用量
//  並把各畫面存成 PNG、結果寫成 JSON：~/Library/Caches/com.firstfu.Liftoff/selftest/
//

import AppKit
import QuartzCore

enum SelfTest {
    static var isRequested: Bool { CommandLine.arguments.contains("--selftest") }

    struct FrameStats: Encodable {
        let frames: Int
        let averageMs: Double
        let worstMs: Double
        /// 超過 1.5 倍正常幀長的次數
        let hitches: Int
    }

    struct Report: Encodable {
        let date: Date
        let apps: Int
        let pages: Int
        let screen: String
        let refreshRate: Double
        let iconPixelSize: Int
        /// 版面實際顯示的圖示像素（model.metrics.iconSize × 倍率）；應與 iconPixelSize 相等，否則圖示不是 1:1 會發糊
        let displayedIconPixels: Int
        let showLatencyMs: [Double]
        /// show() 本身的同步執行時間（不含等 vsync）
        let showSyncMs: [Double]
        let showAnimation: FrameStats
        let pageFlip: FrameStats
        let trackpadSwipe: FrameStats
        let searchLatencyMs: Double
        let searchResults: [String]
        let folderOpen: FrameStats?
        let folderOpenLayoutMs: Double
        let typingLayoutMs: [String: Double]
        let keyToFrameMs: [Double]
        let typingFrames: FrameStats
        let interactions: [String: String]
        let memoryMB: Double
        let screenshots: [String]
    }

    /// 效能剖析用：顯示啟動台後以合成鍵盤事件反覆「打字搜尋 → 刪除」數秒，搭配 xctrace 取樣找熱點。
    @MainActor
    static func profileLoop(coordinator: AppCoordinator) async {
        for _ in 0..<100 where !coordinator.catalog.isReady { try? await Task.sleep(for: .milliseconds(50)) }
        await coordinator.icons.waitUntilLoaded()
        coordinator.show(screen: NSScreen.main)
        try? await Task.sleep(for: .milliseconds(500))
        let panel = coordinator.controller.panel
        let deadline = ContinuousClock.now + .seconds(6)
        while ContinuousClock.now < deadline {
            for (character, keyCode) in [("s", 1), ("a", 0), ("f", 3), ("\u{7f}", 51), ("\u{7f}", 51), ("\u{7f}", 51), ("c", 8), ("h", 4), ("\u{7f}", 51), ("\u{7f}", 51)] {
                for type in [NSEvent.EventType.keyDown, .keyUp] {
                    if let event = NSEvent.keyEvent(
                        with: type, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                        windowNumber: panel.windowNumber, context: nil, characters: character,
                        charactersIgnoringModifiers: character, isARepeat: false, keyCode: UInt16(keyCode)
                    ) {
                        panel.sendEvent(event)
                    }
                }
                try? await Task.sleep(for: .milliseconds(40))
            }
        }
        NSApp.terminate(nil)
    }

    @MainActor
    static func run(coordinator: AppCoordinator) async {
        let output = Paths.selfTest
        try? FileManager.default.removeItem(at: output)
        Paths.ensure(output)
        var shots: [String] = []

        // 等 App 清單與圖示就緒
        for _ in 0..<100 where !coordinator.catalog.isReady { try? await Task.sleep(for: .milliseconds(50)) }
        await coordinator.icons.waitUntilLoaded()
        try? await Task.sleep(for: .milliseconds(400))

        let model = coordinator.model
        let controller = coordinator.controller
        let screen = measurementScreen()
        let recorder = FrameRecorder(view: controller.panel.contentView!)

        func capture(_ name: String) {
            guard let image = SkyLight.captureWindow(controller.windowNumber) else { return }
            let url = output.appending(path: "\(shots.count)-\(name).png")
            IconRenderer.writePNG(image, to: url)
            shots.append(url.lastPathComponent)
        }

        // 1. 顯示延遲（冷的第一次 + 之後 5 次）與顯示動畫幀率
        var latencies: [Double] = []
        var showSync: [Double] = []
        var showStats = FrameStats(frames: 0, averageMs: 0, worstMs: 0, hitches: 0)
        for index in 0..<6 {
            coordinator.hide(reason: .user)
            try? await Task.sleep(for: .milliseconds(450))
            recorder.start()
            let start = ContinuousClock.now
            coordinator.show(screen: screen)
            showSync.append((milliseconds(since: start) * 10).rounded() / 10)
            _ = await recorder.nextFrame()
            latencies.append(milliseconds(since: start))
            try? await Task.sleep(for: .milliseconds(420))
            let stats = recorder.stop()
            if index == 1 { showStats = stats }
        }
        try? await Task.sleep(for: .milliseconds(300))
        capture("page1")

        // 2. 翻頁動畫（鍵盤翻頁：同一套彈簧動畫）
        let pageCount = model.displayPages.count
        recorder.start()
        for page in 1..<max(2, min(pageCount, 4)) {
            model.pager.go(to: page, pageCount: pageCount)
            try? await Task.sleep(for: .milliseconds(520))
        }
        let flipStats = recorder.stop()
        capture("page\(model.pager.page + 1)")
        model.pager.go(to: 0, pageCount: pageCount, animated: false)
        try? await Task.sleep(for: .milliseconds(200))

        // 3. 模擬觸控板跟手拖動（每 8ms 一個位移事件，與真實觸控板頻率相近）
        recorder.start()
        for step in 0..<40 {
            model.pager.offset = -CGFloat(step) * model.containerSize.width / 60
            try? await Task.sleep(for: .milliseconds(8))
        }
        model.pager.go(to: 1, pageCount: pageCount)
        try? await Task.sleep(for: .milliseconds(500))
        let swipeStats = recorder.stop()
        model.pager.go(to: 0, pageCount: pageCount, animated: false)

        // 4. 搜尋：逐字輸入，量「狀態改變 → SwiftUI 完成更新與排版」的主執行緒時間
        var typing: [String: Double] = [:]
        do {
            // 對照組：沒有任何變更、只移動選取（兩格狀態改變）
            var start = ContinuousClock.now
            controller.forceLayout()
            typing["~noop"] = (milliseconds(since: start) * 100).rounded() / 100
            for step in 0..<3 {
                start = ContinuousClock.now
                model.selection = ItemPosition(page: 0, index: step)
                controller.forceLayout()
                typing["~select\(step)"] = (milliseconds(since: start) * 100).rounded() / 100
                try? await Task.sleep(for: .milliseconds(60))
            }
            model.selection = nil
        }
        for query in ["s", "sa", "saf", "", "c", "ch", "chr", "x", ""] {
            let start = ContinuousClock.now
            model.searchText = query
            let modelMs = milliseconds(since: start)
            controller.renderer.syncNow()
            let gridMs = milliseconds(since: start) - modelMs
            controller.forceLayout()
            let key = query.isEmpty ? "(clear)\(typing.count)" : query
            typing[key] = (milliseconds(since: start) * 100).rounded() / 100
            typing[key + " model"] = (modelMs * 100).rounded() / 100
            typing[key + " grid"] = (gridMs * 100).rounded() / 100
            try? await Task.sleep(for: .milliseconds(120))
        }
        // 4b. 真實打字：合成鍵盤事件送進面板（經過輸入框→綁定→搜尋→格線圖層），量每鍵到下一幀的延遲與掉幀
        model.searchText = ""
        try? await Task.sleep(for: .milliseconds(200))
        var keyLatencies: [Double] = []
        var keyMainMs: [Double] = []
        var typedText = ""
        recorder.start()
        for (character, keyCode) in [("s", 1), ("a", 0), ("f", 3), ("a", 0), ("r", 15), ("i", 34)] + Array(repeating: ("\u{7f}", 51), count: 6) {
            let start = ContinuousClock.now
            for type in [NSEvent.EventType.keyDown, .keyUp] {
                if let event = NSEvent.keyEvent(
                    with: type, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                    windowNumber: controller.panel.windowNumber, context: nil, characters: character,
                    charactersIgnoringModifiers: character, isARepeat: false, keyCode: UInt16(keyCode)
                ) {
                    controller.panel.sendEvent(event)
                }
            }
            // 主執行緒同步成本：按鍵處理 + 圖層同步 + SwiftUI 排版（正常流程由追蹤迴圈在下一輪做，這裡強制立即做完來量）
            let eventMs = milliseconds(since: start)
            let parts = controller.forceLayoutTimed()
            keyMainMs.append((milliseconds(since: start) * 100).rounded() / 100)
            Log.perf.info("按鍵：事件 \(eventMs, format: .fixed(precision: 2))、圖層 \(parts.grid, format: .fixed(precision: 2))、SwiftUI \(parts.root, format: .fixed(precision: 2))ms")
            // 讓追蹤迴圈（下一輪主執行緒）完成同步，再等下一個 vsync：量到的是「按鍵 → 畫面可更新」的延遲
            await Task.yield()
            _ = await recorder.nextFrame()
            keyLatencies.append((milliseconds(since: start) * 10).rounded() / 10)
            if keyLatencies.count == 6 { typedText = model.searchText }
            try? await Task.sleep(for: .milliseconds(90))
        }
        let typingFrames = recorder.stop()
        // 打完 6 個字應為 safari、刪完 6 次應為空字串：確認按鍵真的進到搜尋框
        typing["~keys typed=\(typedText) final=\(model.searchText.isEmpty ? "(empty)" : model.searchText)"] = 0
        for (index, ms) in keyMainMs.enumerated() { typing["~key\(index) main"] = ms }

        let searchStart = ContinuousClock.now
        model.searchText = "sa"
        controller.forceLayout()
        let searchLatency = milliseconds(since: searchStart)
        let results = model.searchResults.prefix(8).compactMap { $0.appID.flatMap { coordinator.catalog.entry($0)?.name } }
        try? await Task.sleep(for: .milliseconds(300))
        capture("search")
        model.searchText = ""
        try? await Task.sleep(for: .milliseconds(200))

        // 5. 打開第一個資料夾
        var folderStats: FrameStats?
        var folderOpenMs = 0.0
        if let (pageIndex, folder) = firstFolder(in: model.layoutStore.layout) {
            model.pager.go(to: pageIndex, pageCount: pageCount, animated: false)
            try? await Task.sleep(for: .milliseconds(200))
            // 量測期間不截圖：視窗截圖在主執行緒同步執行要數十 ms，會被當成掉幀
            recorder.start()
            let openStart = ContinuousClock.now
            model.openFolder(folder.id)
            let modelMs = milliseconds(since: openStart)
            controller.renderer.syncNow()
            let gridMs = milliseconds(since: openStart) - modelMs
            controller.forceLayout()
            folderOpenMs = (milliseconds(since: openStart) * 100).rounded() / 100
            Log.perf.info("開資料夾：model \(modelMs, format: .fixed(precision: 2))ms、圖層 \(gridMs, format: .fixed(precision: 2))ms、SwiftUI \(folderOpenMs - modelMs - gridMs, format: .fixed(precision: 2))ms")
            try? await Task.sleep(for: .milliseconds(450))
            folderStats = recorder.stop()
            model.closeFolder()
            try? await Task.sleep(for: .milliseconds(350))
            // 再開一次截動畫中途與完成的畫面
            model.openFolder(folder.id)
            try? await Task.sleep(for: .milliseconds(80))
            capture("folder-opening")
            try? await Task.sleep(for: .milliseconds(370))
            capture("folder")
            model.closeFolder()
            try? await Task.sleep(for: .milliseconds(90))
            capture("folder-closing")
            try? await Task.sleep(for: .milliseconds(300))
        }

        // 6. 互動：以合成滑鼠事件實際走一遍「點擊、拖曳排序、拖到圖示上合併資料夾、Esc 取消拖曳、hover 預覽」
        let interactions = await interact(coordinator: coordinator, capture: capture)

        let displayedIconPixels = Int((coordinator.model.metrics.iconSize * screen.backingScaleFactor).rounded())
        coordinator.hide(reason: .user)
        try? await Task.sleep(for: .milliseconds(300))

        let report = Report(
            date: .now, apps: coordinator.catalog.entries.count, pages: pageCount,
            screen: "\(Int(screen.frame.width))×\(Int(screen.frame.height))@\(screen.backingScaleFactor)x",
            refreshRate: Double(screen.maximumFramesPerSecond),
            iconPixelSize: coordinator.icons.pixelSize, displayedIconPixels: displayedIconPixels,
            showLatencyMs: latencies.map { ($0 * 10).rounded() / 10 }, showSyncMs: showSync,
            showAnimation: showStats, pageFlip: flipStats, trackpadSwipe: swipeStats,
            searchLatencyMs: (searchLatency * 100).rounded() / 100, searchResults: Array(results),
            folderOpen: folderStats, folderOpenLayoutMs: folderOpenMs, typingLayoutMs: typing,
            keyToFrameMs: keyLatencies, typingFrames: typingFrames, interactions: interactions,
            memoryMB: memoryFootprintMB(), screenshots: shots
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(report) {
            try? data.write(to: output.appending(path: "report.json"))
        }
        Log.perf.info("自我測試完成")
        if !CommandLine.arguments.contains("--selftest-keep-running") {
            NSApp.terminate(nil)
        }
    }

    // MARK: - 互動測試

    /// 合成滑鼠事件直接送進面板（與真實事件走同一條路徑：面板 → 命中測試 → model）。
    @MainActor
    static func mouse(_ type: NSEvent.EventType, at point: CGPoint, controller: LaunchpadWindowController) {
        let location = controller.windowPoint(fromRoot: point)
        guard let event = NSEvent.mouseEvent(
            with: type, location: location, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: controller.panel.windowNumber, context: nil, eventNumber: LaunchpadPanel.syntheticEventNumber, clickCount: 1,
            pressure: type == .leftMouseUp ? 0 : 1
        ) else { return }
        controller.panel.sendEvent(event)
    }

    /// 模擬拖曳：按下 → 分段移動（每段 8ms，接近真實滑鼠頻率）→ 在終點停留 → 放開。
    /// - Parameters:
    ///   - onHold: 停留結束、放開前呼叫（截取懸停狀態）
    ///   - onRelease: 放開後 90ms 呼叫（截取放開動畫進行中的畫面）
    @MainActor
    private static func drag(from start: CGPoint, to end: CGPoint, hold: Duration, controller: LaunchpadWindowController,
                             onHold: () -> Void = {}, onRelease: () -> Void = {}) async {
        mouse(.leftMouseDown, at: start, controller: controller)
        let steps = 30
        for step in 1...steps {
            let t = CGFloat(step) / CGFloat(steps)
            mouse(.leftMouseDragged, at: CGPoint(x: start.x + (end.x - start.x) * t, y: start.y + (end.y - start.y) * t), controller: controller)
            try? await Task.sleep(for: .milliseconds(8))
        }
        try? await Task.sleep(for: hold)
        onHold()
        mouse(.leftMouseUp, at: end, controller: controller)
        try? await Task.sleep(for: .milliseconds(90))
        onRelease()
        try? await Task.sleep(for: .milliseconds(360))
    }

    @MainActor
    private static func interact(coordinator: AppCoordinator, capture: (String) -> Void) async -> [String: String] {
        let model = coordinator.model
        let controller = coordinator.controller
        let store = coordinator.layoutStore
        let original = store.layout
        var results: [String: String] = [:]
        // 測試過程絕不真的開啟使用者的 App；只接受合成滑鼠事件（使用者同時動滑鼠也不會干擾）
        model.suppressLaunches = true
        controller.panel.acceptsSyntheticMouseOnly = true
        defer {
            controller.panel.acceptsSyntheticMouseOnly = false
            // 測試會改動使用者的版面：結束後一定還原
            store.replace(with: original)
            store.saveNow()
            model.suppressLaunches = false
        }
        model.pager.go(to: 0, pageCount: model.displayPages.count, animated: false)
        model.searchText = ""
        try? await Task.sleep(for: .milliseconds(300))
        let metrics = model.metrics
        guard let page = store.layout.pages.first, page.count >= 6 else { return ["skipped": "第一頁項目太少"] }
        let apps = page.enumerated().filter { $0.element.appID != nil }.map(\.offset)
        guard apps.count >= 3 else { return ["skipped": "第一頁 App 太少"] }

        // (a) 拖曳排序：把第 apps[0] 格拖到第 apps[1] 格右側空隙
        let sourceIndex = apps[0]
        let movedID = page[sourceIndex].id
        let targetIndex = apps[1]
        let targetFrame = metrics.cellFrame(targetIndex)
        let gap = CGPoint(x: targetFrame.maxX - 4, y: metrics.iconCenter(targetIndex).y)
        await drag(from: metrics.iconCenter(sourceIndex), to: gap, hold: .milliseconds(150), controller: controller)
        let newIndex = store.layout.position(of: movedID)?.index
        results["dragReorder"] = newIndex != sourceIndex ? "ok（第 \(sourceIndex) 格 → 第 \(newIndex ?? -1) 格）" : "失敗：位置沒變"
        store.replace(with: original)
        try? await Task.sleep(for: .milliseconds(300))

        // (b) 拖到另一個 App 圖示中心停留 → 合併成資料夾
        let a = apps[1], b = apps[2]
        let aID = page[a].id, bID = page[b].id
        await drag(from: metrics.iconCenter(a), to: metrics.iconCenter(b), hold: .milliseconds(600), controller: controller,
                   onHold: { capture("merge-hover") }, onRelease: { capture("merge-dropping") })
        if let folder = store.layout.pages.flatMap({ $0 }).compactMap(\.folder).first(where: { Set($0.apps) == Set([aID, bID]) }) {
            capture("merged-folder")
            // 只有 2 個 App 的資料夾：面板應貼合內容（3 欄 × 1 列），不是整片最大尺寸
            model.openFolder(folder.id)
            try? await Task.sleep(for: .milliseconds(450))
            let fitted = model.folderColumns == 3 && model.folderRows == 1
            capture("small-folder")
            model.closeFolder()
            try? await Task.sleep(for: .milliseconds(350))
            results["mergeFolder"] = fitted
                ? "ok（新資料夾「\(folder.name)」，面板 3×1）"
                : "失敗：小資料夾面板 \(model.folderColumns)×\(model.folderRows)"
        } else {
            results["mergeFolder"] = "失敗：沒有產生資料夾"
        }
        store.replace(with: original)
        try? await Task.sleep(for: .milliseconds(300))

        // (c) 拖曳中按 Esc：版面還原
        mouse(.leftMouseDown, at: metrics.iconCenter(a), controller: controller)
        for step in 1...20 {
            mouse(.leftMouseDragged, at: CGPoint(x: metrics.iconCenter(a).x + CGFloat(step) * 12, y: metrics.iconCenter(a).y + 90), controller: controller)
            try? await Task.sleep(for: .milliseconds(8))
        }
        capture("dragging")
        model.handleEscape()
        mouse(.leftMouseUp, at: metrics.iconCenter(a), controller: controller)
        try? await Task.sleep(for: .milliseconds(300))
        results["dragCancel"] = store.layout == original && model.lastLaunchRequest == nil && model.isShown
            ? "ok" : "失敗：版面還原=\(store.layout == original)、誤觸開啟=\(model.lastLaunchRequest ?? "無")"

        // (c2) 單純點一下 App：應該要「開啟」（測試中只記錄不真的開）
        mouse(.leftMouseDown, at: metrics.iconCenter(b), controller: controller)
        mouse(.leftMouseUp, at: metrics.iconCenter(b), controller: controller)
        try? await Task.sleep(for: .milliseconds(100))
        results["clickLaunch"] = model.lastLaunchRequest == bID ? "ok" : "失敗：\(model.lastLaunchRequest ?? "沒有觸發")"

        // (d) 點擊資料夾 → 打開；點面板外 → 關閉
        if let folderIndex = page.firstIndex(where: { $0.folder != nil }) {
            mouse(.leftMouseDown, at: metrics.iconCenter(folderIndex), controller: controller)
            mouse(.leftMouseUp, at: metrics.iconCenter(folderIndex), controller: controller)
            try? await Task.sleep(for: .milliseconds(400))
            let opened = model.openFolderID != nil
            model.backgroundClicked()
            try? await Task.sleep(for: .milliseconds(350))
            results["folderClick"] = opened && model.openFolderID == nil ? "ok" : "失敗：opened=\(opened)"
        }

        // (d2) 鍵盤：→ ↓ 移動選取、Enter 開啟、Esc 收起前先清選取
        func key(_ keyCode: Int) {
            for type in [NSEvent.EventType.keyDown, .keyUp] {
                if let event = NSEvent.keyEvent(
                    with: type, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                    windowNumber: controller.panel.windowNumber, context: nil, characters: "", charactersIgnoringModifiers: "",
                    isARepeat: false, keyCode: UInt16(keyCode)
                ) { controller.panel.sendEvent(event) }
            }
        }
        model.pager.go(to: 0, pageCount: store.layout.pages.count, animated: false)
        model.selection = nil
        key(KeyCode.right)          // 第一次按方向鍵：選到目前頁第一格
        key(KeyCode.right)
        key(KeyCode.down)
        let expected = 1 + model.settings.columns
        let selected = model.selection
        key(KeyCode.returnKey)
        try? await Task.sleep(for: .milliseconds(100))
        let expectedItem = store.layout.pages[0].indices.contains(expected) ? store.layout.pages[0][expected] : nil
        let launchedOrOpened = expectedItem.map { item in
            item.appID.map { model.lastLaunchRequest == $0 } ?? (model.openFolderID == item.folder?.id)
        } ?? false
        results["keyboard"] = selected == ItemPosition(page: 0, index: expected) && launchedOrOpened
            ? "ok（選到第 \(expected) 格並開啟）" : "失敗：選取=\(String(describing: selected))、開啟=\(launchedOrOpened)"
        model.closeFolder()
        model.selection = nil
        try? await Task.sleep(for: .milliseconds(300))

        // (d3) 調整欄數：格子重新排列（量主執行緒同步時間），之後還原
        let columns = model.settings.columns
        let resizeStart = ContinuousClock.now
        model.settings.columns = columns + 1
        controller.forceLayout()
        results["resizeColumnsMs"] = String(format: "%.1f", milliseconds(since: resizeStart))
        try? await Task.sleep(for: .milliseconds(600))
        capture("columns-\(columns + 1)")
        model.settings.columns = columns
        try? await Task.sleep(for: .milliseconds(600))

        // (d4) 捲動翻頁：合成觸控板（有 phase 的連續捲動）與滑鼠滾輪事件
        func scroll(dx: Int32, dy: Int32, phase: Int64, continuous: Bool) {
            guard let cg = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: dy, wheel2: dx, wheel3: 0) else { return }
            cg.setIntegerValueField(.scrollWheelEventIsContinuous, value: continuous ? 1 : 0)
            cg.setIntegerValueField(.scrollWheelEventScrollPhase, value: phase)
            if let event = NSEvent(cgEvent: cg) { controller.panel.sendEvent(event) }
        }
        model.pager.go(to: 0, pageCount: store.layout.pages.count, animated: false)
        // 還原成預設頁寬，確認面板會自己設定（曾因沒人設定頁寬，跟手位移被夾在 ±1pt）
        model.pager.pageWidth = 1
        try? await Task.sleep(for: .milliseconds(100))
        scroll(dx: 0, dy: 0, phase: 1, continuous: true)          // began
        for _ in 0..<12 {
            scroll(dx: -30, dy: 0, phase: 2, continuous: true)    // changed：手指往左撥 = 下一頁
            try? await Task.sleep(for: .milliseconds(8))
        }
        let midOffset = model.pager.offset
        scroll(dx: 0, dy: 0, phase: 4, continuous: true)          // ended
        try? await Task.sleep(for: .milliseconds(500))
        let swipedTo = model.pager.page
        scroll(dx: 0, dy: 5, phase: 0, continuous: false)          // 滑鼠滾輪往上 = 上一頁
        try? await Task.sleep(for: .milliseconds(500))
        // 只有一頁時撥不到第 2 頁（使用者整理成單頁版面很常見）：不是缺陷，標成略過，免得把環境當成回歸
        if store.layout.pages.count < 2 {
            results["scrollPaging"] = "skipped（版面只有 1 頁）"
        } else {
            results["scrollPaging"] = swipedTo == 1 && model.pager.page == 0 && midOffset < -300
                ? "ok（跟手位移 \(Int(midOffset))pt → 第 2 頁，滾輪 → 第 1 頁）"
                : "失敗：跟手=\(midOffset)、撥動後頁=\(swipedTo)、滾輪後頁=\(model.pager.page)"
        }

        // (d5) 滑鼠在空白處按住往右拖 → 跟手並翻回上一頁（空白處 = 最後一頁格子沒排滿的位置）
        let lastPage = store.layout.pages.count - 1
        let lastCount = store.layout.pages.last?.count ?? 0
        if lastPage > 0, lastCount < metrics.columns * metrics.rows {
            model.pager.go(to: lastPage, pageCount: store.layout.pages.count, animated: false)
            model.pager.pageWidth = 1
            try? await Task.sleep(for: .milliseconds(150))
            let start = metrics.iconCenter(lastCount)
            mouse(.leftMouseDown, at: start, controller: controller)
            for step in 1...20 {
                mouse(.leftMouseDragged, at: CGPoint(x: start.x + CGFloat(step) * 20, y: start.y), controller: controller)
                try? await Task.sleep(for: .milliseconds(8))
            }
            let dragOffset = model.pager.offset
            mouse(.leftMouseUp, at: CGPoint(x: start.x + 400, y: start.y), controller: controller)
            try? await Task.sleep(for: .milliseconds(500))
            results["mouseDragPaging"] = dragOffset > 300 && model.pager.page == lastPage - 1 && controller.isVisible
                ? "ok（跟手位移 \(Int(dragOffset))pt → 第 \(lastPage) 頁）"
                : "失敗：跟手=\(dragOffset)、頁=\(model.pager.page)、仍顯示=\(controller.isVisible)"
            model.pager.go(to: 0, pageCount: store.layout.pages.count, animated: false)
        } else {
            results["mouseDragPaging"] = "skipped（最後一頁沒有空白格）"
        }

        // (d6) 資料夾面板內：在兩個圖示之間的空隙按住往左拖 → 翻到資料夾第 2 頁
        if let folder = store.layout.pages.flatMap({ $0 }).compactMap(\.folder).first(where: { $0.apps.count > model.folderCapacityLimit }) {
            if let pageIndex = store.layout.pages.firstIndex(where: { $0.contains { $0.folder?.id == folder.id } }) {
                model.pager.go(to: pageIndex, pageCount: store.layout.pages.count, animated: false)
            }
            model.openFolder(folder.id)
            try? await Task.sleep(for: .milliseconds(450))
            let panel = model.folderPanelFrame(for: folder)
            let fm = model.folderGridMetrics
            let start = CGPoint(x: panel.minX + fm.gridRect.minX + fm.cellSize.width, y: panel.minY + fm.iconCenter(0).y)
            mouse(.leftMouseDown, at: start, controller: controller)
            for step in 1...20 {
                mouse(.leftMouseDragged, at: CGPoint(x: start.x - CGFloat(step) * 20, y: start.y), controller: controller)
                try? await Task.sleep(for: .milliseconds(8))
            }
            let folderOffset = model.folderPager.offset
            mouse(.leftMouseUp, at: CGPoint(x: start.x - 400, y: start.y), controller: controller)
            try? await Task.sleep(for: .milliseconds(500))
            results["folderMouseDragPaging"] = folderOffset < -300 && model.folderPager.page == 1 && model.openFolderID == folder.id
                ? "ok（跟手位移 \(Int(folderOffset))pt → 資料夾第 2 頁）"
                : "失敗：跟手=\(folderOffset)、頁=\(model.folderPager.page)、資料夾仍開=\(model.openFolderID == folder.id)"
            model.closeFolder()
            try? await Task.sleep(for: .milliseconds(350))
            model.pager.go(to: 0, pageCount: store.layout.pages.count, animated: false)
        } else {
            results["folderMouseDragPaging"] = "skipped（沒有超過一頁的資料夾）"
        }

        // (d5) 拖到螢幕右緣停留：自動翻到下一頁，放開後項目在第 2 頁
        do {
            let pageCountBefore = store.layout.pages.count
            let start = metrics.iconCenter(apps[0])
            let edge = CGPoint(x: model.containerSize.width - 12, y: start.y)
            mouse(.leftMouseDown, at: start, controller: controller)
            for step in 1...25 {
                let t = CGFloat(step) / 25
                mouse(.leftMouseDragged, at: CGPoint(x: start.x + (edge.x - start.x) * t, y: start.y), controller: controller)
                try? await Task.sleep(for: .milliseconds(8))
            }
            try? await Task.sleep(for: .milliseconds(900))
            let flippedTo = model.pager.page
            mouse(.leftMouseDragged, at: CGPoint(x: model.containerSize.width / 2, y: start.y), controller: controller)
            try? await Task.sleep(for: .milliseconds(250))
            mouse(.leftMouseUp, at: CGPoint(x: model.containerSize.width / 2, y: start.y), controller: controller)
            try? await Task.sleep(for: .milliseconds(400))
            let landed = store.layout.position(of: page[apps[0]].id)
            results["edgeFlip"] = flippedTo == 1 && landed?.page == 1
                ? "ok（拖到右緣翻到第 2 頁，放開後在第 2 頁第 \(landed?.index ?? -1) 格）"
                : "失敗：翻頁=\(flippedTo)、落點=\(String(describing: landed))、頁數 \(pageCountBefore)→\(store.layout.pages.count)"
            store.replace(with: original)
            model.pager.go(to: 0, pageCount: store.layout.pages.count, animated: false)
            try? await Task.sleep(for: .milliseconds(300))
        }

        // (d6) 從資料夾拖出：面板關閉、App 回到主格線
        if let folderIndex = page.firstIndex(where: { ($0.folder?.apps.count ?? 0) >= 3 }), let folder = page[folderIndex].folder {
            model.openFolder(folder.id)
            try? await Task.sleep(for: .milliseconds(450))
            let panel = model.folderPanelFrame(for: folder)
            let folderMetrics = model.folderGridMetrics
            let start = CGPoint(x: panel.minX + folderMetrics.iconCenter(0).x, y: panel.minY + folderMetrics.iconCenter(0).y)
            let outside = CGPoint(x: panel.midX, y: model.containerSize.height - 40)
            await drag(from: start, to: outside, hold: .milliseconds(300), controller: controller)
            let movedApp = folder.apps[0]
            let stillInFolder = store.layout.folder(id: folder.id)?.apps.contains(movedApp) ?? false
            results["dragOutOfFolder"] = !stillInFolder && store.layout.position(of: movedApp) != nil && model.openFolderID == nil
                ? "ok" : "失敗：仍在資料夾=\(stillInFolder)、資料夾開著=\(model.openFolderID != nil)"
            store.replace(with: original)
            try? await Task.sleep(for: .milliseconds(300))
        }

        // (d7) 長按／右鍵「徹底移除…」的確認框（只截圖、按取消，不會真的移除）
        if let trashable = apps.lazy.compactMap({ page[$0].appID }).first(where: { !(coordinator.catalog.entry($0)?.isSystemApp ?? true) }) {
            model.requestUninstall(trashable)
            try? await Task.sleep(for: .milliseconds(350))
            capture("confirm-trash")
            model.handleEscape()
            try? await Task.sleep(for: .milliseconds(250))
            results["confirmDialog"] = model.confirmation == nil ? "ok（Esc 取消）" : "失敗：確認框沒關"
        }

        // (e) 游標停在執行中的 App 上 → 視窗預覽
        // 挑一個「畫面上有視窗」的執行中 App（沒有視窗的 App 不會跳預覽）
        let pidsWithWindows: Set<pid_t> = {
            let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
            return Set(list.filter { info in
                guard (info[kCGWindowLayer as String] as? Int) == 0,
                      (info[kCGWindowAlpha as String] as? Double ?? 1) > 0.01,
                      let bounds = (info[kCGWindowBounds as String] as? NSDictionary).flatMap({ CGRect(dictionaryRepresentation: $0) })
                else { return false }
                return bounds.width >= 300 && bounds.height >= 200
            }.compactMap { $0[kCGWindowOwnerPID as String] as? pid_t })
        }()
        let pages = store.layout.pages
        if let (pageIndex, index) = pages.enumerated().lazy.compactMap({ pageIndex, items -> (Int, Int)? in
            items.firstIndex { item in
                guard let id = item.appID, let app = model.running.application(for: id) else { return false }
                return pidsWithWindows.contains(app.processIdentifier)
            }.map { (pageIndex, $0) }
        }).first {
            model.pager.go(to: pageIndex, pageCount: pages.count, animated: false)
            try? await Task.sleep(for: .milliseconds(300))
            let center = metrics.iconCenter(index)
            mouse(.mouseMoved, at: CGPoint(x: center.x - 80, y: center.y), controller: controller)
            mouse(.mouseMoved, at: center, controller: controller)
            let start = ContinuousClock.now
            while !model.preview.isVisible, ContinuousClock.now - start < .seconds(2) {
                try? await Task.sleep(for: .milliseconds(20))
            }
            let shownAfter = milliseconds(since: start)
            try? await Task.sleep(for: .milliseconds(500))
            let pickedName = pages[pageIndex][index].appID.flatMap { coordinator.catalog.entry($0)?.name } ?? "?"
            results["hoverPreview"] = model.preview.isVisible
                ? "ok（\(pickedName)，\(Int(shownAfter))ms 後出現，狀態 \(model.preview.status)，視窗 \(model.preview.cards.count) 個，縮圖 \(model.preview.cards.filter { $0.image != nil }.count) 張）"
                : "失敗：\(pickedName) 的預覽沒有出現（狀態 \(model.preview.status)）"
            capture("preview")
            mouse(.mouseMoved, at: CGPoint(x: 20, y: model.containerSize.height - 20), controller: controller)
            try? await Task.sleep(for: .milliseconds(400))
        } else {
            results["hoverPreview"] = "略過：頂層沒有「有視窗的執行中 App」"
        }
        return results
    }

    private static func firstFolder(in layout: Layout) -> (Int, FolderData)? {
        for (index, page) in layout.pages.enumerated() {
            if let folder = page.lazy.compactMap(\.folder).first { return (index, folder) }
        }
        return nil
    }

    /// 主執行緒實際消耗的 CPU 時間（ms）：與牆鐘時間比較，可分辨「真的在算」還是「在等 render server」。
    static func threadCPUTimeMs() -> Double {
        var ts = timespec()
        clock_gettime(CLOCK_THREAD_CPUTIME_ID, &ts)
        return Double(ts.tv_sec) * 1000 + Double(ts.tv_nsec) / 1e6
    }

    /// 目前的實體記憶體用量（phys_footprint，與「活動監視器」的「記憶體」欄相同）。
    static func memoryFootprintMB() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        return (Double(info.phys_footprint) / 1_048_576 * 10).rounded() / 10
    }
}

/// 量測用的螢幕：避開鏡像中的螢幕（在鏡像組裡 NSView 的 display link 不會回呼，量不到任何幀）。
/// 找不到時退回主螢幕。
@MainActor
func measurementScreen() -> NSScreen {
    var ids = [CGDirectDisplayID](repeating: 0, count: 16)
    var count: UInt32 = 0
    CGGetOnlineDisplayList(16, &ids, &count)
    let mirrored = Set(ids.prefix(Int(count)).compactMap { id -> CGDirectDisplayID? in
        let target = CGDisplayMirrorsDisplay(id)
        return target == kCGNullDirectDisplay ? nil : target
    })
    let candidates = NSScreen.screens.filter { !mirrored.contains($0.displayID) && CGDisplayMirrorsDisplay($0.displayID) == kCGNullDirectDisplay }
    if let main = NSScreen.main, candidates.contains(main) { return main }
    return candidates.first ?? NSScreen.main ?? NSScreen.screens[0]
}

/// 以 CADisplayLink 記錄每一幀的時間。
final class FrameRecorder: NSObject {
    private var link: CADisplayLink?
    private var timestamps: [CFTimeInterval] = []
    private var frameWaiters: [CheckedContinuation<Double, Never>] = []
    private let view: NSView

    init(view: NSView) {
        self.view = view
    }

    func start() {
        timestamps.removeAll()
        link?.invalidate()
        let link = view.displayLink(target: self, selector: #selector(tick(_:)))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    /// 等待下一個 vsync，回傳等待時間（ms）。
    func nextFrame() async -> Double {
        let start = ContinuousClock.now
        // 逾時保護：display link 若沒有回呼（例如視窗暫時沒有畫面更新），最多等 500ms，不讓整個自測卡死
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self, !self.frameWaiters.isEmpty else { return }
            Log.perf.error("等待下一幀逾時（display link 沒有回呼）")
            let waiters = self.frameWaiters
            self.frameWaiters.removeAll()
            waiters.forEach { $0.resume(returning: 0) }
        }
        _ = await withCheckedContinuation { continuation in frameWaiters.append(continuation) }
        return milliseconds(since: start)
    }

    @objc private func tick(_ link: CADisplayLink) {
        timestamps.append(link.timestamp)
        let waiters = frameWaiters
        frameWaiters.removeAll()
        waiters.forEach { $0.resume(returning: 0) }
    }

    func stop() -> SelfTest.FrameStats {
        link?.invalidate()
        link = nil
        let intervals = zip(timestamps.dropFirst(), timestamps).map { ($0 - $1) * 1000 }
        guard !intervals.isEmpty else { return SelfTest.FrameStats(frames: 0, averageMs: 0, worstMs: 0, hitches: 0) }
        let sorted = intervals.sorted()
        let nominal = sorted[sorted.count / 2]
        let average = intervals.reduce(0, +) / Double(intervals.count)
        return SelfTest.FrameStats(
            frames: intervals.count,
            averageMs: (average * 100).rounded() / 100,
            worstMs: ((sorted.last ?? 0) * 100).rounded() / 100,
            hitches: intervals.filter { $0 > nominal * 1.5 }.count
        )
    }
}
