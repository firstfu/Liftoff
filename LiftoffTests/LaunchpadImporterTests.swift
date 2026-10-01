//
//  LaunchpadImporterTests.swift
//  LiftoffTests
//
//  以與系統相同結構的 SQLite 檔驗證舊版啟動台匯入：頁序、資料夾、暫存頁排除、以 bundle ID / 名稱對應、
//  已刪除 App 略過、新安裝 App 補在最後。
//

import Foundation
import SQLite3
import Testing
@testable import Liftoff

@MainActor
struct LaunchpadImporterTests {
    /// 建立測試用資料庫：兩頁；第一頁有一個資料夾（含兩頁）與兩個 App；另有 HOLDINGPAGE 暫存頁。
    private func makeDatabase() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "lp-\(UUID().uuidString).db")
        var db: OpaquePointer?
        guard sqlite3_open(url.path, &db) == SQLITE_OK else { throw CocoaError(.fileWriteUnknown) }
        defer { sqlite3_close(db) }
        let sql = """
        CREATE TABLE items (rowid INTEGER PRIMARY KEY ASC, uuid VARCHAR, flags INTEGER, type INTEGER, parent_id INTEGER NOT NULL, ordering INTEGER);
        CREATE TABLE apps (item_id INTEGER PRIMARY KEY, title VARCHAR, bundleid VARCHAR, storeid VARCHAR, category_id INTEGER, moddate REAL, bookmark BLOB);
        CREATE TABLE groups (item_id INTEGER PRIMARY KEY, category_id INTEGER, title VARCHAR);
        INSERT INTO items VALUES (1,'ROOTPAGE',0,1,0,0);
        INSERT INTO items VALUES (2,'HOLDINGPAGE',0,3,1,0);
        INSERT INTO items VALUES (10,'P1',0,3,1,1);
        INSERT INTO items VALUES (11,'P2',0,3,1,2);
        INSERT INTO items VALUES (20,'G',0,2,10,0);
        INSERT INTO groups VALUES (20,0,'工作');
        INSERT INTO items VALUES (21,'GP1',0,3,20,0);
        INSERT INTO items VALUES (22,'GP2',0,3,20,1);
        INSERT INTO items VALUES (30,'A1',0,4,21,0);
        INSERT INTO apps VALUES (30,'Mail','com.apple.mail',NULL,0,0,NULL);
        INSERT INTO items VALUES (31,'A2',0,4,22,0);
        INSERT INTO apps VALUES (31,'Notes','com.apple.Notes',NULL,0,0,NULL);
        INSERT INTO items VALUES (32,'A3',0,4,10,2);
        INSERT INTO apps VALUES (32,'Safari','com.apple.Safari',NULL,0,0,NULL);
        INSERT INTO items VALUES (33,'A4',0,4,10,1);
        INSERT INTO apps VALUES (33,'Gone','com.example.gone',NULL,0,0,NULL);
        INSERT INTO items VALUES (34,'A5',0,4,11,0);
        INSERT INTO apps VALUES (34,'計算機',NULL,NULL,0,0,NULL);
        INSERT INTO items VALUES (35,'A6',0,4,2,0);
        INSERT INTO apps VALUES (35,'Holding','com.example.holding',NULL,0,0,NULL);
        """
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else { throw CocoaError(.fileWriteUnknown) }
        return url
    }

    private func entry(_ id: String, _ name: String, bundle: String?) -> AppEntry {
        AppEntry(id: id, bundleID: bundle, path: "/\(id).app", resolvedPath: "/\(id).app", name: name,
                 altNames: [], category: nil, modified: .distantPast)
    }

    @Test func readsPagesFoldersAndOrdering() throws {
        let url = try makeDatabase()
        defer { try? FileManager.default.removeItem(at: url) }
        let pages = try LaunchpadImporter.read(at: url)
        #expect(pages.count == 2)
        #expect(pages[0] == [
            .folder(title: "工作", apps: [.init(bundleID: "com.apple.mail", title: "Mail"), .init(bundleID: "com.apple.Notes", title: "Notes")]),
            .app(bundleID: "com.example.gone", title: "Gone"),
            .app(bundleID: "com.apple.Safari", title: "Safari"),
        ])
        #expect(pages[1] == [.app(bundleID: nil, title: "計算機")])
    }

    @Test func mapsToInstalledAppsAndAppendsNewOnes() throws {
        let url = try makeDatabase()
        defer { try? FileManager.default.removeItem(at: url) }
        let entries = [
            entry("com.apple.Safari", "Safari", bundle: "com.apple.Safari"),
            entry("com.apple.mail", "郵件", bundle: "com.apple.mail"),
            entry("com.apple.Notes", "備忘錄", bundle: "com.apple.notes"),   // 大小寫不同也要對得到
            entry("calc", "計算機", bundle: nil),                             // 沒有 bundle ID 時以名稱對應
            entry("com.new.app", "New", bundle: "com.new.app"),             // 舊版沒有 → 補在最後
        ]
        let layout = LaunchpadImporter.makeLayout(from: try LaunchpadImporter.read(at: url), entries: entries, hidden: [], capacity: 10)
        #expect(layout.pages.count == 2)
        let folder = try #require(layout.pages[0].first?.folder)
        #expect(folder.name == "工作")
        #expect(folder.apps == ["com.apple.mail", "com.apple.Notes"])
        #expect(layout.pages[0].dropFirst().map(\.id) == ["com.apple.Safari"])
        #expect(layout.pages[1].map(\.id) == ["calc", "com.new.app"])
    }

    @Test func missingDatabaseThrows() {
        #expect(throws: (any Error).self) {
            try LaunchpadImporter.read(at: URL(fileURLWithPath: "/nonexistent/db"))
        }
    }
}
