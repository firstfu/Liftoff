//
//  WindowPreviewModel.swift
//  Liftoff
//
//  執行中 App 的「視窗縮圖預覽」：游標停在執行中 App 的圖示上（或按空白鍵）時，在圖示旁顯示該 App 所有視窗的即時縮圖，
//  點縮圖直接切換到那個視窗。
//
//  延遲設計：游標停留 150ms 就先在背景列舉視窗、開始擷取（WindowServer 私有 API ~20ms/窗），
//  等到設定的延遲（預設 500ms）到了才顯示——多數情況顯示當下縮圖已經拍好，不會先看到空白卡片。
//  預覽已顯示時移到另一個執行中 App，立即切換、不再等待（與 Dock 預覽工具的手感一致）。
//

import AppKit
import Observation
import SwiftUI

@Observable
final class WindowPreviewModel {
    struct Card: Identifiable {
        let window: WindowInfo
        var image: CGImage?
        var id: CGWindowID { window.id }
    }

    enum Status: Equatable {
        case loading
        case ready
        case noWindows
        case needsPermission
    }

    private(set) var appID: String?
    private(set) var appName = ""
    /// 圖示外框（啟動台根座標），預覽框依此定位
    private(set) var anchor: CGRect = .zero
    private(set) var cards: [Card] = []
    private(set) var status: Status = .loading
    private(set) var isVisible = false

    /// 卡片寬度（points）
    static let cardWidth: CGFloat = 208
    static let maxCards = 6

    @ObservationIgnored private let thumbnails = ThumbnailService()
    /// 本次啟動是否已提示過缺少螢幕錄製權限
    private static var permissionHintShown = false
    @ObservationIgnored private var hoverTask: Task<Void, Never>?
    @ObservationIgnored private var hideTask: Task<Void, Never>?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var pointerInPopover = false
    @ObservationIgnored private var pendingPID: pid_t = 0
    /// 點縮圖後請啟動台收起並切換視窗
    @ObservationIgnored var onActivateWindow: ((WindowInfo) -> Void)?
    /// 顯示用的螢幕倍率（決定縮圖像素）
    @ObservationIgnored var backingScale: CGFloat = 2

    // MARK: - 游標進出

    /// 游標進入執行中 App 的圖示。
    /// - Parameters:
    ///   - appID: App 識別鍵
    ///   - app: 執行中的 App
    ///   - name: 顯示名稱
    ///   - anchor: 圖示外框（根座標）
    ///   - delay: 顯示延遲（秒）
    func hoverBegan(appID: String, app: NSRunningApplication, name: String, anchor: CGRect, delay: Double) {
        hideTask?.cancel()
        hoverTask?.cancel()
        if isVisible {
            // 已在顯示中：直接換成新的 App
            if self.appID != appID { load(appID: appID, pid: app.processIdentifier, name: name, anchor: anchor) }
            return
        }
        hoverTask = Task { [weak self] in
            let prefetch = min(delay, 0.15)
            try? await Task.sleep(for: .seconds(prefetch))
            guard let self, !Task.isCancelled else { return }
            self.load(appID: appID, pid: app.processIdentifier, name: name, anchor: anchor)
            try? await Task.sleep(for: .seconds(max(0, delay - prefetch)))
            guard !Task.isCancelled, self.appID == appID else { return }
            withAnimation(.smooth(duration: 0.18)) { self.isVisible = true }
        }
    }

    /// 游標離開圖示：稍等一下，讓游標有時間移進預覽框。
    func hoverEnded(appID: String) {
        hoverTask?.cancel()
        guard self.appID == appID || !isVisible else { return }
        scheduleHide()
    }

    /// 游標進出預覽框本身。
    func popoverHover(_ inside: Bool) {
        pointerInPopover = inside
        if inside { hideTask?.cancel() } else { scheduleHide() }
    }

    /// 立即顯示（鍵盤空白鍵）。
    func showNow(appID: String, app: NSRunningApplication, name: String, anchor: CGRect) {
        hoverTask?.cancel()
        hideTask?.cancel()
        if self.appID != appID || !isVisible {
            load(appID: appID, pid: app.processIdentifier, name: name, anchor: anchor)
        }
        withAnimation(.smooth(duration: 0.18)) { isVisible = true }
    }

    /// 立即隱藏並作廢進行中的擷取。
    func hide() {
        hoverTask?.cancel()
        hideTask?.cancel()
        thumbnails.cancelInteractive()
        generation += 1
        pointerInPopover = false
        guard isVisible || appID != nil else { return }
        withAnimation(.smooth(duration: 0.15)) { isVisible = false }
        appID = nil
    }

    func activate(_ card: Card) {
        let window = card.window
        hide()
        onActivateWindow?(window)
    }

    /// 清空全部縮圖快取（啟動台收起一段時間後由協調者呼叫）。
    func purgeAll() {
        thumbnails.purgeAll()
    }

    /// App 結束時清掉它的縮圖快取。
    func purge(pid: pid_t) {
        thumbnails.purge(pid: pid)
    }

    private func scheduleHide() {
        hideTask?.cancel()
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(220))
            guard let self, !Task.isCancelled, !self.pointerInPopover else { return }
            self.hide()
        }
    }

    // MARK: - 載入

    /// 列舉視窗（背景）→ 先放快取縮圖 → 逐張擷取最新縮圖（串流更新）。
    private func load(appID: String, pid: pid_t, name: String, anchor: CGRect) {
        generation += 1
        let token = generation
        self.appID = appID
        appName = name
        self.anchor = anchor
        pendingPID = pid
        status = .loading
        cards = []

        let hasScreenRecording = CGPreflightScreenCaptureAccess()
        let pixelWidth = Int(Self.cardWidth * backingScale)
        Task { [weak self] in
            let windows = await Task.detached(priority: .userInitiated) {
                WindowEnumerator.windows(for: pid, includeOtherSpaces: true)
            }.value
            guard let self, self.generation == token else { return }
            let visible = Array(windows.prefix(Self.maxCards))
            self.cards = visible.map { Card(window: $0, image: self.thumbnails.cached($0.id)?.image) }
            guard !visible.isEmpty else {
                // 沒有視窗（例如選單列 App）：不顯示空的預覽框，以免游標掃過時一直跳出來
                self.status = .noWindows
                self.hide()
                return
            }
            guard hasScreenRecording else {
                // 缺權限的提示每次啟動只出現一次；之後靜默不顯示，直到使用者到設定授權
                if Self.permissionHintShown {
                    self.hide()
                } else {
                    Self.permissionHintShown = true
                    self.status = .needsPermission
                }
                return
            }
            self.status = .ready
            self.thumbnails.capture(visible, maxPixelWidth: pixelWidth) { [weak self] windowID, thumbnail in
                guard let self, self.generation == token,
                      let index = self.cards.firstIndex(where: { $0.id == windowID }) else { return }
                self.cards[index].image = thumbnail.image
            }
        }
    }
}
