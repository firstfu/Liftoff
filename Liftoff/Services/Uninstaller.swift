//
//  Uninstaller.swift
//  Liftoff
//
//  「徹底移除」：除了 App 本體，還掃出它散落在 ~/Library（偏好設定、快取、容器、Application Support…）
//  的殘留檔，列給使用者勾選後一併移到垃圾桶（可從垃圾桶復原），效果類似 AppCleaner。
//
//  比對原則（寧缺勿濫，避免誤刪別的 App 的資料）：
//  - 以 bundle ID 比對的項目預設勾選（名稱含完整 bundle ID，幾乎不會誤中）
//  - 只靠 App 名稱比對的項目預設不勾選（例如 Application Support/Slack），由使用者自己決定
//  - /Library 底下需要管理員權限的位置，只有目前使用者可寫入時才會列出
//

import AppKit
import Observation

/// 單一殘留檔。
struct LeftoverFile: Identifiable, Hashable, Sendable {
    let url: URL
    /// 檔案或資料夾的總大小（bytes）
    let size: Int64
    /// 來源位置的簡短說明（例如「快取」），顯示在列表
    let kind: String
    var id: URL { url }
}

/// 移除確認框的狀態：App 本體 ＋ 掃到的殘留檔 ＋ 使用者的勾選。
@Observable
final class UninstallPlan {
    let appID: String
    /// 掃描中（殘留檔列表尚未出爐）
    var isScanning = true
    var leftovers: [LeftoverFile] = []
    /// 勾選要一併移除的殘留檔
    var selected: Set<URL> = []
    /// App 本體大小
    var appSize: Int64 = 0
    var isRemoving = false

    init(appID: String) {
        self.appID = appID
    }

    /// 勾選項目（含 App 本體）的總大小。
    var totalSelectedSize: Int64 {
        appSize + leftovers.filter { selected.contains($0.url) }.reduce(0) { $0 + $1.size }
    }
}

nonisolated enum Uninstaller {
    /// 掃描一個 App 的殘留檔（在背景執行緒呼叫；會做檔案系統列舉與大小計算）。
    /// - Parameter entry: 要移除的 App
    /// - Returns: (殘留檔清單, 預設勾選的網址, App 本體大小)
    static func scan(_ entry: AppEntry) -> (files: [LeftoverFile], preselected: Set<URL>, appSize: Int64) {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        let userLibrary = home.appending(path: "Library", directoryHint: .isDirectory)
        let systemLibrary = URL(fileURLWithPath: "/Library", isDirectory: true)

        var found: [URL: (kind: String, byBundleID: Bool)] = [:]
        let candidates = nameCandidates(for: entry)

        /// 在 `directory` 內找符合的子項目。
        /// - Parameters:
        ///   - ids: 完整比對 bundle ID 的規則（檔名等於、或以 `<id>.` 開頭、或含 id 的 group 容器）
        ///   - names: 以名稱完整比對（不含副檔名）的規則；不勾選
        func collect(in directory: URL, kind: String, matchesID: ((String, String) -> Bool)? = nil, names: Bool = false) {
            guard let children = try? fm.contentsOfDirectory(atPath: directory.path) else { return }
            for child in children {
                let url = directory.appending(path: child)
                if let bundleID = entry.bundleID, (matchesID ?? Uninstaller.defaultMatch)(child, bundleID) {
                    found[url] = (kind, true)
                } else if names {
                    let stem = (child as NSString).deletingPathExtension
                    let hit = candidates.contains { $0.caseInsensitiveCompare(stem) == .orderedSame || $0.caseInsensitiveCompare(child) == .orderedSame }
                    if hit, found[url] == nil { found[url] = (kind, false) }
                }
            }
        }

        for (root, isSystem) in [(userLibrary, false), (systemLibrary, true)] {
            // /Library 需要管理員權限：不可寫就不列出，免得按了移除才失敗
            func writable(_ directory: URL) -> Bool { !isSystem || fm.isWritableFile(atPath: directory.path) }
            func dir(_ name: String) -> URL { root.appending(path: name, directoryHint: .isDirectory) }

            if writable(dir("Application Support")) { collect(in: dir("Application Support"), kind: String(localized: "App 資料"), names: true) }
            if writable(dir("Caches")) { collect(in: dir("Caches"), kind: String(localized: "快取"), names: true) }
            if writable(dir("Preferences")) { collect(in: dir("Preferences"), kind: String(localized: "偏好設定")) }
            if writable(dir("LaunchAgents")) { collect(in: dir("LaunchAgents"), kind: String(localized: "背景代理")) }
            if isSystem {
                if writable(dir("LaunchDaemons")) { collect(in: dir("LaunchDaemons"), kind: String(localized: "背景服務")) }
                if writable(dir("PrivilegedHelperTools")) { collect(in: dir("PrivilegedHelperTools"), kind: String(localized: "輔助工具")) }
            }
        }
        // 以下只存在於使用者資料夾
        collect(in: userLibrary.appending(path: "Preferences/ByHost"), kind: String(localized: "偏好設定"))
        collect(in: userLibrary.appending(path: "Containers"), kind: String(localized: "沙盒容器"))
        collect(in: userLibrary.appending(path: "Group Containers"), kind: String(localized: "群組容器"), matchesID: { name, id in name.contains(id) })
        collect(in: userLibrary.appending(path: "Saved Application State"), kind: String(localized: "視窗狀態"))
        collect(in: userLibrary.appending(path: "HTTPStorages"), kind: String(localized: "網路儲存"))
        collect(in: userLibrary.appending(path: "WebKit"), kind: String(localized: "WebKit 資料"))
        collect(in: userLibrary.appending(path: "Cookies"), kind: String(localized: "Cookie"))
        collect(in: userLibrary.appending(path: "Application Scripts"), kind: String(localized: "App 腳本"))
        collect(in: userLibrary.appending(path: "Logs"), kind: String(localized: "記錄檔"), names: true)

        // 計算大小（資料夾要遞迴），依大小由大到小排
        let files = found.map { url, meta in
            LeftoverFile(url: url, size: allocatedSize(of: url), kind: meta.kind)
        }.sorted { $0.size > $1.size }
        let preselected = Set(files.filter { found[$0.url]?.byBundleID == true }.map(\.url))
        return (files, preselected, allocatedSize(of: entry.url))
    }

    /// bundle ID 比對：檔名等於 id，或以 `id.` 開頭（例如 `com.x.App.plist`、`com.x.App.savedState`、`com.x.App.helper`）。
    fileprivate static func defaultMatch(_ child: String, _ id: String) -> Bool {
        child == id || child.hasPrefix(id + ".") || child.hasPrefix(id + "-")
    }

    /// 名稱比對用的候選：顯示名稱、其他名稱、檔名（去掉 .app）。過短的名稱（≤2 字）容易誤中，排除。
    private static func nameCandidates(for entry: AppEntry) -> [String] {
        let fileName = ((entry.path as NSString).lastPathComponent as NSString).deletingPathExtension
        return ([entry.name, fileName] + entry.altNames).filter { $0.count > 2 }
    }

    /// 檔案或資料夾實際占用的大小。
    private static func allocatedSize(of url: URL) -> Int64 {
        let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .isDirectoryKey]
        let fm = FileManager.default
        var total: Int64 = 0
        guard let values = try? url.resourceValues(forKeys: Set(keys)) else { return 0 }
        if values.isDirectory != true {
            return Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
        }
        guard let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: keys, options: [], errorHandler: { _, _ in true }) else { return 0 }
        for case let child as URL in enumerator {
            let v = try? child.resourceValues(forKeys: Set(keys))
            total += Int64(v?.totalFileAllocatedSize ?? v?.fileAllocatedSize ?? 0)
        }
        return total
    }

    /// 把勾選的殘留檔移到垃圾桶（逐一處理，單一失敗不影響其他）。
    /// - Returns: 失敗的項目名稱
    static func trash(_ urls: [URL]) -> [String] {
        var failed: [String] = []
        for url in urls {
            do {
                try FileManager.default.trashItem(at: url, resultingItemURL: nil)
            } catch {
                failed.append(url.lastPathComponent)
            }
        }
        return failed
    }
}
