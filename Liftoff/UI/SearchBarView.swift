//
//  SearchBarView.swift
//  Liftoff
//
//  啟動台上方的搜尋列：純 AppKit（NSTextField 放在 Liquid Glass 膠囊裡），不經過 SwiftUI。
//  為什麼不用 SwiftUI TextField：實測每打一個字，光是搜尋框這棵小小的 SwiftUI 樹排版就要 3.5–8ms，
//  加上 binding 傳遞，每鍵主執行緒 8–30ms；換成 AppKit 後每鍵只剩搜尋本身與格線圖層同步的成本。
//  與 model 的同步：使用者輸入 → controlTextDidChange 寫入 model.searchText；
//  程式改動（清除、收起後重設）→ RenderLoop 追蹤 model.searchText 回寫到輸入框。
//

import AppKit

final class SearchBarView: NSView, NSTextFieldDelegate {
    /// 整個搜尋列的大小（膠囊本身）
    static let size = CGSize(width: 240, height: 32)

    private let model: LaunchpadModel
    private let glass = NSGlassEffectView()
    private let icon = NSImageView()
    private let field = NSTextField()
    private let clearButton = NSButton()
    private var loops: [RenderLoop] = []
    private var lastFocusRequest = 0

    init(model: LaunchpadModel) {
        self.model = model
        super.init(frame: CGRect(origin: .zero, size: Self.size))
        wantsLayer = true

        glass.cornerRadius = Self.size.height / 2
        glass.frame = bounds
        glass.autoresizingMask = [.width, .height]
        addSubview(glass)

        let content = NSView(frame: bounds)
        glass.contentView = content

        icon.image = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 13, weight: .medium))
        icon.contentTintColor = .secondaryLabelColor
        icon.frame = CGRect(x: 12, y: (Self.size.height - 16) / 2, width: 16, height: 16)
        content.addSubview(icon)

        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 14)
        field.placeholderString = String(localized: "搜尋")
        field.usesSingleLineMode = true
        field.cell?.isScrollable = true
        field.cell?.wraps = false
        field.delegate = self
        let fieldHeight: CGFloat = 18
        field.frame = CGRect(x: 35, y: (Self.size.height - fieldHeight) / 2, width: Self.size.width - 35 - 30, height: fieldHeight)
        content.addSubview(field)

        clearButton.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: String(localized: "清除"))
        clearButton.isBordered = false
        clearButton.contentTintColor = .secondaryLabelColor
        clearButton.target = self
        clearButton.action = #selector(clear)
        clearButton.frame = CGRect(x: Self.size.width - 28, y: (Self.size.height - 18) / 2, width: 18, height: 18)
        clearButton.isHidden = true
        content.addSubview(clearButton)

        loops = [
            // 程式改動搜尋文字（清除、收起後重設）時回寫輸入框
            RenderLoop { [weak self] in self?.syncText() },
            // 開資料夾時淡出且不接收點擊；背景深淺切換深色/淺色外觀
            RenderLoop { [weak self] in self?.syncAppearance() },
            // 要求搜尋框取得焦點（打開啟動台、⌘F、改完資料夾名稱）
            RenderLoop { [weak self] in self?.syncFocus() },
        ]
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    // MARK: - 與 model 同步

    private func syncText() {
        let text = model.searchText
        if field.stringValue != text, !isComposing {
            field.stringValue = text
            // 編輯中直接改字串會被全選：游標移回最後，接著打字才不會把內容蓋掉
            if let editor = field.currentEditor() {
                editor.selectedRange = NSRange(location: (text as NSString).length, length: 0)
            }
        }
        clearButton.isHidden = text.isEmpty
    }

    private func syncAppearance() {
        let folderOpen = model.openFolderID != nil
        let dark = !model.labelsAreDark
        let name: NSAppearance.Name = dark ? .darkAqua : .aqua
        if appearance?.name != name { appearance = NSAppearance(named: name) }
        guard isHidden != folderOpen else { return }
        if folderOpen, let window, window.firstResponder === field.currentEditor() {
            // 資料夾開著時鍵盤交給資料夾（方向鍵選取等由面板層處理），輸入框先放掉焦點
            window.makeFirstResponder(nil)
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            animator().alphaValue = folderOpen ? 0 : 1
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.isHidden = self.model.openFolderID != nil
            }
        }
        if !folderOpen { isHidden = false }
    }

    private func syncFocus() {
        let request = model.focusRequest
        guard request != lastFocusRequest else { return }
        lastFocusRequest = request
        let start = ContinuousClock.now
        focus()
        Log.perf.debug("搜尋框取得焦點 \(milliseconds(since: start), format: .fixed(precision: 2))ms")
    }

    /// 讓輸入框取得鍵盤焦點（游標放到最後，不全選）。
    func focus() {
        guard let window, !isHidden else { return }
        window.makeFirstResponder(field)
        if let editor = field.currentEditor() {
            editor.selectedRange = NSRange(location: (field.stringValue as NSString).length, length: 0)
        }
    }

    /// 中文輸入法選字中（有未確認的組字）：組字中的注音/拼音不拿去搜尋，也不能被程式覆蓋。
    private var isComposing: Bool {
        (field.currentEditor() as? NSTextView)?.hasMarkedText() ?? false
    }

    // MARK: - 輸入

    func controlTextDidChange(_ notification: Notification) {
        guard !isComposing else { return }
        let text = field.stringValue
        if model.searchText != text { model.searchText = text }
        clearButton.isHidden = text.isEmpty
    }

    @objc private func clear() {
        field.stringValue = ""
        model.searchText = ""
        focus()
    }
}
