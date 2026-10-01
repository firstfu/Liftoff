//
//  HotKeyRecorder.swift
//  Liftoff
//
//  快速鍵錄製按鈕：點一下進入錄製，按下想要的組合鍵（至少一個修飾鍵，或 F 功能鍵）即完成；Esc 取消。
//  錄製期間暫停全域快速鍵，避免按到現有組合時直接觸發啟動台。
//

import AppKit
import Carbon.HIToolbox
import SwiftUI

struct HotKeyRecorder: View {
    @Binding var combo: HotKeyCombo?
    let hotKeys: HotKeyService
    @State private var isRecording = false
    @State private var monitor: Any?

    /// F1–F20 的 Carbon keyCode 集合（不需修飾鍵即可作為快速鍵）
    private static let functionKeyCodes: Set<Int> = [
        kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10,
        kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20,
    ].reduce(into: Set<Int>()) { $0.insert(Int($1)) }

    var body: some View {
        HStack(spacing: 6) {
            Button {
                isRecording ? stop() : start()
            } label: {
                Text(isRecording ? String(localized: "請按下組合鍵…") : (combo?.displayString ?? String(localized: "未設定")))
                    .frame(minWidth: 110)
            }
            if combo != nil, !isRecording {
                Button {
                    combo = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.borderless)
                .help("清除快速鍵")
            }
        }
        .onDisappear(perform: stop)
    }

    private func start() {
        isRecording = true
        hotKeys.unregister()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
            if event.keyCode == UInt16(kVK_Escape), flags.isEmpty {
                stop()
                return nil
            }
            // Carbon 的 F 鍵 keyCode 不連續且 kVK_F1 (0x7A) > kVK_F20 (0x5A)，不能用 ClosedRange（會 trap），
            // 因此逐一列舉
            let isFunctionKey = Self.functionKeyCodes.contains(Int(event.keyCode))
            guard !flags.isEmpty || isFunctionKey else {
                NSSound.beep()
                return nil
            }
            combo = HotKeyCombo(keyCode: event.keyCode, modifiers: flags.rawValue)
            stop()
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if isRecording {
            isRecording = false
            // 錄製結束（無論是否變更）都重新註冊目前的快速鍵
            hotKeys.register(combo)
        }
    }
}
