//
//  LaunchpadImporter.swift
//  Liftoff
//
//  匯入舊版系統啟動台（macOS 15 以前）的排列：資料在 `$DARWIN_USER_DIR/com.apple.dock.launchpad/db/db`（SQLite）。
//  升級到 macOS 26 後系統不再使用它，但檔案通常還留著，裡面有使用者多年整理的頁面與資料夾。
//
//  資料表結構（逆向自實際檔案）：
//  - items(rowid, uuid, flags, type, parent_id, ordering)：樹狀結構
//    type 1 = 根（uuid ROOTPAGE）、3 = 頁、2 = 資料夾、4 = App；資料夾底下還有自己的頁（type 3）
//    uuid 為 HOLDINGPAGE* 的是系統暫存頁，要排除
//  - apps(item_id, title, bundleid, …)、groups(item_id, category_id, title)
//  以唯讀＋immutable 模式開啟：不建立 -wal/-shm、不改動原檔。
//

import Foundation
import SQLite3

nonisolated enum LaunchpadImporter {
    /// 舊版啟動台中的一格。
    enum ImportedItem: Equatable, Sendable {
        case app(bundleID: String?, title: String?)
        case folder(title: String, apps: [ImportedApp])
    }

    struct ImportedApp: Equatable, Sendable {
        let bundleID: String?
        let title: String?
    }

    enum ImportError: LocalizedError {
        case notFound
        case openFailed(String)
        case noPages

        var errorDescription: String? {
            switch self {
            case .notFound: String(localized: "找不到舊版啟動台的資料庫")
            case .openFailed(let message): String(localized: "無法讀取舊版啟動台資料庫：\(message)")
            case .noPages: String(localized: "舊版啟動台資料庫裡沒有任何頁面")
            }
        }
    }

    /// 目前使用者的舊版啟動台資料庫位置（不存在時為 nil）。
    static var databaseURL: URL? {
        var buffer = [CChar](repeating: 0, count: Int(PATH_MAX))
        guard confstr(_CS_DARWIN_USER_DIR, &buffer, buffer.count) > 0 else { return nil }
        let length = buffer.firstIndex(of: 0) ?? buffer.count
        let userDir = String(decoding: buffer[..<length].map { UInt8(bitPattern: $0) }, as: UTF8.self)
        let url = URL(fileURLWithPath: userDir).appending(path: "com.apple.dock.launchpad/db/db")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// 讀出舊版啟動台的頁面結構。
    /// - Parameter url: 資料庫檔案
    /// - Returns: 各頁的項目（依原本順序）
    /// - Throws: `ImportError`
    static func read(at url: URL) throws -> [[ImportedItem]] {
        var db: OpaquePointer?
        let uri = "file:\(url.path)?immutable=1"
        guard sqlite3_open_v2(uri, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, nil) == SQLITE_OK, let db else {
            let message = db.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
            sqlite3_close(db)
            throw ImportError.openFailed(message)
        }
        defer { sqlite3_close(db) }

        struct Row {
            let id: Int64
            let uuid: String
            let type: Int32
            let parent: Int64
            let ordering: Int64
            let bundleID: String?
            let appTitle: String?
            let groupTitle: String?
        }

        let sql = """
            SELECT i.rowid, i.uuid, i.type, i.parent_id, i.ordering, a.bundleid, a.title, g.title
            FROM items i
            LEFT JOIN apps a ON a.item_id = i.rowid
            LEFT JOIN groups g ON g.item_id = i.rowid
            """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw ImportError.openFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(statement) }

        func text(_ column: Int32) -> String? {
            guard let raw = sqlite3_column_text(statement, column) else { return nil }
            let value = String(cString: raw)
            return value.isEmpty ? nil : value
        }

        var rows: [Row] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            rows.append(Row(
                id: sqlite3_column_int64(statement, 0),
                uuid: text(1) ?? "",
                type: sqlite3_column_int(statement, 2),
                parent: sqlite3_column_int64(statement, 3),
                ordering: sqlite3_column_int64(statement, 4),
                bundleID: text(5),
                appTitle: text(6),
                groupTitle: text(7)
            ))
        }

        var children: [Int64: [Row]] = [:]
        for row in rows { children[row.parent, default: []].append(row) }
        for key in children.keys { children[key]?.sort { $0.ordering < $1.ordering } }

        guard let root = rows.first(where: { $0.uuid == "ROOTPAGE" }) else { throw ImportError.noPages }
        let pages = (children[root.id] ?? []).filter { $0.type == 3 && !$0.uuid.hasPrefix("HOLDINGPAGE") }

        var result: [[ImportedItem]] = []
        for page in pages {
            var items: [ImportedItem] = []
            for row in children[page.id] ?? [] {
                switch row.type {
                case 4:
                    items.append(.app(bundleID: row.bundleID, title: row.appTitle))
                case 2:
                    // 資料夾底下是它自己的頁，頁底下才是 App
                    let apps = (children[row.id] ?? []).filter { $0.type == 3 }
                        .flatMap { children[$0.id] ?? [] }
                        .filter { $0.type == 4 }
                        .map { ImportedApp(bundleID: $0.bundleID, title: $0.appTitle) }
                    items.append(.folder(title: row.groupTitle ?? "", apps: apps))
                default:
                    continue
                }
            }
            if !items.isEmpty { result.append(items) }
        }
        guard !result.isEmpty else { throw ImportError.noPages }
        return result
    }

    /// 把舊版排列對應到目前安裝的 App，產生新版面。
    /// 對不到的 App（已刪除）略過；舊版沒有的 App（之後才安裝）由 `Layout.reconcile` 補在最後。
    /// - Parameters:
    ///   - imported: `read(at:)` 的結果
    ///   - entries: 目前安裝的 App
    ///   - hidden: 使用者隱藏的 App
    ///   - capacity: 每頁容量（舊版每頁若超過會自動擠到下一頁）
    /// - Returns: 新版面
    static func makeLayout(from imported: [[ImportedItem]], entries: [AppEntry], hidden: Set<String>, capacity: Int) -> Layout {
        var byBundleID: [String: String] = [:]
        var byName: [String: String] = [:]
        for entry in entries where !hidden.contains(entry.id) {
            if let bundleID = entry.bundleID?.lowercased(), byBundleID[bundleID] == nil { byBundleID[bundleID] = entry.id }
            if byName[entry.name] == nil { byName[entry.name] = entry.id }
        }
        var used = Set<String>()

        func resolve(_ bundleID: String?, _ title: String?) -> String? {
            let id = bundleID.flatMap { byBundleID[$0.lowercased()] } ?? title.flatMap { byName[$0] }
            guard let id, used.insert(id).inserted else { return nil }
            return id
        }

        var layout = Layout(pages: [])
        for page in imported {
            var items: [LayoutItem] = []
            for item in page {
                switch item {
                case .app(let bundleID, let title):
                    if let id = resolve(bundleID, title) { items.append(.app(id)) }
                case .folder(let title, let apps):
                    let ids = apps.compactMap { resolve($0.bundleID, $0.title) }
                    if ids.count >= 2 {
                        items.append(.folder(FolderData(name: title.isEmpty ? String(localized: "資料夾") : title, apps: ids)))
                    } else if let only = ids.first {
                        items.append(.app(only))
                    }
                }
            }
            if !items.isEmpty {
                // 每個舊頁從新的一頁開始，保留使用者原本的分頁意圖
                layout.pages.append(items)
                layout.cascade(from: layout.pages.count - 1, capacity: capacity)
            }
        }
        layout.reconcile(installed: entries.map(\.id), hidden: hidden, capacity: capacity)
        return layout
    }
}
