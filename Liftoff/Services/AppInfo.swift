//
//  AppInfo.swift
//  Liftoff
//
//  版本資訊與對外連結（官網、Release、回報問題）。
//  App 自己不連網：「檢查更新」「回報問題」只是請系統用瀏覽器打開網址，要不要送出由使用者決定，
//  這樣才不違背「完全不連網」的隱私承諾。
//

import AppKit

enum AppInfo {
    static let repository = URL(string: "https://github.com/firstfu/Liftoff")!
    static let website = URL(string: "https://firstfu.github.io/Liftoff/")!
    static let latestRelease = URL(string: "https://github.com/firstfu/Liftoff/releases/latest")!

    /// 版本字串，例如「1.1.0 (4)」；讀不到時只顯示「—」。
    static var versionDescription: String {
        let info = Bundle.main.infoDictionary
        guard let version = info?["CFBundleShortVersionString"] as? String else { return "—" }
        guard let build = info?["CFBundleVersion"] as? String else { return version }
        return "\(version) (\(build))"
    }

    /// 回報問題的網址：預填 bug 模板的「macOS 版本」欄位。
    /// 欄位 id 是 `macos`（見 .github/ISSUE_TEMPLATE/bug_report.yml）；模板改欄位 id 時這裡要一起改，否則只是不預填、不會壞。
    static var reportProblemURL: URL {
        var components = URLComponents(string: repository.absoluteString + "/issues/new")!
        let system = ProcessInfo.processInfo.operatingSystemVersion
        components.queryItems = [
            URLQueryItem(name: "template", value: "bug_report.yml"),
            URLQueryItem(name: "macos", value: "macOS \(system.majorVersion).\(system.minorVersion).\(system.patchVersion), Liftoff \(versionDescription)"),
        ]
        return components.url ?? repository
    }

    /// 用預設瀏覽器打開網址。
    static func open(_ url: URL) {
        NSWorkspace.shared.open(url)
    }
}
