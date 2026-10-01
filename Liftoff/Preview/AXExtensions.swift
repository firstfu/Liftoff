//
//  AXExtensions.swift
//  Liftoff（沿用自 DockLens，已在 DockLens 實測驗證）
//
//  AXUIElement 的型別安全存取封裝。AX API 是跨 process 的 IPC 呼叫、本身執行緒安全，
//  因此這裡全部標為 nonisolated，讓視窗列舉可以在背景執行緒進行、不卡主執行緒。
//

import ApplicationServices
import CoreGraphics

/// 可跨 concurrency domain 傳遞的 AXUIElement 包裝。
/// AXUIElement 是不可變的 CF 參照、AX 呼叫由系統保證執行緒安全，故以 @unchecked Sendable 標示。
nonisolated struct AXRef: @unchecked Sendable {
    let element: AXUIElement
}

nonisolated extension AXUIElement {
    /// 讀取任意 AX 屬性並轉型。
    /// - Parameter name: 屬性名稱（例如 `kAXTitleAttribute`）
    /// - Returns: 成功且型別相符時回傳值，否則 nil
    func value<T>(_ name: String) -> T? {
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(self, name as CFString, &raw) == .success else { return nil }
        return raw as? T
    }

    /// 讀取 AXValue 包裝的幾何屬性（CGPoint/CGSize）到呼叫端提供的記憶體。
    /// - Returns: 屬性存在且型別相符時為 true
    private func copyAXValue(_ name: String, type: AXValueType, into pointer: UnsafeMutableRawPointer) -> Bool {
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(self, name as CFString, &raw) == .success,
              let raw, CFGetTypeID(raw) == AXValueGetTypeID() else { return false }
        // CFGetTypeID 已確認型別，強制轉型安全
        return AXValueGetValue(raw as! AXValue, type, pointer)
    }

    /// 一次 IPC 批次讀取多個屬性（比逐一讀取快數倍，因每次 AX 呼叫都要往返目標 App 的主執行緒）。
    /// - Parameter names: 屬性名稱
    /// - Returns: 屬性名 → 值；讀取失敗的屬性不會出現在結果中
    func values(_ names: [String]) -> [String: CFTypeRef] {
        var raw: CFArray?
        guard AXUIElementCopyMultipleAttributeValues(self, names as CFArray, AXCopyMultipleAttributeOptions(), &raw) == .success,
              let array = raw as? [CFTypeRef], array.count == names.count else { return [:] }
        var result: [String: CFTypeRef] = [:]
        for (name, value) in zip(names, array) {
            // 失敗的屬性會以 AXValue(.axError) 佔位
            if CFGetTypeID(value) == AXValueGetTypeID(), AXValueGetType(value as! AXValue) == .axError { continue }
            result[name] = value
        }
        return result
    }

    var role: String? { value(kAXRoleAttribute) }
    var subrole: String? { value(kAXSubroleAttribute) }
    var title: String? { value(kAXTitleAttribute) }
    var children: [AXUIElement] { value(kAXChildrenAttribute) ?? [] }
    var isMinimized: Bool { value(kAXMinimizedAttribute) ?? false }

    var position: CGPoint? {
        var point = CGPoint.zero
        return copyAXValue(kAXPositionAttribute, type: .cgPoint, into: &point) ? point : nil
    }

    var size: CGSize? {
        var size = CGSize.zero
        return copyAXValue(kAXSizeAttribute, type: .cgSize, into: &size) ? size : nil
    }

    /// AX 座標系（主螢幕左上角為原點、Y 向下）下的外框。
    var frame: CGRect? {
        guard let position, let size else { return nil }
        return CGRect(origin: position, size: size)
    }

    /// 對應的 CGWindowID；非視窗元素或查詢失敗時回傳 nil。
    var windowID: CGWindowID? {
        var id: CGWindowID = 0
        return _AXUIElementGetWindow(self, &id) == .success && id != 0 ? id : nil
    }

    /// 從批次讀取結果解出幾何值。
    static func point(_ value: CFTypeRef?) -> CGPoint? {
        guard let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero
        return AXValueGetValue(value as! AXValue, .cgPoint, &point) ? point : nil
    }

    static func size(_ value: CFTypeRef?) -> CGSize? {
        guard let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var size = CGSize.zero
        return AXValueGetValue(value as! AXValue, .cgSize, &size) ? size : nil
    }

    /// 寫入 AX 屬性。
    /// - Returns: 是否成功
    @discardableResult
    func set(_ name: String, _ value: CFTypeRef) -> Bool {
        AXUIElementSetAttributeValue(self, name as CFString, value) == .success
    }

    /// 執行 AX 動作（例如 `kAXRaiseAction`、`kAXPressAction`）。
    /// - Returns: 是否成功
    @discardableResult
    func perform(_ action: String) -> Bool {
        AXUIElementPerformAction(self, action as CFString) == .success
    }
}
