//
//  LayoutStore.swift
//  Liftoff
//
//  版面的持有者：提供給 SwiftUI 觀察、負責存檔（去抖 0.6 秒、背景寫入）、備份與還原。
//  第一次啟動時若找得到舊版系統啟動台資料庫，自動沿用使用者原本的排列。
//

import Foundation
import Observation

@Observable
final class LayoutStore {
    private(set) var layout: Layout = .empty

    @ObservationIgnored private var saveTask: Task<Void, Never>?
    /// 是否已從磁碟載入或建立過版面
    @ObservationIgnored private(set) var isLoaded = false

    /// 備份檔資訊。
    struct Backup: Identifiable, Hashable {
        let url: URL
        let date: Date
        var id: URL { url }
        var name: String { url.deletingPathExtension().lastPathComponent }
    }

    /// 讀取存檔（沒有時保持空白，由呼叫端決定初始版面）。
    /// - Returns: 是否讀到存檔
    @discardableResult
    func load() -> Bool {
        guard let data = try? Data(contentsOf: Paths.layoutFile),
              let decoded = try? JSONDecoder().decode(Layout.self, from: data) else { return false }
        layout = decoded
        isLoaded = true
        return true
    }

    /// 修改版面並排程存檔。
    /// - Parameter change: 修改內容
    func update(_ change: (inout Layout) -> Void) {
        var copy = layout
        change(&copy)
        guard copy != layout else { return }
        layout = copy
        isLoaded = true
        scheduleSave()
    }

    /// 整個換掉版面（匯入、還原、重設）。
    func replace(with newLayout: Layout) {
        layout = newLayout
        isLoaded = true
        scheduleSave()
    }

    /// 與已安裝 App 同步；首次沒有存檔時建立初始版面（優先沿用舊版啟動台排列）。
    /// - Returns: 初始版面的來源說明（log 用）
    @discardableResult
    func reconcile(entries: [AppEntry], hidden: Set<String>, capacity: Int) -> String {
        if !isLoaded {
            if let url = LaunchpadImporter.databaseURL, let imported = try? LaunchpadImporter.read(at: url) {
                replace(with: LaunchpadImporter.makeLayout(from: imported, entries: entries, hidden: hidden, capacity: capacity))
                return "legacy-launchpad"
            }
            replace(with: .alphabetical(entries: entries, capacity: capacity, hidden: hidden))
            return "alphabetical"
        }
        update { $0.reconcile(installed: entries.map(\.id), hidden: hidden, capacity: capacity) }
        return "reconciled"
    }

    /// 立即寫檔（App 結束前呼叫）。
    func saveNow() {
        saveTask?.cancel()
        if let data = try? JSONEncoder().encode(layout) {
            try? Paths.writeAtomically(data, to: Paths.layoutFile)
        }
    }

    private func scheduleSave() {
        saveTask?.cancel()
        let snapshot = layout
        saveTask = Task {
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            await Task.detached(priority: .utility) {
                if let data = try? JSONEncoder().encode(snapshot) {
                    try? Paths.writeAtomically(data, to: Paths.layoutFile)
                }
            }.value
        }
    }

    // MARK: - 備份

    /// 以目前時間為名存一份備份。
    /// - Returns: 備份檔
    @discardableResult
    func createBackup() throws -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        let url = Paths.backups.appending(path: "\(formatter.string(from: .now)).json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try Paths.writeAtomically(try encoder.encode(layout), to: url)
        return url
    }

    func backups() -> [Backup] {
        let keys: [URLResourceKey] = [.contentModificationDateKey]
        let urls = (try? FileManager.default.contentsOfDirectory(at: Paths.backups, includingPropertiesForKeys: keys)) ?? []
        return urls.filter { $0.pathExtension == "json" }
            .map { Backup(url: $0, date: (try? $0.resourceValues(forKeys: Set(keys)).contentModificationDate) ?? .distantPast) }
            .sorted { $0.date > $1.date }
    }

    /// 還原備份（與目前安裝的 App 同步後套用）。
    /// - Throws: 讀檔或解碼錯誤
    func restore(_ backup: Backup, entries: [AppEntry], hidden: Set<String>, capacity: Int) throws {
        var restored = try JSONDecoder().decode(Layout.self, from: Data(contentsOf: backup.url))
        restored.reconcile(installed: entries.map(\.id), hidden: hidden, capacity: capacity)
        replace(with: restored)
    }

    func deleteBackup(_ backup: Backup) {
        try? FileManager.default.removeItem(at: backup.url)
    }
}
