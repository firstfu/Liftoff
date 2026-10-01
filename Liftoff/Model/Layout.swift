//
//  Layout.swift
//  Liftoff
//
//  啟動台的版面資料：多個「頁」，每頁依序排列 App 或資料夾。
//  全部是值型別與純函式，方便單元測試；UI 端的拖曳、建立資料夾、刪除 App 都透過這裡的操作完成。
//
//  規則（與經典啟動台一致）：
//  - 每頁最多 `capacity`（列 × 行）個項目；插入造成超量時，最後一項往下一頁「擠」過去（連鎖到底）
//  - 資料夾內不能再放資料夾；資料夾只剩一個 App 時自動解散，剩下的 App 回到資料夾原本的位置
//  - 空白頁在拖曳結束（normalize）時才移除，拖曳過程中保留，避免頁碼突然改變
//

import Foundation

/// 資料夾內容。
nonisolated struct FolderData: Codable, Hashable, Sendable, Identifiable {
    var id: UUID
    var name: String
    var apps: [String]

    init(id: UUID = UUID(), name: String, apps: [String]) {
        self.id = id
        self.name = name
        self.apps = apps
    }
}

/// 頁面上的一格：App 或資料夾。
nonisolated enum LayoutItem: Codable, Hashable, Sendable, Identifiable {
    case app(String)
    case folder(FolderData)

    /// SwiftUI 識別用；App 直接用 App 識別鍵（bundle ID 或路徑，不會以 "folder:" 開頭）
    var id: String {
        switch self {
        case .app(let id): id
        case .folder(let folder): Self.folderKey(folder.id)
        }
    }

    var appID: String? {
        if case .app(let id) = self { id } else { nil }
    }

    var folder: FolderData? {
        if case .folder(let folder) = self { folder } else { nil }
    }

    static func folderKey(_ id: UUID) -> String { "folder:" + id.uuidString }
}

/// 項目在頁面中的位置。
nonisolated struct ItemPosition: Hashable, Sendable {
    var page: Int
    var index: Int
}

nonisolated struct Layout: Codable, Hashable, Sendable {
    var pages: [[LayoutItem]]

    static let empty = Layout(pages: [])

    // MARK: - 查詢

    /// 所有 App 識別鍵（含資料夾內），依畫面順序。
    var allAppIDs: [String] {
        var result: [String] = []
        for page in pages {
            for item in page {
                switch item {
                case .app(let id): result.append(id)
                case .folder(let folder): result.append(contentsOf: folder.apps)
                }
            }
        }
        return result
    }

    /// 頂層項目（App 或資料夾）的位置。
    func position(of itemID: String) -> ItemPosition? {
        for (pageIndex, page) in pages.enumerated() {
            if let index = page.firstIndex(where: { $0.id == itemID }) {
                return ItemPosition(page: pageIndex, index: index)
            }
        }
        return nil
    }

    func item(at position: ItemPosition) -> LayoutItem? {
        guard pages.indices.contains(position.page), pages[position.page].indices.contains(position.index) else { return nil }
        return pages[position.page][position.index]
    }

    func folder(id: UUID) -> FolderData? {
        guard let position = position(of: LayoutItem.folderKey(id)) else { return nil }
        return item(at: position)?.folder
    }

    /// 找出包含指定 App 的資料夾。
    /// - Returns: 資料夾 ID 與 App 在資料夾內的索引；App 不在任何資料夾時為 nil
    func folderContaining(appID: String) -> (folderID: UUID, index: Int)? {
        for page in pages {
            for case .folder(let folder) in page {
                if let index = folder.apps.firstIndex(of: appID) { return (folder.id, index) }
            }
        }
        return nil
    }

    // MARK: - 基本編輯

    /// 移除頂層項目（不移除空白頁）。
    /// - Returns: 被移除的項目；找不到時為 nil
    @discardableResult
    mutating func removeItem(id itemID: String) -> LayoutItem? {
        guard let position = position(of: itemID) else { return nil }
        return pages[position.page].remove(at: position.index)
    }

    /// 在指定位置插入項目，超出容量的項目依序擠到下一頁。
    /// - Parameters:
    ///   - item: 要插入的項目
    ///   - position: 目標頁與索引（索引超出範圍時放在該頁最後；頁碼等於頁數時新增一頁）
    ///   - capacity: 每頁容量
    mutating func insert(_ item: LayoutItem, at position: ItemPosition, capacity: Int) {
        let page = max(0, min(position.page, pages.count))
        if page == pages.count { pages.append([]) }
        let index = max(0, min(position.index, pages[page].count))
        pages[page].insert(item, at: index)
        cascade(from: page, capacity: capacity)
    }

    /// 把頂層項目移到指定位置：結果中該項目會位在 `position`（索引以移除自己之後的頁面計算）。
    /// 拖曳時每跨一格呼叫一次，被拖曳的項目本身就是畫面上的「空位」。
    mutating func move(itemID: String, to position: ItemPosition, capacity: Int) {
        guard let item = removeItem(id: itemID) else { return }
        insert(item, at: position, capacity: capacity)
    }

    /// 超量的頁把最後的項目擠到下一頁，一路連鎖到最後一頁（必要時新增頁）。
    mutating func cascade(from startPage: Int = 0, capacity: Int) {
        guard capacity > 0 else { return }
        var page = max(0, startPage)
        while page < pages.count {
            if pages[page].count > capacity {
                let overflow = Array(pages[page][capacity...])
                pages[page].removeSubrange(capacity...)
                if page + 1 < pages.count {
                    pages[page + 1].insert(contentsOf: overflow, at: 0)
                } else {
                    pages.append(overflow)
                }
            }
            page += 1
        }
    }

    /// 整理：處理超量並移除空白頁（拖曳結束、設定變更後呼叫）。
    mutating func normalize(capacity: Int) {
        cascade(capacity: capacity)
        pages.removeAll { $0.isEmpty }
    }

    /// 緊湊排列：把所有項目依序重新填滿每一頁，消除各頁的空位。
    mutating func compact(capacity: Int) {
        guard capacity > 0 else { return }
        let items = pages.flatMap { $0 }
        pages = stride(from: 0, to: items.count, by: capacity).map { Array(items[$0..<min($0 + capacity, items.count)]) }
    }

    // MARK: - 資料夾

    /// 從資料夾移出 App。資料夾只剩一個 App 時自動解散（剩下的 App 取代資料夾位置），沒有 App 時移除。
    /// - Returns: 是否真的移除了
    @discardableResult
    mutating func removeApp(_ appID: String, fromFolder folderID: UUID) -> Bool {
        guard let position = position(of: LayoutItem.folderKey(folderID)),
              var folder = item(at: position)?.folder,
              let index = folder.apps.firstIndex(of: appID) else { return false }
        folder.apps.remove(at: index)
        switch folder.apps.count {
        case 0: pages[position.page].remove(at: position.index)
        case 1: pages[position.page][position.index] = .app(folder.apps[0])
        default: pages[position.page][position.index] = .folder(folder)
        }
        return true
    }

    /// 把 App 從目前位置（頁面或資料夾）取出，不做其他處理。
    /// - Returns: 是否找到並取出
    @discardableResult
    mutating func detachApp(_ appID: String) -> Bool {
        if removeItem(id: appID) != nil { return true }
        if let (folderID, _) = folderContaining(appID: appID) {
            return removeApp(appID, fromFolder: folderID)
        }
        return false
    }

    /// 把 App 拖到另一個項目上：目標是 App 則兩者合成新資料夾，目標是資料夾則加入其中。
    /// - Parameters:
    ///   - appID: 被拖曳的 App
    ///   - targetID: 放上去的目標項目（頂層 App 或資料夾）
    ///   - folderName: 建立新資料夾時使用的名稱
    /// - Returns: 結果資料夾的 ID；目標無效（例如拖到自己身上）時為 nil 且版面不變
    @discardableResult
    mutating func merge(appID: String, into targetID: String, folderName: String) -> UUID? {
        guard appID != targetID, let targetItem = position(of: targetID).flatMap({ item(at: $0) }) else { return nil }
        if case .folder(let existing) = targetItem, existing.apps.contains(appID) { return nil }

        detachApp(appID)
        // 取出被拖曳的 App 可能讓目標位移（同頁且在目標之前），也可能讓資料夾解散，因此重新定位
        guard let position = position(of: targetID) else { return nil }
        switch pages[position.page][position.index] {
        case .app(let targetApp):
            let folder = FolderData(name: folderName, apps: [targetApp, appID])
            pages[position.page][position.index] = .folder(folder)
            return folder.id
        case .folder(var folder):
            folder.apps.append(appID)
            pages[position.page][position.index] = .folder(folder)
            return folder.id
        }
    }

    /// 資料夾內重新排序。
    mutating func moveInFolder(_ folderID: UUID, appID: String, to index: Int) {
        guard let position = position(of: LayoutItem.folderKey(folderID)),
              var folder = item(at: position)?.folder,
              let from = folder.apps.firstIndex(of: appID) else { return }
        folder.apps.remove(at: from)
        folder.apps.insert(appID, at: max(0, min(index, folder.apps.count)))
        pages[position.page][position.index] = .folder(folder)
    }

    mutating func renameFolder(_ folderID: UUID, to name: String) {
        guard let position = position(of: LayoutItem.folderKey(folderID)),
              var folder = item(at: position)?.folder else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        folder.name = trimmed.isEmpty ? folder.name : trimmed
        pages[position.page][position.index] = .folder(folder)
    }

    /// 解散資料夾：內含的 App 依序放回資料夾原本的位置。
    mutating func dissolveFolder(_ folderID: UUID, capacity: Int) {
        guard let position = position(of: LayoutItem.folderKey(folderID)),
              let folder = item(at: position)?.folder else { return }
        pages[position.page].replaceSubrange(position.index...position.index, with: folder.apps.map { LayoutItem.app($0) })
        cascade(from: position.page, capacity: capacity)
    }

    // MARK: - 與已安裝 App 同步

    /// 讓版面與實際安裝的 App 一致：移除已刪除或隱藏的 App、去除重複、補上新安裝的 App（加在最後）。
    /// - Parameters:
    ///   - installed: 已安裝 App 的識別鍵（新 App 依此順序補上）
    ///   - hidden: 使用者隱藏的 App
    ///   - capacity: 每頁容量
    /// - Returns: 版面是否有變動
    @discardableResult
    mutating func reconcile(installed: [String], hidden: Set<String>, capacity: Int) -> Bool {
        let original = self
        let valid = Set(installed).subtracting(hidden)
        var seen = Set<String>()

        pages = pages.map { page in
            page.compactMap { item -> LayoutItem? in
                switch item {
                case .app(let id):
                    guard valid.contains(id), seen.insert(id).inserted else { return nil }
                    return item
                case .folder(var folder):
                    folder.apps = folder.apps.filter { valid.contains($0) && seen.insert($0).inserted }
                    switch folder.apps.count {
                    case 0: return nil
                    case 1: return .app(folder.apps[0])
                    default: return .folder(folder)
                    }
                }
            }
        }

        let missing = installed.filter { valid.contains($0) && !seen.contains($0) }
        if !missing.isEmpty {
            if pages.isEmpty { pages.append([]) }
            pages[pages.count - 1].append(contentsOf: missing.map { LayoutItem.app($0) })
        }
        normalize(capacity: capacity)
        return self != original
    }

    /// 預設版面：依名稱排序，系統「工具程式」收進一個資料夾放在最後（仿經典啟動台）。
    static func alphabetical(entries: [AppEntry], capacity: Int, hidden: Set<String> = []) -> Layout {
        let visible = entries.filter { !hidden.contains($0.id) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        let utilities = visible.filter { isUtility($0) }
        let others = visible.filter { !isUtility($0) }

        var items = others.map { LayoutItem.app($0.id) }
        if utilities.count >= 2 {
            items.append(.folder(FolderData(name: String(localized: "工具程式"), apps: utilities.map(\.id))))
        } else {
            items.append(contentsOf: utilities.map { LayoutItem.app($0.id) })
        }
        var layout = Layout(pages: [items])
        layout.normalize(capacity: capacity)
        return layout
    }

    private static func isUtility(_ entry: AppEntry) -> Bool {
        entry.resolvedPath.hasPrefix("/System/Applications/Utilities/") || entry.path.hasPrefix("/Applications/Utilities/")
    }
}

// MARK: - 資料夾命名

nonisolated enum FolderNaming {
    /// 依兩個 App 的 App Store 分類產生資料夾名稱（仿經典啟動台）：分類相同用該分類，否則用目標 App 的分類。
    static func name(target: AppEntry?, dragged: AppEntry?) -> String {
        let targetName = target?.category.flatMap(categoryName)
        let draggedName = dragged?.category.flatMap(categoryName)
        if let targetName, targetName == draggedName { return targetName }
        return targetName ?? draggedName ?? String(localized: "資料夾")
    }

    /// LSApplicationCategoryType → 顯示名稱。
    static func categoryName(_ category: String) -> String? {
        let key = category.replacingOccurrences(of: "public.app-category.", with: "")
        if key.hasSuffix("-games") || key == "games" { return String(localized: "遊戲") }
        let names: [String: String.LocalizationValue] = [
            "developer-tools": "開發者工具", "productivity": "生產力工具", "utilities": "工具程式",
            "graphics-design": "圖形與設計", "photography": "攝影", "video": "影片", "music": "音樂",
            "entertainment": "娛樂", "social-networking": "社交", "business": "商務", "education": "教育",
            "finance": "財經", "news": "新聞", "reference": "參考", "lifestyle": "生活風格",
            "healthcare-fitness": "健康與健身", "medical": "醫療", "travel": "旅遊", "weather": "天氣",
            "sports": "運動", "books": "書籍", "navigation": "導航", "food-and-drink": "飲食",
        ]
        return names[key].map { String(localized: $0) }
    }
}
