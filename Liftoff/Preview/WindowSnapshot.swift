//
//  WindowSnapshot.swift
//  Liftoff
//
//  搜尋視窗標題用的快照：每次打開啟動台時在背景呼叫一次 CGWindowList，拍下所有執行中 App 的具名視窗。
//  只用一次 CGWindowList（涵蓋所有桌面），不對每個 App 做 AX 列舉——AX 只看得到目前桌面、而且每個 App 都要 IPC；
//  真正要切換時才針對那一個 pid 用 AX 取得視窗元素（見 LaunchpadModel.switchToWindow）。
//  讀取視窗標題需要螢幕錄製權限；沒有權限時標題都是空的，這個功能就安靜地沒有結果。
//

import AppKit

/// CGWindowList 裡的一個視窗（過濾前）。
nonisolated struct WindowCandidate: Sendable {
    let windowID: CGWindowID
    let pid: pid_t
    let title: String
    let frame: CGRect
    let isOnScreen: Bool
    /// 視窗所屬的桌面；nil 表示沒查（在畫面上）或私有 API 不可用
    let spaces: [Int]?
}

nonisolated enum WindowSnapshot {
    /// 小於此尺寸的視為工具面板或隱藏的輔助視窗
    static let minimumSize = CGSize(width: 200, height: 150)

    /// 拍下目前所有執行中 App 的具名視窗（請在背景執行緒呼叫）。
    /// - Parameter apps: pid → (App 識別鍵, 顯示名稱)，只收這些 App 的視窗（排除 Liftoff 自己與背景程序）
    /// - Returns: 可搜尋的視窗，依前後層次排列（最前面的在前）
    static func capture(apps: [pid_t: (id: String, name: String)]) -> [WindowHit] {
        guard !apps.isEmpty,
              let list = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        else { return [] }
        var candidates: [WindowCandidate] = []
        let currentSpaces = SkyLight.currentSpaceIDs()
        for info in list {
            guard (info[kCGWindowLayer as String] as? Int) == 0,
                  let pid = info[kCGWindowOwnerPID as String] as? pid_t, apps[pid] != nil,
                  let title = info[kCGWindowName as String] as? String, !title.isEmpty,
                  (info[kCGWindowAlpha as String] as? Double ?? 1) > 0.01,
                  let id = info[kCGWindowNumber as String] as? CGWindowID,
                  let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict) else { continue }
            let onScreen = info[kCGWindowIsOnscreen as String] as? Bool ?? false
            candidates.append(WindowCandidate(
                windowID: id, pid: pid, title: title, frame: bounds, isOnScreen: onScreen,
                // 只有不在畫面上的視窗才需要查桌面（私有 API，逐一呼叫），畫面上的直接收
                spaces: onScreen ? nil : SkyLight.spaces(for: id)
            ))
        }
        // 在目前桌面卻不在畫面上的視窗：只對這些 App 用 AX 確認哪些是真的視窗（通常只有零到兩個 App）
        let suspectPIDs = Set(candidates.filter { needsAXCheck($0, currentSpaces: currentSpaces) }.map(\.pid))
        var axVisible = Set<CGWindowID>()
        for pid in suspectPIDs { axVisible.formUnion(axWindowIDs(pid: pid)) }
        return hits(from: candidates, apps: apps, currentSpaces: currentSpaces, axVisible: axVisible)
    }

    /// 不在畫面上、卻屬於某個螢幕目前顯示中的桌面：可能是最小化、App 被隱藏（⌘H），或被 App 收起的幽靈視窗
    /// （實測：備忘錄關掉的視窗仍以原標題留在 CGWindowList 與目前桌面上，AX 看不到），要用 AX 分辨——
    /// 前兩者 AX 列得出來，幽靈視窗列不出來。
    static func needsAXCheck(_ candidate: WindowCandidate, currentSpaces: Set<Int>?) -> Bool {
        guard !candidate.isOnScreen, let spaces = candidate.spaces, let currentSpaces else { return false }
        return !currentSpaces.isDisjoint(with: spaces)
    }

    /// 用 AX 列出某個 App 的視窗 ID（背景執行緒呼叫；只有一次 IPC，卡住的 App 最多等 0.5 秒）。
    /// 視窗 ID 由 `_AXUIElementGetWindow` 在本地取得，不必逐一再問 App。
    private static func axWindowIDs(pid: pid_t) -> Set<CGWindowID> {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.5)
        guard let windows: [AXUIElement] = app.value(kAXWindowsAttribute) else { return [] }
        return Set(windows.compactMap(\.windowID))
    }

    /// 過濾規則（純函式，供測試）：
    /// - 要有標題、夠大
    /// - 不在畫面上的：不屬於任何桌面的（被收起的隱藏輔助視窗）不收；屬於目前桌面的必須是 AX 列得出來的視窗
    ///   （最小化或 App 被隱藏；否則是關掉後殘留的幽靈視窗）；在其他桌面的收下。無從得知桌面時保守收下（已要求有標題與尺寸）
    /// - 標題就是 App 名稱的不收（例如「行事曆」視窗）：跟 App 本身的搜尋結果重複
    /// - Parameters:
    ///   - candidates: CGWindowList 的視窗，依前後層次排列
    ///   - apps: pid → (App 識別鍵, 顯示名稱)
    ///   - currentSpaces: 各螢幕目前的桌面；nil 表示無從得知
    ///   - axVisible: 需要確認的 App 中，AX 列得出來的視窗
    /// - Returns: 可搜尋的視窗
    static func hits(from candidates: [WindowCandidate], apps: [pid_t: (id: String, name: String)],
                     currentSpaces: Set<Int>? = nil, axVisible: Set<CGWindowID> = []) -> [WindowHit] {
        var result: [WindowHit] = []
        var seen = Set<CGWindowID>()
        for candidate in candidates {
            guard let app = apps[candidate.pid], seen.insert(candidate.windowID).inserted,
                  candidate.frame.width >= minimumSize.width, candidate.frame.height >= minimumSize.height else { continue }
            if !candidate.isOnScreen, let spaces = candidate.spaces, spaces.isEmpty { continue }
            if needsAXCheck(candidate, currentSpaces: currentSpaces), !axVisible.contains(candidate.windowID) { continue }
            let title = candidate.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty, SearchIndex.normalize(title) != SearchIndex.normalize(app.name) else { continue }
            result.append(WindowHit(windowID: candidate.windowID, pid: candidate.pid, appID: app.id, title: title))
        }
        return result
    }
}
