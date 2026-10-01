//
//  Paths.swift
//  Liftoff
//
//  App 自己的檔案位置：設定以外的持久資料（佈局、App 索引、使用紀錄、備份）放 Application Support，
//  可重建的快取（圖示、模糊桌布）放 Caches，系統清理快取時不會影響使用者資料。
//

import Foundation

nonisolated enum Paths {
    static let bundleID = "com.firstfu.Liftoff"

    /// ~/Library/Application Support/Liftoff
    static let support: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return ensure(base.appending(path: "Liftoff", directoryHint: .isDirectory))
    }()

    /// ~/Library/Caches/com.firstfu.Liftoff
    static let caches: URL = {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return ensure(base.appending(path: bundleID, directoryHint: .isDirectory))
    }()

    static var layoutFile: URL { support.appending(path: "layout.json") }
    static var catalogFile: URL { support.appending(path: "catalog.json") }
    static var usageFile: URL { support.appending(path: "usage.json") }
    static var backups: URL { ensure(support.appending(path: "Backups", directoryHint: .isDirectory)) }
    static var iconCache: URL { ensure(caches.appending(path: "Icons", directoryHint: .isDirectory)) }
    static var selfTest: URL { ensure(caches.appending(path: "selftest", directoryHint: .isDirectory)) }

    /// 建立目錄（已存在則忽略）後回傳原路徑。
    @discardableResult
    static func ensure(_ url: URL) -> URL {
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// 以「暫存檔 + 原子替換」寫入，避免寫到一半當機留下壞檔。
    /// - Throws: 檔案系統錯誤
    static func writeAtomically(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: .atomic)
    }
}

/// FNV-1a 64 位元雜湊：快取檔名用（穩定、跨次啟動一致；Swift 內建 Hasher 每次啟動會換種子，不能用）。
nonisolated func stableHash(_ string: String) -> String {
    var hash: UInt64 = 0xcbf2_9ce4_8422_2325
    for byte in string.utf8 {
        hash ^= UInt64(byte)
        hash &*= 0x100_0000_01b3
    }
    return String(hash, radix: 16)
}
