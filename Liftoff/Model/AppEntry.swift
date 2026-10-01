//
//  AppEntry.swift
//  Liftoff
//
//  已安裝 App 的中繼資料快照，以及掃描磁碟找出 App 的邏輯。
//  掃描刻意不用 `Bundle(url:)`：它會把每個 NSBundle 永久快取在記憶體裡，反覆重掃會越吃越多；
//  改為直接解析 Info.plist，並以 LaunchServices 取得在地化顯示名稱。
//

import AppKit

/// 單一 App 的不可變快照（可跨執行緒傳遞、可寫入磁碟索引）。
nonisolated struct AppEntry: Identifiable, Hashable, Sendable, Codable {
    /// 版面識別鍵：優先用 bundle ID（App 更新、搬移位置後仍穩定），沒有 bundle ID 或重複時用路徑
    let id: String
    let bundleID: String?
    /// App 所在位置（可能是符號連結，例如 /Applications/Safari.app）
    let path: String
    /// 解析符號連結後的實際路徑，用來比對 NSRunningApplication.bundleURL
    let resolvedPath: String
    /// 在地化顯示名稱（跟隨系統語言，例如「系統設定」）
    let name: String
    /// 其他名稱（CFBundleName、檔名等，多半是英文），讓搜尋英文名也找得到
    let altNames: [String]
    /// App Store 分類（LSApplicationCategoryType），自動命名資料夾用
    let category: String?
    /// Info.plist 修改時間：App 更新時會變，用來判斷圖示快取是否過期
    let modified: Date
    /// 中文名稱的拼音（搜尋用；非中文為 nil）。掃描時算好存進索引：拼音轉換會載入 ICU 字典（約 12MB 常駐），
    /// 之後啟動直接讀索引就不必再載入
    var latin: String? = nil

    var url: URL { URL(fileURLWithPath: path) }

    /// 位於系統唯讀卷宗的 App（不可移到垃圾桶）
    var isSystemApp: Bool {
        resolvedPath.hasPrefix("/System/") || path.hasPrefix("/System/")
    }
}

nonisolated enum AppScanner {
    /// 預設掃描位置（順序即優先權：同一 bundle ID 出現多次時，先找到的拿到 bundle ID 當識別鍵）
    static var defaultDirectories: [URL] {
        [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Applications", isDirectory: true),
            FileManager.default.homeDirectoryForCurrentUser.appending(path: "Applications", directoryHint: .isDirectory),
        ]
    }

    /// 掃描多個資料夾，回傳去重後的 App 清單（依資料夾優先序與路徑排序，結果穩定）。
    ///
    /// 成本（M 系列、約 170 個 App）：列舉 ~15ms，解析 Info.plist 與取在地化名稱以多核並行約 30–50ms。
    /// - Parameters:
    ///   - directories: 要掃描的資料夾（不存在的會被略過）
    ///   - maxDepth: 最多往下幾層（避免誤入巨大的資料夾樹）
    /// - Returns: App 清單
    static func scan(directories: [URL], maxDepth: Int = 3, previous: [AppEntry] = []) -> [AppEntry] {
        var candidates: [URL] = []
        var seenPaths = Set<String>()
        for directory in directories {
            for url in bundles(in: directory, maxDepth: maxDepth) {
                let resolved = url.resolvingSymlinksInPath().path
                // 同一個 App 可能經由符號連結出現兩次（例如 /Applications/Safari.app → Cryptex）
                guard seenPaths.insert(resolved).inserted else { continue }
                candidates.append(url)
            }
        }

        // Info.plist 解析與 LaunchServices 查名稱都是獨立 I/O，並行處理
        let urls = candidates
        // 上次掃描的拼音沿用（名稱沒變就不必再轉，避免載入 ICU）
        var knownLatin: [String: String] = [:]
        for entry in previous { if let latin = entry.latin { knownLatin[entry.path + "|" + entry.name] = latin } }
        let known = knownLatin
        let results = UnsafeResultBuffer<AppEntry?>(count: urls.count)
        DispatchQueue.concurrentPerform(iterations: urls.count) { index in
            guard var entry = makeEntry(for: urls[index]) else { return }
            entry.latin = known[entry.path + "|" + entry.name] ?? latinName(for: entry.name)
            results[index] = entry
        }

        var entries: [AppEntry] = []
        var usedIDs = Set<String>()
        for case let entry? in results.values {
            // bundle ID 重複（同一 App 多個副本）：後來的改用路徑當識別鍵，兩份都保留
            if usedIDs.contains(entry.id) {
                let alternate = AppEntry(
                    id: entry.path, bundleID: entry.bundleID, path: entry.path, resolvedPath: entry.resolvedPath,
                    name: entry.name, altNames: entry.altNames, category: entry.category, modified: entry.modified,
                    latin: entry.latin
                )
                usedIDs.insert(alternate.id)
                entries.append(alternate)
            } else {
                usedIDs.insert(entry.id)
                entries.append(entry)
            }
        }
        return entries
    }

    /// 中文名稱轉拼音（「計算機」→ "ji suan ji"）；不含漢字時回傳 nil。
    static func latinName(for name: String) -> String? {
        guard name.unicodeScalars.contains(where: { $0.properties.isIdeographic }) else { return nil }
        return name.applyingTransform(.toLatin, reverse: false)?.applyingTransform(.stripDiacritics, reverse: false)
    }

    /// 列舉資料夾內的 .app（不進入 App 套件內部；符號連結指向 .app 也算）。
    private static func bundles(in directory: URL, maxDepth: Int) -> [URL] {
        let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey]
        // 不用 .skipsHiddenFiles：系統把 /Applications/Safari.app（指向 Cryptex 的符號連結）標成隱藏，會被一起略過
        guard let enumerator = FileManager.default.enumerator(
            at: directory, includingPropertiesForKeys: keys,
            options: [.skipsPackageDescendants]
        ) else { return [] }

        var found: [URL] = []
        for case let url as URL in enumerator {
            if url.lastPathComponent.hasPrefix(".") {
                enumerator.skipDescendants()
            } else if url.pathExtension == "app" {
                found.append(url)
                enumerator.skipDescendants()
            } else if enumerator.level >= maxDepth {
                enumerator.skipDescendants()
            }
        }
        return found.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    /// 由 App 套件建立 AppEntry；不是有效 App（缺 Info.plist、背景程式）時回傳 nil。
    static func makeEntry(for url: URL) -> AppEntry? {
        let resolved = url.resolvingSymlinksInPath()
        // 一般 Mac App 在 Contents/；Apple Silicon 上的 iPhone/iPad App 以 WrappedBundle 包裝，Info.plist 在套件根目錄
        let plistURL = [
            resolved.appending(path: "Contents/Info.plist"),
            resolved.appending(path: "WrappedBundle/Info.plist"),
        ].first { FileManager.default.fileExists(atPath: $0.path) }
        guard let plistURL, let data = try? Data(contentsOf: plistURL),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return nil }
        // 純背景程式不會出現在啟動台
        if plist["LSBackgroundOnly"] as? Bool == true || (plist["LSBackgroundOnly"] as? String) == "1" { return nil }

        let bundleID = plist["CFBundleIdentifier"] as? String
        // 啟動台自己不必出現在啟動台裡
        if bundleID == Paths.bundleID { return nil }
        let fileName = url.deletingPathExtension().lastPathComponent
        let displayName = FileManager.default.displayName(atPath: url.path)
        let name = displayName.hasSuffix(".app") ? String(displayName.dropLast(4)) : displayName

        var alt: [String] = []
        for candidate in [plist["CFBundleDisplayName"] as? String, plist["CFBundleName"] as? String, fileName] {
            if let candidate, !candidate.isEmpty, candidate != name, !alt.contains(candidate) { alt.append(candidate) }
        }
        let modified = (try? plistURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
            ?? .distantPast

        return AppEntry(
            id: bundleID ?? url.path,
            bundleID: bundleID,
            path: url.path,
            resolvedPath: resolved.path,
            name: name,
            altNames: alt,
            category: plist["LSApplicationCategoryType"] as? String,
            modified: modified
        )
    }
}

/// concurrentPerform 專用的結果緩衝：每個 index 只由一條執行緒寫入一次、全部寫完才讀，因此不需要鎖。
/// 用原生指標而非 Swift 陣列：陣列屬性的並行寫入會觸發 Swift 的動態獨占存取檢查（exclusivity）而當掉。
nonisolated final class UnsafeResultBuffer<Element>: @unchecked Sendable {
    private let pointer: UnsafeMutablePointer<Element?>
    let count: Int

    init(count: Int) {
        self.count = count
        pointer = .allocate(capacity: max(count, 1))
        pointer.initialize(repeating: nil, count: count)
    }

    deinit {
        pointer.deinitialize(count: count)
        pointer.deallocate()
    }

    subscript(index: Int) -> Element? {
        get { pointer[index] }
        set { pointer[index] = newValue }
    }

    /// 依 index 順序回傳所有已寫入的結果。
    var values: [Element] { (0..<count).compactMap { pointer[$0] } }
}
