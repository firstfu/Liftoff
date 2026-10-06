//
//  LaunchpadRootView.swift
//  Liftoff
//
//  啟動台的 SwiftUI 根畫面（背景由 AppKit 圖層負責，這裡只畫內容）：
//  分頁格線、頁碼點、資料夾面板、拖曳中的浮動圖示、視窗縮圖預覽、確認框與提示訊息。
//

import SwiftUI

struct LaunchpadRootView: View {
    /// 根座標空間名稱：所有位置計算都以此為準（等同整個螢幕）
    static let space = "launchpad"

    let model: LaunchpadModel

    // 觀察粒度：根畫面只依賴版面尺寸；搜尋文字、頁數、資料夾等各由獨立的小 view 讀取，
    // 打字時只有搜尋框與頁碼點會重算，不會牽動整個畫面。
    var body: some View {
        GeometryReader { proxy in
            let metrics = model.metrics
            ZStack(alignment: .topLeading) {
                // 點空白處：關資料夾或收起啟動台
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { model.backgroundClicked() }

                ChromeLayer(model: model, metrics: metrics)

                FolderLayer(model: model)
                    .zIndex(2)

                WindowPreviewLayer(model: model, containerSize: metrics.containerSize)
                    .zIndex(3)

                OverlayLayer(model: model)
                    .zIndex(5)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .coordinateSpace(.named(Self.space))
            .onAppear { model.containerSize = proxy.size }
            .onChange(of: proxy.size) { _, size in model.containerSize = size }
        }
        .ignoresSafeArea()
    }
}

/// 頁碼點、「沒有結果」提示（搜尋列是 AppKit，見 SearchBarView）。
private struct ChromeLayer: View {
    let model: LaunchpadModel
    let metrics: GridMetrics

    var body: some View {
        let folderOpen = model.openFolderID != nil
        MainPageDots(model: model)
            .position(x: metrics.containerSize.width / 2, y: metrics.pageDotsY)
            .opacity(folderOpen ? 0 : 1)
        NoResultsHint(model: model)
            .position(x: metrics.containerSize.width / 2, y: metrics.containerSize.height / 2)
    }
}

private struct MainPageDots: View {
    let model: LaunchpadModel

    var body: some View {
        PageDots(pager: model.pager, count: model.displayPages.count, dark: model.labelsAreDark)
    }
}

private struct NoResultsHint: View {
    let model: LaunchpadModel

    var body: some View {
        if model.isSearching, model.searchResults.isEmpty {
            Text("沒有符合的 App")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(model.labelsAreDark ? Color.black.opacity(0.6) : Color.white.opacity(0.85))
        }
    }
}

private struct FolderLayer: View {
    let model: LaunchpadModel
    /// 最近一次開過的資料夾：面板常駐不卸載，開資料夾時只換文字與透明度，
    /// 不必每次重建 SwiftUI 子樹（實測插入/移除整個面板要 12ms 以上）
    @State private var shown: FolderData?

    var body: some View {
        let folder = model.openFolder
        let isOpen = folder != nil
        ZStack {
            if let current = folder ?? shown {
                FolderPanelView(model: model, folder: current)
            }
        }
        // 面板子樹常駐，換資料夾時 position／frame 會跟著變；若被下方的淡入動畫波及，
        // 標題就會從上一個資料夾的位置滑到定位。這裡切斷內部的隱式動畫，只讓 opacity 有動畫
        .transaction { $0.animation = nil }
        .opacity(isOpen ? 1 : 0)
        .allowsHitTesting(isOpen)
        // 面板由圖層從資料夾圖示放大，標題晚一點淡入，免得面板還很小時標題已經出現在定位
        .animation(isOpen ? .easeOut(duration: 0.2).delay(0.14) : .easeIn(duration: 0.12), value: isOpen)
        .onChange(of: folder) { _, newValue in if let newValue { shown = newValue } }
        .onAppear {
            // 預先掛上任一資料夾，第一次打開資料夾時也不必建立子樹
            shown = shown ?? model.layoutStore.layout.pages.lazy.flatMap { $0 }.compactMap(\.folder).first
        }
    }
}

// MARK: - 頁碼

/// 頁碼點：目前頁實心，點擊跳頁。
struct PageDots: View {
    let pager: PagerState
    let count: Int
    let dark: Bool

    var body: some View {
        if count > 1 {
            HStack(spacing: 10) {
                ForEach(0..<count, id: \.self) { index in
                    Circle()
                        .fill(color.opacity(index == pager.page ? 0.95 : 0.35))
                        .frame(width: 8, height: 8)
                        .contentShape(Rectangle().inset(by: -5))
                        .onTapGesture { pager.go(to: index, pageCount: count) }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .animation(.smooth(duration: 0.2), value: pager.page)
        }
    }

    private var color: Color { dark ? .black : .white }
}


// MARK: - 確認框與提示

private struct OverlayLayer: View {
    let model: LaunchpadModel

    var body: some View {
        ZStack {
            if let confirmation = model.confirmation {
                Color.black.opacity(0.3)
                    .contentShape(Rectangle())
                    .onTapGesture { model.confirmation = nil }
                    .transition(.opacity)
                ConfirmCard(model: model, confirmation: confirmation)
                    .transition(.scale(scale: 0.9).combined(with: .opacity))
            }
            if let toast = model.toast {
                VStack {
                    Spacer()
                    Text(toast)
                        .font(.system(size: 13, weight: .medium))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 9)
                        .glassEffect(.regular, in: .capsule)
                        .environment(\.colorScheme, .dark)
                        .padding(.bottom, 120)
                }
                .allowsHitTesting(false)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }
}

private struct ConfirmCard: View {
    let model: LaunchpadModel
    let confirmation: Confirmation

    var body: some View {
        switch confirmation {
        case .uninstall(let appID):
            if let plan = model.uninstallPlan {
                UninstallCard(model: model, plan: plan, appID: appID)
            }
        }
    }
}

/// 「徹底移除」：App 本體 ＋ 殘留檔清單（可勾選），底下顯示將釋放的空間。
private struct UninstallCard: View {
    let model: LaunchpadModel
    let plan: UninstallPlan
    let appID: String

    var body: some View {
        let entry = model.catalog.entry(appID)
        VStack(spacing: 12) {
            AppIconImage(icon: model.icons.icon(for: appID), placeholder: model.icons.placeholder)
                .frame(width: 64, height: 64)
            Text("要徹底移除「\(entry?.name ?? appID)」嗎？")
                .font(.system(size: 15, weight: .semibold))
            if plan.isScanning {
                ProgressView().controlSize(.small).frame(height: 60)
            } else if plan.leftovers.isEmpty {
                Text("沒有找到殘留檔，只會移除 App 本身。")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(plan.leftovers) { file in
                            LeftoverRow(file: file, isOn: Binding(
                                get: { plan.selected.contains(file.url) },
                                set: { if $0 { plan.selected.insert(file.url) } else { plan.selected.remove(file.url) } }))
                        }
                    }
                }
                .frame(height: min(220, CGFloat(plan.leftovers.count) * 40 + 4))
                .background(.black.opacity(0.18), in: .rect(cornerRadius: 10))
                Text("全部會移到垃圾桶，可以復原。只靠名稱比對到的項目預設不勾選。")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            HStack(spacing: 10) {
                Button("取消") { model.confirmation = nil; model.uninstallPlan = nil }
                    .keyboardShortcut(.cancelAction)
                Button(plan.isScanning ? "移除" : "移除 \(ByteCountFormatter.string(fromByteCount: plan.totalSelectedSize, countStyle: .file))",
                       role: .destructive) { model.confirmUninstall() }
                    .buttonStyle(.glassProminent)
                    .tint(.red)
                    .disabled(plan.isScanning || plan.isRemoving)
            }
            .controlSize(.large)
        }
        .padding(24)
        .frame(width: 460)
        .glassEffect(.regular, in: .rect(cornerRadius: 26))
        .environment(\.colorScheme, .dark)
    }
}

private struct LeftoverRow: View {
    let file: LeftoverFile
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(file.url.lastPathComponent).font(.system(size: 12)).lineLimit(1).truncationMode(.middle)
                    Text(file.kind).font(.system(size: 10)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Text(ByteCountFormatter.string(fromByteCount: file.size, countStyle: .file))
                    .font(.system(size: 11)).foregroundStyle(.secondary).monospacedDigit()
            }
        }
        .toggleStyle(.checkbox)
        .padding(.horizontal, 10).padding(.vertical, 5)
    }
}
