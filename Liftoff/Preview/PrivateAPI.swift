//
//  PrivateAPI.swift
//  Liftoff（沿用自 DockLens，已在 DockLens 實測驗證）
//
//  集中管理所有 macOS 私有 API 的橋接。
//  - SkyLight 函式一律以 dlopen/dlsym 動態取得：不必連結私有框架，符號不存在時也能優雅退回公開 API。
//  - HIServices 的 `_AXUIElementGetWindow`、`GetProcessForPID` 屬於已連結的公開框架，直接用 @_silgen_name 宣告。
//  這些 API 皆為 AltTab、Hammerspoon 等開源工具長年使用的做法，但 Apple 可能隨時變更，呼叫端都必須準備 fallback。
//

import AppKit
import ApplicationServices

// MARK: - HIServices（已連結框架中的未公開符號）

/// 由 AX 視窗元素取得對應的 CGWindowID（公開 API 沒有提供這個對應關係）。
/// - Parameters:
///   - element: AX 視窗元素
///   - windowID: 輸出的 CGWindowID
/// - Returns: AXError，`.success` 代表成功
@_silgen_name("_AXUIElementGetWindow")
nonisolated func _AXUIElementGetWindow(_ element: AXUIElement, _ windowID: UnsafeMutablePointer<CGWindowID>) -> AXError

/// 以 pid 取得 ProcessSerialNumber（Swift 端已標為 unavailable，但符號仍存在；SkyLight 的聚焦函式需要 PSN）。
@_silgen_name("GetProcessForPID")
nonisolated func _GetProcessForPID(_ pid: pid_t, _ psn: UnsafeMutablePointer<ProcessSerialNumber>) -> OSStatus

// MARK: - SkyLight（動態載入）

/// SkyLight 私有函式的動態載入器。所有成員皆為 `nonisolated`，可在任何執行緒呼叫。
nonisolated enum SkyLight {
    private typealias MainConnectionFn = @convention(c) () -> Int32
    private typealias HWCaptureFn = @convention(c) (Int32, UnsafeMutablePointer<CGWindowID>, UInt32, UInt32) -> Unmanaged<CFArray>?
    private typealias SetFrontProcessFn = @convention(c) (UnsafeMutablePointer<ProcessSerialNumber>, CGWindowID, UInt32) -> CGError
    private typealias PostEventRecordFn = @convention(c) (UnsafeMutablePointer<ProcessSerialNumber>, UnsafeMutablePointer<UInt8>) -> CGError
    private typealias CopySpacesFn = @convention(c) (Int32, Int32, CFArray) -> Unmanaged<CFArray>?

    /// dlopen handle 只在首次存取時初始化一次，之後唯讀，因此標 unsafe 是安全的。
    nonisolated(unsafe) private static let handle: UnsafeMutableRawPointer? =
        dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)

    private static func symbol<T>(_ name: String, as type: T.Type) -> T? {
        guard let handle, let sym = dlsym(handle, name) else { return nil }
        return unsafeBitCast(sym, to: type)
    }

    private static let mainConnectionFn = symbol("SLSMainConnectionID", as: MainConnectionFn.self)
    private static let hwCaptureFn = symbol("CGSHWCaptureWindowList", as: HWCaptureFn.self)
    private static let setFrontProcessFn = symbol("_SLPSSetFrontProcessWithOptions", as: SetFrontProcessFn.self)
    private static let postEventRecordFn = symbol("SLPSPostEventRecordTo", as: PostEventRecordFn.self)
    private static let copySpacesFn = symbol("SLSCopySpacesForWindows", as: CopySpacesFn.self)

    /// 與 WindowServer 的連線 ID；整個 process 共用同一條，取一次即可。
    private static let connectionID: Int32? = mainConnectionFn?()

    /// 高速截圖是否可用（符號存在且取得連線）。
    static var canCaptureWindows: Bool { hwCaptureFn != nil && connectionID != nil }

    /// `CGSHWCaptureWindowList` 的選項位元。
    /// - ignoreGlobalClipShape: 忽略圓角/陰影裁切，拿到完整視窗內容
    /// - nominalResolution: 以「點」為單位的 1x 解析度輸出，比 Retina 2x 快且縮圖綽綽有餘
    private static let captureOptions: UInt32 = (1 << 11) | (1 << 9)

    /// 以 WindowServer 私有 API 擷取單一視窗影像。
    ///
    /// 實測（M 系列、macOS 27）約 20ms/窗，是 ScreenCaptureKit 單張截圖（~70ms）的 3 倍以上快，
    /// 且可擷取其他桌面（Space）上、未顯示在螢幕上的視窗。WindowServer 內部序列化，多執行緒並行無加速效果。
    /// - Parameter windowID: 目標視窗
    /// - Returns: 視窗影像；私有 API 不可用或擷取失敗時回傳 nil（呼叫端應退回 ScreenCaptureKit）
    static func captureWindow(_ windowID: CGWindowID) -> CGImage? {
        guard let hwCaptureFn, let connectionID else { return nil }
        var wid = windowID
        guard let array = hwCaptureFn(connectionID, &wid, 1, captureOptions)?.takeRetainedValue() as? [CGImage] else {
            return nil
        }
        return array.first
    }

    /// 查詢視窗所屬的桌面（Space）。
    /// 用途：分辨「在其他桌面上的真實視窗」與「被收起（ordered out）的隱藏輔助視窗」——後者不屬於任何桌面。
    /// - Parameter windowID: 目標視窗
    /// - Returns: 所屬 Space ID；私有 API 不可用時為 nil（呼叫端應改用較保守的判斷）
    static func spaces(for windowID: CGWindowID) -> [Int]? {
        guard let copySpacesFn, let connectionID else { return nil }
        // mask 7：目前、其他、全螢幕等所有類型的 Space
        return copySpacesFn(connectionID, 7, [windowID] as CFArray)?.takeRetainedValue() as? [Int] ?? []
    }

    /// 將指定 process 帶到最前並把指定視窗設為 key window。
    ///
    /// 為什麼不用 `NSRunningApplication.activate()`：macOS 14 起的「協作式啟用」會拒絕背景 agent 搶焦點，
    /// 而且它無法指定「哪一個視窗」。這裡沿用 AltTab/Hammerspoon 的作法：`_SLPSSetFrontProcessWithOptions`
    /// 指定視窗前置，再送兩筆合成事件紀錄讓該視窗成為 key window（位元組版面來自逆向工程）。
    /// - Parameters:
    ///   - pid: 目標 App 的 pid
    ///   - windowID: 要成為 key 的視窗
    /// - Returns: 私有 API 是否可用且呼叫成功；false 時呼叫端應退回公開 API
    @discardableResult
    static func focus(pid: pid_t, windowID: CGWindowID) -> Bool {
        guard let setFrontProcessFn, let postEventRecordFn else { return false }
        var psn = ProcessSerialNumber()
        guard _GetProcessForPID(pid, &psn) == noErr else { return false }

        // 0x200 = kCPSUserGenerated：讓系統視為使用者操作，才會切換到視窗所在的 Space
        guard setFrontProcessFn(&psn, windowID, 0x200) == .success else { return false }

        var bytes = [UInt8](repeating: 0, count: 0xF8)
        bytes[0x04] = 0xF8
        bytes[0x3A] = 0x10
        withUnsafeBytes(of: windowID) { raw in
            for (offset, byte) in raw.enumerated() { bytes[0x3C + offset] = byte }
        }
        for i in 0x20..<0x30 { bytes[i] = 0xFF }
        bytes[0x08] = 0x01
        _ = bytes.withUnsafeMutableBufferPointer { postEventRecordFn(&psn, $0.baseAddress!) }
        bytes[0x08] = 0x02
        _ = bytes.withUnsafeMutableBufferPointer { postEventRecordFn(&psn, $0.baseAddress!) }
        return true
    }
}
