//
//  RunningApps.swift
//  Liftoff
//
//  追蹤哪些 App 正在執行（圖示下方顯示小圓點、決定能否預覽視窗）。
//  只在 App 啟動/結束的系統通知時重算一次，不輪詢。
//

import AppKit
import Observation

@Observable
final class RunningApps {
    /// 執行中 App 的識別鍵
    private(set) var ids: Set<String> = []

    @ObservationIgnored private var byID: [String: NSRunningApplication] = [:]
    @ObservationIgnored private weak var catalog: AppCatalog?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    /// 開始追蹤。
    func start(catalog: AppCatalog) {
        self.catalog = catalog
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            })
        }
        refresh()
    }

    /// 重新對照執行中 App 與 App 清單（App 清單變動後也要呼叫）。
    func refresh() {
        guard let catalog else { return }
        var map: [String: NSRunningApplication] = [:]
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular || app.activationPolicy == .accessory {
            guard let id = catalog.id(forBundleURL: app.bundleURL, bundleID: app.bundleIdentifier) else { continue }
            // 同一 App 多個實例時取最早啟動的（通常是主要那個）
            if map[id] == nil { map[id] = app }
        }
        byID = map
        idsByPID = Dictionary(map.map { ($0.value.processIdentifier, $0.key) }, uniquingKeysWith: { first, _ in first })
        let newIDs = Set(map.keys)
        if newIDs != ids { ids = newIDs }
    }

    /// 執行中 App 的 pid → 識別鍵（搜尋視窗標題時用來認領視窗；只含 App 清單裡的 App，不含背景程序）。
    /// 在 refresh 時就算好：搜尋時現算要逐一讀 NSRunningApplication 的屬性，實測主執行緒約 2ms。
    @ObservationIgnored private(set) var idsByPID: [pid_t: String] = [:]

    func application(for id: String) -> NSRunningApplication? {
        guard let app = byID[id], !app.isTerminated else { return nil }
        return app
    }
}
