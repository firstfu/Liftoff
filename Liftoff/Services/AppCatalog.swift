//
//  AppCatalog.swift
//  Liftoff
//
//  已安裝 App 的清單：啟動時先讀磁碟索引（幾毫秒就能顯示），再於背景重掃並比對差異；
//  之後以 FSEvents 監看 App 資料夾，有 App 安裝/移除/更新時自動重掃（去抖 1.5 秒）。
//

import AppKit
import CoreServices
import Observation

@Observable
final class AppCatalog {
    /// 依掃描順序排列的 App
    private(set) var entries: [AppEntry] = []
    /// 識別鍵 → App
    private(set) var byID: [String: AppEntry] = [:]
    /// 是否已有可用資料（讀到索引或完成第一次掃描）
    private(set) var isReady = false

    /// 實際路徑 → 識別鍵（比對執行中的 App 用）
    @ObservationIgnored private var byResolvedPath: [String: String] = [:]
    /// 原始路徑 → 識別鍵
    @ObservationIgnored private var byPath: [String: String] = [:]
    /// bundle ID（小寫）→ 識別鍵
    @ObservationIgnored private var byBundleID: [String: String] = [:]
    @ObservationIgnored private var stream: FSEventStreamRef?
    @ObservationIgnored private var pendingRescan: Task<Void, Never>?
    @ObservationIgnored private var directories: [URL] = AppScanner.defaultDirectories
    /// 清單變動後呼叫（版面同步、圖示載入、搜尋索引重建）
    @ObservationIgnored var onChange: (() -> Void)?

    // MARK: - 查詢

    func entry(_ id: String) -> AppEntry? { byID[id] }

    /// 由執行中 App 的資訊找出對應的識別鍵。
    /// - Parameters:
    ///   - bundleURL: NSRunningApplication.bundleURL
    ///   - bundleID: NSRunningApplication.bundleIdentifier
    /// - Returns: 識別鍵；不在清單中的 App（例如命令列工具）為 nil
    func id(forBundleURL bundleURL: URL?, bundleID: String?) -> String? {
        // NSRunningApplication.bundleURL 已是實際路徑，直接比對。不要再 resolvingSymlinksInPath：
        // 它會對路徑逐層 stat，碰到位於「桌面/文件」等受保護資料夾的 App 會觸發系統的資料夾存取詢問
        if let path = bundleURL?.path, let id = byResolvedPath[path] ?? byPath[path] { return id }
        if let bundleID, let id = byBundleID[bundleID.lowercased()] { return id }
        return nil
    }

    // MARK: - 載入與掃描

    /// 讀取上次的磁碟索引（同步、約 2ms），讓 App 一啟動就有資料可顯示。
    /// - Returns: 是否成功讀到
    @discardableResult
    func loadIndex() -> Bool {
        guard let data = try? Data(contentsOf: Paths.catalogFile),
              let cached = try? JSONDecoder().decode([AppEntry].self, from: data), !cached.isEmpty else { return false }
        apply(cached)
        Log.catalog.info("讀取 App 索引：\(cached.count) 個")
        return true
    }

    /// 設定要掃描的資料夾（預設位置 + 使用者額外加入的）。
    func setDirectories(extra: [String]) {
        var urls = AppScanner.defaultDirectories
        for path in extra where !urls.contains(where: { $0.path == path }) {
            urls.append(URL(fileURLWithPath: path, isDirectory: true))
        }
        guard urls != directories else { return }
        directories = urls
        if stream != nil { startWatching() }
    }

    /// 背景重掃所有資料夾，有變動才更新清單並寫回索引。
    func rescan() async {
        let directories = directories
        let previous = entries
        let start = ContinuousClock.now
        let scanned = await Task.detached(priority: .userInitiated) {
            AppScanner.scan(directories: directories, previous: previous)
        }.value
        Log.catalog.info("掃描完成：\(scanned.count) 個 App，\(milliseconds(since: start), format: .fixed(precision: 1))ms")
        guard scanned != entries else {
            isReady = true
            return
        }
        apply(scanned)
        let data = try? JSONEncoder().encode(scanned)
        Task.detached(priority: .utility) {
            if let data { try? Paths.writeAtomically(data, to: Paths.catalogFile) }
        }
    }

    private func apply(_ newEntries: [AppEntry]) {
        entries = newEntries
        var ids: [String: AppEntry] = [:]
        var paths: [String: String] = [:]
        var originals: [String: String] = [:]
        var bundles: [String: String] = [:]
        for entry in newEntries {
            ids[entry.id] = entry
            paths[entry.resolvedPath] = entry.id
            originals[entry.path] = entry.id
            if let bundleID = entry.bundleID?.lowercased(), bundles[bundleID] == nil { bundles[bundleID] = entry.id }
        }
        byID = ids
        byResolvedPath = paths
        byPath = originals
        byBundleID = bundles
        isReady = true
        onChange?()
    }

    // MARK: - 監看檔案系統

    /// 以 FSEvents 監看所有掃描資料夾（遞迴），變動時去抖後重掃。
    func startWatching() {
        stopWatching()
        let paths = directories.map(\.path).filter { FileManager.default.fileExists(atPath: $0) }
        guard !paths.isEmpty else { return }

        var context = FSEventStreamContext(
            version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil, release: nil, copyDescription: nil
        )
        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            // 串流排程在主佇列上，這裡必定在主執行緒
            MainActor.assumeIsolated {
                Unmanaged<AppCatalog>.fromOpaque(info).takeUnretainedValue().scheduleRescan()
            }
        }
        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault, callback, &context, paths as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 1.0,
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagNone)
        ) else { return }
        FSEventStreamSetDispatchQueue(stream, .main)
        FSEventStreamStart(stream)
        self.stream = stream
    }

    func stopWatching() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    /// App 安裝/更新時常在短時間內產生大量事件，合併成一次重掃。
    private func scheduleRescan() {
        pendingRescan?.cancel()
        pendingRescan = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            await self?.rescan()
        }
    }
}
