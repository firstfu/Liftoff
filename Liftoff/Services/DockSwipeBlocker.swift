//
//  DockSwipeBlocker.swift
//  Liftoff
//
//  啟動台顯示期間，擋掉「四指左右滑動切換桌面／全螢幕 App」（issue #16）。
//  不擋的話系統會把啟動台連同桌面一起推走，畫面變成半邊啟動台、半邊別的 App。
//  做法：在 HID 層放一個事件攔截點（CGEventTap，只收 Dock 手勢事件），把水平滑動整段吃掉；
//  垂直滑動（指揮中心）與捏合照常放行。需要「輔助使用」權限，沒有就不啟用（行為與以前相同）。
//  事件類型與欄位編號沒有公開文件（見 `PrivateAPI.swift` 的 `DockControlEvent`），讀不到預期值時一律放行。
//

import AppKit
import ApplicationServices

final class DockSwipeBlocker {
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    /// 啟動台顯示中：新開始的水平滑動要擋
    private var isActive = false
    /// 正在吃掉一段手勢：必須吃到結束，否則 Dock 只收到半段
    private var isSwallowing = false

    /// 建立攔截點（先不啟用）。沒有輔助使用權限時不建立，之後取得權限再呼叫一次即可。
    func prepare() {
        guard tap == nil else { return }
        guard AXIsProcessTrusted() else {
            Log.input.debug("沒有輔助使用權限，不攔截四指滑動")
            return
        }
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: CGEventMask(1) << DockControlEvent.type, callback: dockSwipeTapCallback, userInfo: context
        ) else {
            Log.input.error("無法建立 Dock 手勢攔截點")
            return
        }
        // 建立後預設是啟用的：先關掉，顯示啟動台時才開
        CGEvent.tapEnable(tap: tap, enable: false)
        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        self.tap = tap
        self.source = source
        Log.input.info("Dock 手勢攔截點已建立")
        if isActive { CGEvent.tapEnable(tap: tap, enable: true) }
    }

    /// 移除攔截點（關閉設定時）。
    func teardown() {
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let tap { CFMachPortInvalidate(tap) }
        tap = nil
        source = nil
        isSwallowing = false
    }

    /// 啟動台顯示／收起時切換。收起時若正吃到一半，等那段手勢結束才真的停。
    func setActive(_ active: Bool) {
        guard active != isActive else { return }
        isActive = active
        guard let tap else { return }
        if active {
            CGEvent.tapEnable(tap: tap, enable: true)
        } else if !isSwallowing {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
    }

    /// 攔截點被系統停用（回呼逾時等）：還需要就重新啟用。
    fileprivate func tapWasDisabled() {
        isSwallowing = false
        if isActive, let tap { CGEvent.tapEnable(tap: tap, enable: true) }
    }

    /// - Returns: true = 吃掉這個事件
    fileprivate func shouldDrop(motion: Int64, phase: Int64) -> Bool {
        if phase == DockControlEvent.phaseBegan {
            isSwallowing = isActive && motion == DockControlEvent.motionHorizontal
            if isSwallowing { Log.input.debug("擋下四指左右滑動") }
            return isSwallowing
        }
        guard isSwallowing else { return false }
        if phase == DockControlEvent.phaseEnded || phase == DockControlEvent.phaseCancelled {
            isSwallowing = false
            if !isActive, let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        }
        return true
    }
}

/// 事件攔截回呼。攔截點掛在主執行緒的 run loop 上，所以一定在主執行緒被呼叫。
private nonisolated let dockSwipeTapCallback: CGEventTapCallBack = { _, type, event, context in
    guard let context else { return Unmanaged.passUnretained(event) }
    // 指標只是用來在主執行緒找回 blocker，本身不跨執行緒
    let address = UInt(bitPattern: context)
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        MainActor.assumeIsolated {
            Unmanaged<DockSwipeBlocker>.fromOpaque(UnsafeRawPointer(bitPattern: address)!).takeUnretainedValue().tapWasDisabled()
        }
        return Unmanaged.passUnretained(event)
    }
    guard type.rawValue == DockControlEvent.type,
          event.getIntegerValueField(DockControlEvent.hidTypeField) == DockControlEvent.hidTypeDockSwipe
    else { return Unmanaged.passUnretained(event) }
    let motion = event.getIntegerValueField(DockControlEvent.motionField)
    let phase = event.getIntegerValueField(DockControlEvent.phaseField)
    let drop = MainActor.assumeIsolated {
        Unmanaged<DockSwipeBlocker>.fromOpaque(UnsafeRawPointer(bitPattern: address)!).takeUnretainedValue().shouldDrop(motion: motion, phase: phase)
    }
    return drop ? nil : Unmanaged.passUnretained(event)
}
