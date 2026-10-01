//
//  HotKeyService.swift
//  Liftoff
//
//  全域快速鍵：使用 Carbon `RegisterEventHotKey`。
//  為什麼不用 NSEvent 全域監聽：全域鍵盤監聽需要「輔助使用」權限，而且只能旁觀、無法攔下按鍵；
//  Carbon 熱鍵不需任何權限、由系統直接派送，零輪詢。
//

import AppKit
import Carbon.HIToolbox

final class HotKeyService {
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    /// 快速鍵按下時呼叫（主執行緒）
    var onPress: (() -> Void)?

    /// 註冊（或以 nil 取消）快速鍵。
    /// - Parameter combo: 快速鍵組合
    /// - Returns: 是否註冊成功（可能被其他 App 占用）
    @discardableResult
    func register(_ combo: HotKeyCombo?) -> Bool {
        unregister()
        guard let combo else { return true }
        installHandlerIfNeeded()

        let hotKeyID = EventHotKeyID(signature: OSType(0x4C46_5446), id: 1) // 'LFTF'
        let status = RegisterEventHotKey(
            UInt32(combo.keyCode), Self.carbonModifiers(combo.modifierFlags), hotKeyID,
            GetEventDispatcherTarget(), 0, &hotKeyRef
        )
        if status != noErr {
            Log.input.error("快速鍵註冊失敗（\(status)）：\(combo.displayString, privacy: .public)")
            hotKeyRef = nil
            return false
        }
        Log.input.info("快速鍵已註冊：\(combo.displayString, privacy: .public)")
        return true
    }

    func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        hotKeyRef = nil
    }

    private func installHandlerIfNeeded() {
        guard handlerRef == nil else { return }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let handler: EventHandlerUPP = { _, _, userData in
            guard let userData else { return OSStatus(eventNotHandledErr) }
            // Carbon 事件在主執行緒派送
            MainActor.assumeIsolated {
                Unmanaged<HotKeyService>.fromOpaque(userData).takeUnretainedValue().onPress?()
            }
            return noErr
        }
        InstallEventHandler(GetEventDispatcherTarget(), handler, 1, &eventType, Unmanaged.passUnretained(self).toOpaque(), &handlerRef)
    }

    /// NSEvent 修飾鍵 → Carbon 修飾鍵位元。
    static func carbonModifiers(_ flags: NSEvent.ModifierFlags) -> UInt32 {
        var result: UInt32 = 0
        if flags.contains(.command) { result |= UInt32(cmdKey) }
        if flags.contains(.option) { result |= UInt32(optionKey) }
        if flags.contains(.control) { result |= UInt32(controlKey) }
        if flags.contains(.shift) { result |= UInt32(shiftKey) }
        return result
    }
}

extension HotKeyCombo {
    /// 顯示用字串，例如「⌃⌘L」。
    nonisolated var displayString: String {
        var text = ""
        let flags = modifierFlags
        if flags.contains(.control) { text += "⌃" }
        if flags.contains(.option) { text += "⌥" }
        if flags.contains(.shift) { text += "⇧" }
        if flags.contains(.command) { text += "⌘" }
        return text + Self.keyName(keyCode)
    }

    /// 虛擬鍵碼 → 鍵名（特殊鍵用符號，一般鍵依目前鍵盤配置轉成字元）。
    nonisolated static func keyName(_ keyCode: UInt16) -> String {
        let special: [Int: String] = [
            kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Delete: "⌫", kVK_Escape: "⎋",
            kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
            kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
            kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
            kVK_F13: "F13", kVK_F14: "F14", kVK_F15: "F15", kVK_F16: "F16", kVK_F17: "F17", kVK_F18: "F18",
            kVK_F19: "F19", kVK_F20: "F20", kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟",
            kVK_ANSI_Grave: "`",
        ]
        if let name = special[Int(keyCode)] { return name }
        return characterForKeyCode(keyCode)?.uppercased() ?? "#\(keyCode)"
    }

    /// 依目前的 ASCII 鍵盤配置把鍵碼轉成字元（中文輸入法下也能得到英文字母）。
    nonisolated private static func characterForKeyCode(_ keyCode: UInt16) -> String? {
        guard let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
              let raw = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(raw).takeUnretainedValue() as Data
        return data.withUnsafeBytes { buffer -> String? in
            guard let layout = buffer.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return nil }
            var deadKeys: UInt32 = 0
            var length = 0
            var chars = [UniChar](repeating: 0, count: 4)
            let status = UCKeyTranslate(layout, keyCode, UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
                                        OptionBits(kUCKeyTranslateNoDeadKeysBit), &deadKeys, chars.count, &length, &chars)
            guard status == noErr, length > 0 else { return nil }
            return String(utf16CodeUnits: chars, count: length)
        }
    }
}
