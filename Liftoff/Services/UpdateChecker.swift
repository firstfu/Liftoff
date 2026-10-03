//
//  UpdateChecker.swift
//  Liftoff
//
//  檢查 GitHub 上有沒有新版本。Liftoff 對外承諾「不主動連網」，所以：
//  - 只有使用者按「檢查更新」，或自己打開「每週自動檢查」時才連線；預設不連。
//  - 只發一個請求到 GitHub API 讀最新版本號，不送出任何使用者資料（沒有自訂 header、沒有識別碼）。
//  - 自動檢查交給 NSBackgroundActivityScheduler：由系統挑空檔、合併喚醒，不自己跑計時器，閒置 0% CPU 的紅線不受影響。
//

import AppKit
import Observation

/// 檢查更新的狀態。
nonisolated enum UpdateStatus: Equatable, Sendable {
    case idle
    case checking
    /// 已是最新版本
    case upToDate
    /// 有新版本（版本號、下載頁）
    case available(version: String, url: URL)
    /// 連線或解析失敗
    case failed
}

@Observable
final class UpdateChecker {
    /// GitHub「最新正式版」API（不含 draft／prerelease）
    nonisolated static let latestReleaseAPI = URL(string: "https://api.github.com/repos/firstfu/Liftoff/releases/latest")!
    /// 自動檢查的間隔
    nonisolated static let autoInterval: TimeInterval = 7 * 24 * 60 * 60

    private(set) var status: UpdateStatus = .idle
    /// 目前版本（Info.plist 的 CFBundleShortVersionString）
    let currentVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"

    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private var scheduler: NSBackgroundActivityScheduler?

    init(settings: AppSettings) {
        self.settings = settings
    }

    /// 是否有新版本（選單用）
    var availableUpdate: (version: String, url: URL)? {
        if case .available(let version, let url) = status { return (version, url) }
        return nil
    }

    /// 依設定啟用或停用自動檢查；啟用時若距上次檢查已超過間隔，立即檢查一次。
    func applyAutoCheckSetting() {
        scheduler?.invalidate()
        scheduler = nil
        guard settings.autoChecksForUpdates else { return }
        if let last = settings.lastUpdateCheck, Date.now.timeIntervalSince(last) < Self.autoInterval {
            Log.app.notice("自動檢查更新：距上次檢查未滿間隔，略過")
        } else {
            Task { await check() }
        }
        let scheduler = NSBackgroundActivityScheduler(identifier: "\(Log.subsystem).update-check")
        scheduler.repeats = true
        scheduler.interval = Self.autoInterval
        // 容許系統在一天內挑時間執行，盡量和其他工作合併喚醒
        scheduler.tolerance = 24 * 60 * 60
        scheduler.qualityOfService = .utility
        scheduler.schedule { [weak self] completion in
            Task { @MainActor in
                await self?.check()
                completion(.finished)
            }
        }
        self.scheduler = scheduler
    }

    /// 向 GitHub 查詢最新版本；結果寫進 `status`。
    func check() async {
        guard status != .checking else { return }
        status = .checking
        var request = URLRequest(url: Self.latestReleaseAPI, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  let release = Self.parseRelease(data) else {
                status = .failed
                return
            }
            settings.lastUpdateCheck = .now
            status = Self.isNewer(release.version, than: currentVersion)
                ? .available(version: release.version, url: release.url) : .upToDate
            Log.app.notice("檢查更新：最新 \(release.version, privacy: .public)、目前 \(self.currentVersion, privacy: .public)")
        } catch {
            Log.app.error("檢查更新失敗：\(error.localizedDescription, privacy: .public)")
            status = .failed
        }
    }

    /// 選單「檢查更新…」：查完後用對話框回報結果（有新版本時可直接去下載頁）。
    func checkAndAnnounce() async {
        await check()
        let alert = NSAlert()
        switch status {
        case .available(let version, let url):
            alert.messageText = String(localized: "有新版本：\(version)")
            alert.informativeText = AppInfo.versionDescription
            alert.addButton(withTitle: String(localized: "下載"))
            alert.addButton(withTitle: String(localized: "取消"))
            NSApp.activate()
            if alert.runModal() == .alertFirstButtonReturn { AppInfo.open(url) }
            return
        case .upToDate:
            alert.messageText = String(localized: "已是最新版本")
            alert.informativeText = AppInfo.versionDescription
        case .failed:
            alert.messageText = String(localized: "無法連線到 GitHub，請稍後再試")
        case .idle, .checking:
            return
        }
        NSApp.activate()
        alert.runModal()
    }

    // MARK: - 純邏輯（可測試）

    /// 從 GitHub release JSON 取出版本號（去掉開頭的 v）與網頁位址。
    /// - Returns: 解析失敗時為 nil
    nonisolated static func parseRelease(_ data: Data) -> (version: String, url: URL)? {
        struct Release: Decodable {
            let tag_name: String
            let html_url: URL
        }
        guard let release = try? JSONDecoder().decode(Release.self, from: data) else { return nil }
        let version = release.tag_name.hasPrefix("v") ? String(release.tag_name.dropFirst()) : release.tag_name
        return (version, release.html_url)
    }

    /// 以數字逐段比較版本號（1.0.10 > 1.0.9；缺少的段視為 0）。
    nonisolated static func isNewer(_ candidate: String, than current: String) -> Bool {
        func parts(_ version: String) -> [Int] {
            version.split(separator: ".").map { Int($0.prefix { $0.isNumber }) ?? 0 }
        }
        let a = parts(candidate), b = parts(current)
        for index in 0..<max(a.count, b.count) {
            let x = index < a.count ? a[index] : 0, y = index < b.count ? b[index] : 0
            if x != y { return x > y }
        }
        return false
    }
}
