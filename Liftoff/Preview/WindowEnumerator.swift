//
//  WindowEnumerator.swift
//  Liftoff（沿用自 DockLens，已在 DockLens 實測驗證）
//
//  列舉某個 App 目前有哪些「使用者看得到的視窗」。
//  資料來源合併兩者：
//  - Accessibility（AX）：權威清單，能分辨標準視窗/對話框、知道是否最小化、並提供關閉/縮小等操作入口；
//    但只回傳「目前桌面（Space）」上的視窗。
//  - CGWindowList：涵蓋所有 Space，也提供前後層次（z-order）；但混有大量隱藏的輔助視窗（例如自動填寫面板）。
//  以 AX 為主、CG 補上其他 Space 的具名視窗，兼顧正確性與完整性。
//

import AppKit

/// 單一視窗的快照資訊。
nonisolated struct WindowInfo: Identifiable, Sendable, Equatable {
    let id: CGWindowID
    let pid: pid_t
    var title: String
    /// 視窗外框（points、CG 全域座標）
    var frame: CGRect
    var isMinimized: Bool
    /// 視窗是否位於其他桌面（Space）；此類視窗沒有 AX 元素，無法關閉/縮小，只能切換過去
    var isOnOtherSpace: Bool
    /// AX 元素，供關閉/縮小/前置等操作；其他 Space 的視窗為 nil
    let ax: AXRef?

    /// 視窗寬高比，用來決定縮圖卡片大小（在影像還沒拍到前就能先排版，避免面板跳動）
    var aspectRatio: CGFloat {
        guard frame.height > 1 else { return 16.0 / 10.0 }
        return frame.width / frame.height
    }

    static func == (lhs: WindowInfo, rhs: WindowInfo) -> Bool {
        lhs.id == rhs.id && lhs.title == rhs.title && lhs.frame == rhs.frame
            && lhs.isMinimized == rhs.isMinimized && lhs.isOnOtherSpace == rhs.isOnOtherSpace
    }
}

nonisolated enum WindowEnumerator {
    /// 小於此尺寸的視窗視為工具面板/雜訊，不列入預覽
    private static let minimumSide: CGFloat = 60
    /// AX 呼叫逾時：遇到卡死的 App 時避免拖住整個預覽（系統預設高達 6 秒）。
    /// 不能設太短：系統忙碌時正常 App 也可能要數百毫秒才回應（實測負載 9 時超過 0.25 秒），太短會誤判成沒有視窗。
    private static let axTimeout: Float = 1.0

    /// 列舉指定 App 的可預覽視窗，依「最近使用」排序（最前面的視窗在前、最小化視窗在後）。
    ///
    /// 成本：CGWindowList ~2–3ms + 每個視窗數個 AX IPC，通常 < 10ms；請在背景執行緒呼叫。
    /// - Parameters:
    ///   - pid: 目標 App 的 pid
    ///   - includeOtherSpaces: 是否納入其他桌面上的視窗
    /// - Returns: 視窗清單（可能為空）
    static func windows(for pid: pid_t, includeOtherSpaces: Bool) -> [WindowInfo] {
        let cgWindows = cgWindowList(for: pid)
        // 權限查詢每次都是一趟 TCC IPC：整次列舉只查一次，不在逐視窗的迴圈裡重查
        let trusted = AXIsProcessTrusted()
        // CGWindowList 由前到後排列，索引即 z-order
        var zOrder: [CGWindowID: Int] = [:]
        for (index, entry) in cgWindows.enumerated() { zOrder[entry.id] = index }
        let cgByID = Dictionary(cgWindows.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, axTimeout)
        var rawWindows: CFTypeRef?
        let axStatus = AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &rawWindows)
        let axWindows = (rawWindows as? [AXUIElement]) ?? []

        var result: [WindowInfo] = []
        var seen = Set<CGWindowID>()
        let attributes = [
            kAXRoleAttribute as String, kAXSubroleAttribute as String, kAXMinimizedAttribute as String,
            kAXTitleAttribute as String, kAXPositionAttribute as String, kAXSizeAttribute as String,
        ]
        for window in axWindows {
            // 每個視窗只做一次批次 IPC，而非 6 次個別呼叫
            let values = window.values(attributes)
            guard values[kAXRoleAttribute as String] as? String == kAXWindowRole as String,
                  let subrole = values[kAXSubroleAttribute as String] as? String,
                  subrole == kAXStandardWindowSubrole as String || subrole == kAXDialogSubrole as String,
                  let id = window.windowID, !seen.contains(id) else { continue }
            let cg = cgByID[id]
            let minimized = values[kAXMinimizedAttribute as String] as? Bool ?? false
            // 非最小化卻不存在於 CG 清單的，多半是已關閉但 AX 尚未更新的殭屍元素
            guard cg != nil || minimized else { continue }
            let axFrame: CGRect? = {
                guard let origin = AXUIElement.point(values[kAXPositionAttribute as String]),
                      let size = AXUIElement.size(values[kAXSizeAttribute as String]) else { return nil }
                return CGRect(origin: origin, size: size)
            }()
            let frame = cg?.frame ?? axFrame ?? .zero
            guard frame.width >= minimumSide, frame.height >= minimumSide else { continue }

            seen.insert(id)
            let axTitle = values[kAXTitleAttribute as String] as? String ?? ""
            result.append(WindowInfo(
                id: id, pid: pid,
                title: axTitle.isEmpty ? (cg?.title ?? "") : axTitle,
                frame: frame,
                isMinimized: minimized,
                isOnOtherSpace: false,
                ax: AXRef(element: window)
            ))
        }

        // AX 查詢失敗（App 忙碌逾時、不支援輔助使用）時，改以 CG 清單中「畫面上、具標題」的視窗補上，
        // 至少能預覽與切換（沒有 AX 元素就無法關閉/縮小）
        if axStatus != .success && axStatus != .noValue {
            for cg in cgWindows where !seen.contains(cg.id) && cg.isOnScreen && !cg.title.isEmpty
                && cg.frame.width >= minimumSide && cg.frame.height >= minimumSide {
                seen.insert(cg.id)
                result.append(WindowInfo(
                    id: cg.id, pid: pid, title: cg.title, frame: cg.frame,
                    isMinimized: false, isOnOtherSpace: false, ax: nil
                ))
            }
        }

        // 沒有輔助使用權限時 AX 拿不到任何視窗：退回只用 CGWindowList 列出畫面上的一般視窗
        // （無法得知最小化視窗，也無法指定前置哪一個視窗，但縮圖預覽仍可用）
        if !trusted {
            for cg in cgWindows where !seen.contains(cg.id) && cg.isOnScreen
                && cg.frame.width >= minimumSide * 2 && cg.frame.height >= minimumSide * 2 {
                seen.insert(cg.id)
                result.append(WindowInfo(
                    id: cg.id, pid: pid, title: cg.title, frame: cg.frame,
                    isMinimized: false, isOnOtherSpace: false, ax: nil
                ))
            }
        }

        if includeOtherSpaces {
            // 其他桌面（Space）上的視窗：AX 看不到、不在畫面上、一般層級且夠大。
            // 以「是否屬於某個 Space」排除被收起的隱藏輔助視窗（例如 Electron 的 500×500 隱藏視窗）；
            // 私有 API 不可用時退回「具標題」的保守條件。
            for cg in cgWindows where !seen.contains(cg.id) && !cg.isOnScreen
                && cg.frame.width >= 200 && cg.frame.height >= 150 {
                if let spaces = SkyLight.spaces(for: cg.id) {
                    guard !spaces.isEmpty else { continue }
                } else if cg.title.isEmpty {
                    continue
                }
                // 沒有輔助使用權限時無法用 AX 確認是不是真正的視窗；其他桌面上沒有標題的多半是隱藏輔助視窗
                //（例如 Chrome 的背景視窗，截出來是空白），有螢幕錄製權限時真正的視窗都讀得到標題
                if !trusted, cg.title.isEmpty, CGPreflightScreenCaptureAccess() { continue }
                seen.insert(cg.id)
                result.append(WindowInfo(
                    id: cg.id, pid: pid, title: cg.title, frame: cg.frame,
                    isMinimized: false, isOnOtherSpace: true, ax: nil
                ))
            }
        }

        result.sort { lhs, rhs in
            if lhs.isMinimized != rhs.isMinimized { return !lhs.isMinimized }
            return (zOrder[lhs.id] ?? .max) < (zOrder[rhs.id] ?? .max)
        }
        return result
    }

    // MARK: - CGWindowList

    private struct CGEntry {
        let id: CGWindowID
        let title: String
        let frame: CGRect
        let isOnScreen: Bool
    }

    /// 取得指定 pid 的一般層級（layer 0）、非全透明視窗。
    private static func cgWindowList(for pid: pid_t) -> [CGEntry] {
        guard let list = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] else { return [] }
        var entries: [CGEntry] = []
        for info in list {
            guard (info[kCGWindowOwnerPID as String] as? pid_t) == pid,
                  (info[kCGWindowLayer as String] as? Int) == 0,
                  (info[kCGWindowAlpha as String] as? Double ?? 1) > 0.01,
                  let id = info[kCGWindowNumber as String] as? CGWindowID,
                  let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict) else { continue }
            entries.append(CGEntry(
                id: id,
                title: info[kCGWindowName as String] as? String ?? "",
                frame: bounds,
                isOnScreen: info[kCGWindowIsOnscreen as String] as? Bool ?? false
            ))
        }
        return entries
    }
}
