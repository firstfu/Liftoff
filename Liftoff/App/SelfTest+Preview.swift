//
//  SelfTest+Preview.swift
//  Liftoff
//
//  視窗縮圖預覽的端到端測試（`--selftest-preview`）：對「有視窗的執行中 App」逐一 hover（主格線與資料夾內各測），
//  量測「游標停留 → 預覽框出現 → 所有縮圖就緒」的時間並截圖；最後實際點一張縮圖，確認啟動台收起且切換到該 App。
//  報告：~/Library/Caches/com.firstfu.Liftoff/selftest/report-preview.json
//

import AppKit

extension SelfTest {
    struct PreviewSample: Encodable {
        let app: String
        let inFolder: Bool
        let status: String
        let windows: Int
        let thumbnails: Int
        let shownMs: Double?
        let thumbnailsReadyMs: Double?
        let titles: [String]
        let screenshot: String?
    }

    struct PreviewReport: Encodable {
        let screenRecording: Bool
        let accessibility: Bool
        let delaySetting: Double
        let samples: [PreviewSample]
        let clickSwitch: String
    }

    /// 一個候選：App 在版面上的位置（頂層或資料夾內）與其 pid。
    private struct Candidate {
        let appID: String
        let name: String
        let pid: pid_t
        let page: Int
        let index: Int
        let folderID: UUID?
    }

    @MainActor
    static func runPreviewTest(coordinator: AppCoordinator) async {
        let output = Paths.selfTest
        Paths.ensure(output)
        for _ in 0..<100 where !coordinator.catalog.isReady { try? await Task.sleep(for: .milliseconds(50)) }
        await coordinator.icons.waitUntilLoaded()
        try? await Task.sleep(for: .milliseconds(300))

        let model = coordinator.model
        let controller = coordinator.controller
        let store = coordinator.layoutStore
        model.suppressLaunches = true
        controller.panel.acceptsSyntheticMouseOnly = true
        coordinator.show(screen: NSScreen.main ?? NSScreen.screens[0])
        try? await Task.sleep(for: .milliseconds(500))

        func capture(_ name: String) -> String? {
            guard let image = SkyLight.captureWindow(controller.windowNumber) else { return nil }
            let file = "preview-\(name).png"
            IconRenderer.writePNG(image, to: output.appending(path: file))
            return file
        }

        // 有「夠大的畫面上視窗」的 pid
        let pidsWithWindows: Set<pid_t> = {
            let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
            return Set(list.compactMap { info -> pid_t? in
                guard (info[kCGWindowLayer as String] as? Int) == 0,
                      (info[kCGWindowAlpha as String] as? Double ?? 1) > 0.01,
                      let bounds = (info[kCGWindowBounds as String] as? NSDictionary).flatMap({ CGRect(dictionaryRepresentation: $0) }),
                      bounds.width >= 300, bounds.height >= 200 else { return nil }
                return info[kCGWindowOwnerPID as String] as? pid_t
            })
        }()

        var topLevel: [Candidate] = []
        var inFolders: [Candidate] = []
        for (pageIndex, page) in store.layout.pages.enumerated() {
            for (index, item) in page.enumerated() {
                switch item {
                case .app(let id):
                    if let app = model.running.application(for: id), pidsWithWindows.contains(app.processIdentifier) {
                        topLevel.append(Candidate(appID: id, name: model.title(for: item), pid: app.processIdentifier, page: pageIndex, index: index, folderID: nil))
                    }
                case .folder(let folder):
                    for (offset, id) in folder.apps.enumerated() where offset < model.folderCapacity {
                        if let app = model.running.application(for: id), pidsWithWindows.contains(app.processIdentifier) {
                            inFolders.append(Candidate(appID: id, name: model.title(for: .app(id)), pid: app.processIdentifier, page: pageIndex, index: offset, folderID: folder.id))
                        }
                    }
                }
            }
        }

        var samples: [PreviewSample] = []
        let chosen = Array(topLevel.prefix(3)) + Array(inFolders.prefix(3))
        for candidate in chosen {
            samples.append(await hoverAndMeasure(candidate, model: model, controller: controller, capture: capture))
        }

        // 點縮圖切換視窗：優先挑 cmux（多半就是目前在用的終端機，切過去不會打擾），否則挑第一個頂層候選
        var clickResult = "略過：沒有可點的候選"
        if let target = topLevel.first(where: { $0.name.lowercased().contains("cmux") }) ?? topLevel.first {
            _ = await hoverAndMeasure(target, model: model, controller: controller, capture: { _ in nil })
            if model.preview.isVisible, let card = model.preview.cards.first {
                let frame = WindowPreviewLayer.frame(for: model.preview, containerSize: model.containerSize)
                // 第一張卡片縮圖中心：左右內距 14、上方為 App 名稱列（約 16pt）+ 間距 10、縮圖高 132
                let point = CGPoint(x: frame.minX + 14 + WindowPreviewModel.cardWidth / 2, y: frame.minY + 14 + 16 + 10 + 66)
                mouse(.mouseMoved, at: point, controller: controller)
                try? await Task.sleep(for: .milliseconds(150))
                mouse(.leftMouseDown, at: point, controller: controller)
                mouse(.leftMouseUp, at: point, controller: controller)
                try? await Task.sleep(for: .milliseconds(900))
                let front = NSWorkspace.shared.frontmostApplication
                let hidden = !controller.isVisible
                clickResult = hidden && front?.processIdentifier == target.pid
                    ? "ok（點「\(card.window.title.isEmpty ? target.name : card.window.title)」→ 啟動台收起、\(target.name) 到最前）"
                    : "失敗：啟動台收起=\(hidden)、最前面=\(front?.localizedName ?? "?")"
            } else {
                clickResult = "失敗：預覽沒有出現"
            }
        }

        coordinator.hide(reason: .user)
        let report = PreviewReport(
            screenRecording: CGPreflightScreenCaptureAccess(), accessibility: AXIsProcessTrusted(),
            delaySetting: model.settings.previewDelay, samples: samples, clickSwitch: clickResult
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(report) {
            try? data.write(to: output.appending(path: "report-preview.json"))
        }
        try? await Task.sleep(for: .milliseconds(300))
        NSApp.terminate(nil)
    }

    /// 把游標移到候選 App 的圖示上（必要時先翻頁或打開資料夾），量測預覽出現與縮圖就緒時間。
    @MainActor
    private static func hoverAndMeasure(
        _ candidate: Candidate, model: LaunchpadModel, controller: LaunchpadWindowController,
        capture: (String) -> String?
    ) async -> PreviewSample {
        // 先把游標移到角落、收掉上一個預覽
        mouse(.mouseMoved, at: CGPoint(x: 10, y: model.containerSize.height - 10), controller: controller)
        model.preview.hide()
        model.closeFolder()
        try? await Task.sleep(for: .milliseconds(350))
        model.pager.go(to: candidate.page, pageCount: model.layoutStore.layout.pages.count, animated: false)

        let center: CGPoint
        if let folderID = candidate.folderID, let folder = model.layoutStore.layout.folder(id: folderID) {
            model.openFolder(folderID)
            try? await Task.sleep(for: .milliseconds(450))
            let panel = model.folderPanelFrame(for: folder)
            let icon = model.folderGridMetrics.iconCenter(candidate.index)
            center = CGPoint(x: panel.minX + icon.x, y: panel.minY + icon.y)
        } else {
            try? await Task.sleep(for: .milliseconds(250))
            center = model.metrics.iconCenter(candidate.index)
        }

        mouse(.mouseMoved, at: CGPoint(x: center.x, y: center.y + 1), controller: controller)
        mouse(.mouseMoved, at: center, controller: controller)
        let start = ContinuousClock.now
        var shownMs: Double?
        var readyMs: Double?
        while ContinuousClock.now - start < .seconds(3) {
            if shownMs == nil, model.preview.isVisible { shownMs = milliseconds(since: start) }
            if shownMs != nil, model.preview.status != .loading,
               !model.preview.cards.isEmpty, model.preview.cards.allSatisfy({ $0.image != nil }) {
                readyMs = milliseconds(since: start)
                break
            }
            if model.preview.status == .noWindows || model.preview.status == .needsPermission, shownMs != nil { break }
            try? await Task.sleep(for: .milliseconds(10))
        }
        try? await Task.sleep(for: .milliseconds(250))
        let preview = model.preview
        let shot = preview.isVisible ? capture(candidate.name.replacingOccurrences(of: "/", with: "-")) : nil
        return PreviewSample(
            app: candidate.name, inFolder: candidate.folderID != nil, status: "\(preview.status)",
            windows: preview.cards.count, thumbnails: preview.cards.filter { $0.image != nil }.count,
            shownMs: shownMs.map { ($0 * 10).rounded() / 10 }, thumbnailsReadyMs: readyMs.map { ($0 * 10).rounded() / 10 },
            titles: preview.cards.map(\.window.title), screenshot: shot
        )
    }
}
