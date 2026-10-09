//
//  SelfTest+Demo.swift
//  Liftoff
//
//  README／行銷素材產生器（以 `--demo-shots <輸出資料夾>` 啟動，正常使用不會執行）。
//  跟自我測試一樣直接驅動 model、只擷取啟動台面板「自己」的畫面：不送任何全域的滑鼠鍵盤事件，
//  也拍不到桌面上其他視窗，所以使用者同時在用電腦不會被干擾，私人內容也不會被拍進去。
//  產出：grid／folder／search／preview／smart-organize 的 PNG，以及 hero 動圖用的逐格影格（frames/）
//  與 frames.txt（ffmpeg concat 格式，每格停留時間取實際擷取間隔）。
//  會暫時改動版面與隱藏清單，結束後一定還原。搭配 `-AppleLanguages "(ja)"` 可產生各語言版本。
//
//  參數：
//    --demo-hide id1,id2     額外隱藏的 App（把私人 App 排除在畫面外）
//    --demo-app id1,id2      示範用的執行中 App（預覽縮圖停在第一個有在執行的），它們的視窗內容必須能公開
//    --demo-search a,b,c     搜尋示範的候選字串，取第一個有結果的
//    --demo-set core         只產生 grid／folder／smart-organize（其他語言的在地化截圖用，不拍搜尋、預覽與動圖）
//
//  隱私防線：搜尋會比對所有視窗標題，示範時桌面上可能有私人視窗。每次輸出畫面前都檢查結果裡的視窗
//  都屬於示範 App，否則那一格不輸出（寧可少一格，不能洩漏標題）。
//

import AppKit
import SwiftUI

enum DemoShots {
    /// 輸出資料夾；沒帶 `--demo-shots` 時為 nil
    static var outputDirectory: URL? {
        value(of: "--demo-shots").map { URL(fileURLWithPath: $0, isDirectory: true) }
    }

    /// 取得 `--flag value` 的 value。
    private static func value(of flag: String) -> String? {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else { return nil }
        return arguments[index + 1]
    }

    private static func list(of flag: String, default fallback: [String]) -> [String] {
        value(of: flag).map { $0.split(separator: ",").map(String.init) } ?? fallback
    }

    /// 產生全部素材。
    /// - Parameters:
    ///   - coordinator: App 協調者
    ///   - output: 輸出資料夾
    @MainActor
    static func run(coordinator: AppCoordinator, output: URL) async {
        Paths.ensure(output)
        for _ in 0..<100 where !coordinator.catalog.isReady { try? await Task.sleep(for: .milliseconds(50)) }
        await coordinator.icons.waitUntilLoaded()

        let model = coordinator.model
        let controller = coordinator.controller
        let store = coordinator.layoutStore
        let settings = AppSettings.shared
        let demoAppList = list(of: "--demo-app", default: ["com.apple.calculator", "com.apple.TextEdit"])
        let demoApps = Set(demoAppList)
        let queries = list(of: "--demo-search", default: ["term", "pho", "cal", "note", "mus"])
        let isFullSet = value(of: "--demo-set") != "core"

        // 會改動使用者的版面與隱藏清單：先備份，結束後還原並刪掉這份備份（不留痕跡在「備份」清單裡）
        let originalLayout = store.layout
        let originalHidden = settings.hiddenApps
        savePendingRestore(layout: originalLayout, hiddenApps: UserDefaults.standard.array(forKey: hiddenAppsKey) as? [String])
        model.suppressLaunches = true
        controller.panel.acceptsSyntheticMouseOnly = true
        defer {
            controller.panel.acceptsSyntheticMouseOnly = false
            settings.hiddenApps = originalHidden
            store.replace(with: originalLayout)
            store.saveNow()
            model.suppressLaunches = false
            clearPendingRestore()
        }

        // 1. 排除私人 App，並用智慧整理建立乾淨版面（跟新使用者第一次啟動看到的一樣）
        settings.hiddenApps = originalHidden.union(list(of: "--demo-hide", default: []))
        try? await Task.sleep(for: .milliseconds(500))
        let plan = OrganizePlan(entries: coordinator.catalog.entries, hidden: settings.hiddenApps, classifier: .bundled())
        store.replace(with: plan.layout(capacity: settings.pageCapacity))
        try? await Task.sleep(for: .milliseconds(400))
        coordinator.show(screen: measurementScreen())
        try? await Task.sleep(for: .milliseconds(900))
        let pageCount = model.displayPages.count
        model.pager.go(to: 0, pageCount: pageCount, animated: false)
        model.searchText = ""

        /// 搜尋結果中的視窗是否都屬於示範 App
        func isSafeToShow() -> Bool {
            model.searchResults.allSatisfy { item in item.windowHit.map { demoApps.contains($0.appID) } ?? true }
        }
        func capture() -> CGImage? {
            isSafeToShow() ? SkyLight.captureWindow(controller.windowNumber) : nil
        }
        func save(_ name: String) {
            guard let image = capture() else { return Log.app.error("素材 \(name, privacy: .public) 因隱私防線略過") }
            IconRenderer.writePNG(image, to: output.appending(path: "\(name).png"))
        }

        // 2. 格線
        try? await Task.sleep(for: .milliseconds(300))
        save("grid")

        // 3. 打開第一個內容夠多的資料夾
        let folder = store.layout.pages.flatMap { $0 }.compactMap(\.folder).max { $0.apps.count < $1.apps.count }
        if let folder, let position = store.layout.position(of: LayoutItem.folderKey(folder.id)) {
            model.pager.go(to: position.page, pageCount: pageCount, animated: false)
            try? await Task.sleep(for: .milliseconds(200))
            model.openFolder(folder.id)
            try? await Task.sleep(for: .milliseconds(700))
            save("folder")
            model.closeFolder()
            try? await Task.sleep(for: .milliseconds(450))
            model.pager.go(to: 0, pageCount: pageCount, animated: false)
        }

        // 4. 搜尋：取第一個有結果的候選字串
        var query: String?
        for candidate in queries where isFullSet {
            model.searchText = candidate
            controller.forceLayout()
            try? await Task.sleep(for: .milliseconds(450))
            if !model.searchResults.isEmpty { query = candidate; break }
        }
        if query != nil { save("search") }
        model.searchText = ""
        try? await Task.sleep(for: .milliseconds(300))

        // 5. 搜尋示範 App 並讓游標停在結果上 → 視窗縮圖預覽（只用有在執行的示範 App，縮圖內容才能公開）
        let target = isFullSet ? demoAppList.first { model.running.application(for: $0) != nil } : nil
        let targetQuery = target.map { String((coordinator.catalog.entry($0)?.name ?? $0).lowercased().prefix(4)) }
        var previewShown = false
        if let target, let targetQuery {
            previewShown = await searchAndHover(target, query: targetQuery, model: model, controller: controller)
            if previewShown { save("preview") }
            await unhover(model: model, controller: controller)
            model.searchText = ""
            try? await Task.sleep(for: .milliseconds(300))
        }

        // 6. 智慧整理的預覽畫面：開一個真正的小視窗擷取（SwiftUI 的 ImageRenderer 不會畫捲動容器的內容）
        coordinator.hide(reason: .user)
        try? await Task.sleep(for: .milliseconds(450))
        let sheet = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 600), styleMask: [.titled, .fullSizeContentView],
                             backing: .buffered, defer: false)
        // 預設 close() 後視窗會自行 release，與 ARC 重複釋放而崩潰
        sheet.isReleasedWhenClosed = false
        sheet.titlebarAppearsTransparent = true
        sheet.titleVisibility = .hidden
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] { sheet.standardWindowButton(button)?.isHidden = true }
        // 只用來畫畫面：不連主程式（hostPID nil），名稱與圖示取自磁碟上的 App 索引
        let context = SettingsContext(settings: coordinator.settings, hostPID: nil)
        sheet.contentView = NSHostingView(rootView: OrganizePreview(plan: plan, context: context, onApply: {}, onCancel: {}))
        sheet.center()
        sheet.orderFrontRegardless()
        try? await Task.sleep(for: .milliseconds(900))
        if let image = SkyLight.captureWindow(CGWindowID(sheet.windowNumber)) {
            IconRenderer.writePNG(image, to: output.appending(path: "smart-organize.png"))
        }
        sheet.close()
        coordinator.show(screen: measurementScreen())
        try? await Task.sleep(for: .milliseconds(700))

        guard isFullSet else { return }

        // 7. hero 動圖：逐格擷取一段「格線 → 打字搜尋 → 視窗預覽 → 開資料夾 → 翻頁」
        let frameDirectory = Paths.ensure(output.appending(path: "frames", directoryHint: .isDirectory))
        var frames: [(name: String, time: Double)] = []
        let start = ContinuousClock.now
        /// 連續擷取指定秒數；擷取本身要數十 ms，實際幀率約 10–15fps（動圖本來就不需要更高）
        func record(for seconds: Double) async {
            let end = ContinuousClock.now + .seconds(seconds)
            while ContinuousClock.now < end {
                if let image = capture(), let small = downscale(image, width: 960) {
                    let name = String(format: "f%04d.png", frames.count)
                    IconRenderer.writePNG(small, to: frameDirectory.appending(path: name))
                    let elapsed = ContinuousClock.now - start
                    frames.append((name, Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18))
                }
                try? await Task.sleep(for: .milliseconds(10))
            }
        }
        model.pager.go(to: 0, pageCount: pageCount, animated: false)
        await record(for: 0.9)
        // 打字搜尋：有示範 App 就打它的名字（接著游標停上去看縮圖），否則打候選字串
        if let word = targetQuery ?? query {
            for end in 1...word.count {
                model.searchText = String(word.prefix(end))
                await record(for: 0.32)
            }
            await record(for: 0.8)
            if let target, previewShown {
                _ = await searchAndHover(target, query: word, model: model, controller: controller)
                await record(for: 1.8)
                await unhover(model: model, controller: controller)
                await record(for: 0.4)
            }
            model.searchText = ""
            await record(for: 0.5)
        }
        if let folder, let position = store.layout.position(of: LayoutItem.folderKey(folder.id)) {
            model.pager.go(to: position.page, pageCount: pageCount, animated: false)
            await record(for: 0.4)
            model.openFolder(folder.id)
            await record(for: 1.4)
            model.closeFolder()
            await record(for: 0.6)
        }
        if pageCount > 1 {
            model.pager.go(to: 0, pageCount: pageCount, animated: false)
            await record(for: 0.3)
            model.pager.go(to: 1, pageCount: pageCount)
            await record(for: 1.1)
            model.pager.go(to: 0, pageCount: pageCount)
            await record(for: 0.9)
        }
        writeConcatList(frames, to: output.appending(path: "frames.txt"))
        Log.app.info("素材完成：\(frames.count) 格影格、輸出 \(output.path, privacy: .public)")
    }


    // MARK: - 崩潰後復原

    /// 隱藏清單在 UserDefaults 的 key（與 AppSettings 內部的 Key 一致）
    private static let hiddenAppsKey = "hiddenApps"

    /// 示範前的狀態備忘：原始版面另存一份，以及原本的隱藏清單（nil 代表原本沒設定過）。
    private struct PendingRestore: Codable {
        let hiddenApps: [String]?
    }

    private static var markerURL: URL { Paths.caches.appending(path: "demo-restore.json") }
    private static var originalLayoutURL: URL { Paths.caches.appending(path: "demo-original-layout.json") }

    /// 記下要還原的狀態。示範會直接改寫使用者的版面與設定，任何一點中斷都不能讓使用者吃虧，所以先落地再動手。
    private static func savePendingRestore(layout: Layout, hiddenApps: [String]?) {
        if let data = try? JSONEncoder().encode(layout) { try? Paths.writeAtomically(data, to: originalLayoutURL) }
        if let data = try? JSONEncoder().encode(PendingRestore(hiddenApps: hiddenApps)) { try? Paths.writeAtomically(data, to: markerURL) }
    }

    private static func clearPendingRestore() {
        try? FileManager.default.removeItem(at: markerURL)
        try? FileManager.default.removeItem(at: originalLayoutURL)
    }

    /// 上次示範若沒有正常結束（崩潰、被強制結束），把版面與隱藏清單還原。
    /// 必須在版面載入之前呼叫；沒有備忘檔時只做一次檔案存在檢查，對一般啟動沒有影響。
    static func restoreIfInterrupted() {
        guard let data = try? Data(contentsOf: markerURL),
              let pending = try? JSONDecoder().decode(PendingRestore.self, from: data),
              FileManager.default.fileExists(atPath: originalLayoutURL.path) else { return }
        try? FileManager.default.removeItem(at: Paths.layoutFile)
        try? FileManager.default.copyItem(at: originalLayoutURL, to: Paths.layoutFile)
        if let hidden = pending.hiddenApps {
            UserDefaults.standard.set(hidden, forKey: hiddenAppsKey)
        } else {
            UserDefaults.standard.removeObject(forKey: hiddenAppsKey)
        }
        clearPendingRestore()
        Log.app.notice("上次的素材產生沒有正常結束，已還原版面與隱藏清單")
    }

    // MARK: - 輔助

    /// 搜尋指定 App，讓游標停在它的搜尋結果圖示上，等預覽縮圖出現（最多 3 秒）。
    /// - Returns: 預覽是否有出現
    @MainActor
    private static func searchAndHover(_ id: String, query: String, model: LaunchpadModel,
                                       controller: LaunchpadWindowController) async -> Bool {
        model.searchText = query
        controller.forceLayout()
        try? await Task.sleep(for: .milliseconds(600))
        guard let index = model.displayPages.first?.firstIndex(where: { $0.appID == id }) else { return false }
        let center = model.metrics.iconCenter(index)
        SelfTest.mouse(.mouseMoved, at: CGPoint(x: center.x - 80, y: center.y), controller: controller)
        SelfTest.mouse(.mouseMoved, at: center, controller: controller)
        let start = ContinuousClock.now
        while !model.preview.isVisible, ContinuousClock.now - start < .seconds(3) {
            try? await Task.sleep(for: .milliseconds(20))
        }
        try? await Task.sleep(for: .milliseconds(600))
        return model.preview.isVisible
    }

    /// 把游標移回角落，收起預覽。
    @MainActor
    private static func unhover(model: LaunchpadModel, controller: LaunchpadWindowController) async {
        SelfTest.mouse(.mouseMoved, at: CGPoint(x: 20, y: model.containerSize.height - 20), controller: controller)
        try? await Task.sleep(for: .milliseconds(450))
    }

    /// 縮小影像（動圖不需要 1080p，縮小後寫檔快、檔案也小）。
    static func downscale(_ image: CGImage, width: Int) -> CGImage? {
        let height = image.height * width / image.width
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }

    /// 寫出 ffmpeg concat 清單：每格停留到下一格的擷取時間，所以動圖速度與實際操作一致。
    private static func writeConcatList(_ frames: [(name: String, time: Double)], to url: URL) {
        var text = ""
        for (index, frame) in frames.enumerated() {
            let next = index + 1 < frames.count ? frames[index + 1].time : frame.time + 1.2
            text += "file 'frames/\(frame.name)'\nduration \(String(format: "%.3f", max(0.02, next - frame.time)))\n"
        }
        // concat 規定最後一格要再寫一次檔名，時長才會生效
        if let last = frames.last { text += "file 'frames/\(last.name)'\n" }
        try? text.write(to: url, atomically: true, encoding: .utf8)
    }
}
