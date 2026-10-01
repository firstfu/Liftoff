//
//  FolderPanelView.swift
//  Liftoff
//
//  展開的資料夾：置中的 Liquid Glass 面板，上方是可點擊改名的標題，下方是資料夾內 App 的格線
//  （每頁 3 列，超過時可橫向翻頁）。可在面板內拖曳排序；拖出面板即移出資料夾。
//

import SwiftUI

/// 資料夾面板上的 SwiftUI 部分：標題（可改名）與頁碼點。
/// 玻璃底板與格子由 Core Animation（GridRenderer）繪製，這裡只疊上需要文字輸入與點擊的元件。
struct FolderPanelView: View {
    let model: LaunchpadModel
    let folder: FolderData

    var body: some View {
        let frame = model.folderPanelFrame(for: folder)
        let pages = (folder.apps.count + model.folderCapacity - 1) / model.folderCapacity
        ZStack(alignment: .topLeading) {
            // 吃掉面板內空白處的點擊（格子的點擊在面板層就被攔下，不會到這裡），避免穿透到背景而收起資料夾
            Color.clear
                .contentShape(.rect(cornerRadius: 30))
                .onTapGesture { model.isRenamingFolder = false }
            FolderTitle(model: model, folder: folder)
                .frame(width: frame.width, height: FolderPanelStyle.titleHeight + FolderPanelStyle.padding * 0.6)
            if pages > 1 {
                PageDots(pager: model.folderPager, count: pages, dark: false)
                    .position(x: frame.width / 2, y: frame.height - 14)
            }
        }
        .frame(width: frame.width, height: frame.height)
        .environment(\.colorScheme, .dark)
        .position(x: frame.midX, y: frame.midY)
    }
}

private struct FolderTitle: View {
    let model: LaunchpadModel
    let folder: FolderData
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        Group {
            if model.isRenamingFolder {
                TextField("資料夾名稱", text: $draft)
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(.center)
                    .focused($focused)
                    .onSubmit { commit() }
                    .onAppear {
                        draft = folder.name
                        focused = true
                    }
                    .onChange(of: focused) { _, isFocused in if !isFocused { commit() } }
            } else {
                Text(folder.name)
                    .onTapGesture {
                        draft = folder.name
                        model.isRenamingFolder = true
                    }
            }
        }
        .font(.system(size: 22, weight: .semibold))
        .foregroundStyle(Color.white)
        .frame(maxWidth: 360)
    }

    private func commit() {
        guard model.isRenamingFolder else { return }
        model.renameFolder(folder.id, to: draft)
        model.isRenamingFolder = false
        model.focusRequest += 1
    }
}
