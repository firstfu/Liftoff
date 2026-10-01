//
//  AppActions.swift
//  Liftoff
//
//  對 App 的操作：開啟、在 Finder 顯示、移到垃圾桶、結束，以及開啟次數統計（搜尋排序加權用）。
//

import AppKit

enum AppActions {
    /// 開啟（或切換到）App。已在執行的 App 會收到 reopen 事件，行為與點 Dock 圖示相同（沒有視窗時會開新視窗）。
    /// - Parameter entry: 目標 App
    static func open(_ entry: AppEntry) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: entry.url, configuration: configuration) { _, error in
            if let error {
                Log.app.error("開啟 \(entry.name, privacy: .public) 失敗：\(error.localizedDescription, privacy: .public)")
            }
        }
    }

    static func revealInFinder(_ entry: AppEntry) {
        NSWorkspace.shared.activateFileViewerSelecting([entry.url])
    }

    /// 移到垃圾桶（可從垃圾桶復原）。系統 App 不允許。
    /// - Returns: 錯誤訊息；成功時為 nil
    static func moveToTrash(_ entry: AppEntry) async -> String? {
        guard !entry.isSystemApp else { return String(localized: "系統 App 無法移除") }
        do {
            _ = try await NSWorkspace.shared.recycle([entry.url])
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    static func quit(_ app: NSRunningApplication) {
        app.terminate()
    }
}

/// 開啟次數與最近使用時間（存在 Application Support/usage.json）。
@Observable
final class UsageStore {
    nonisolated struct Record: Codable, Sendable {
        var count: Int
        var last: Date
    }

    private(set) var records: [String: Record] = [:]
    @ObservationIgnored private var saveTask: Task<Void, Never>?

    init() {
        if let data = try? Data(contentsOf: Paths.usageFile),
           let decoded = try? JSONDecoder().decode([String: Record].self, from: data) {
            records = decoded
        }
    }

    func recordLaunch(_ id: String) {
        var record = records[id] ?? Record(count: 0, last: .distantPast)
        record.count += 1
        record.last = .now
        records[id] = record
        scheduleSave()
    }

    /// 搜尋加權（0…1）：使用次數取對數壓縮，再依最近使用時間衰減（半衰期約 30 天）。
    func boosts() -> [String: Double] {
        let now = Date.now
        var result: [String: Double] = [:]
        for (id, record) in records {
            let frequency = min(1, log2(Double(record.count) + 1) / 6)
            let days = now.timeIntervalSince(record.last) / 86_400
            result[id] = frequency * pow(0.5, days / 30)
        }
        return result
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [records] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled, let data = try? JSONEncoder().encode(records) else { return }
            try? Paths.writeAtomically(data, to: Paths.usageFile)
        }
    }
}
