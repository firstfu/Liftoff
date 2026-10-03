//
//  AppClassifier.swift
//  Liftoff
//
//  智慧整理的分類規則：判斷每個 App 該放進哪個資料夾。
//  依序看：系統「工具程式」位置 → 內建對照表（bundle ID，再退而用 .app 檔名）→ App 自填的 App Store 類別。
//  App 自填類別有七成以上是空白或籠統的 productivity／utilities（實測），所以只採用明確的類別，
//  其餘寧可不分類（放在資料夾外），也不要硬塞進錯的資料夾。
//
//  對照表在 Resources/AppCategories.json：由 Homebrew 熱門 App 與人工整理的清單建成，一個 App 一行，方便發 PR 補充。
//

import Foundation

/// 智慧整理的資料夾種類。rawValue 即對照表中的 folder 值。
nonisolated enum AppFolder: String, CaseIterable, Codable, Sendable {
    case developer, productivity, communication, browser, media, design, utilities
    case cloud, ai, education, finance, games, lifestyle
    /// 系統的「工具程式」（/System/Applications/Utilities 等）：依位置判斷，不在對照表裡
    case systemUtilities

    /// 資料夾顯示名稱。
    var displayName: String {
        switch self {
        case .developer: String(localized: "開發工具")
        case .productivity: String(localized: "辦公與文件")
        case .communication: String(localized: "溝通與社群")
        case .browser: String(localized: "網頁瀏覽")
        case .media: String(localized: "影音娛樂")
        case .design: String(localized: "照片與設計")
        case .utilities: String(localized: "系統工具")
        case .cloud: String(localized: "檔案與雲端")
        case .ai: String(localized: "AI 助理")
        case .education: String(localized: "學習與參考")
        case .finance: String(localized: "財經與購物")
        case .games: String(localized: "遊戲")
        case .lifestyle: String(localized: "生活")
        case .systemUtilities: String(localized: "工具程式")
        }
    }
}

nonisolated struct AppClassifier: Sendable {
    /// 分類依據（預覽時讓使用者知道哪些是推測的）。
    enum Source: Sendable {
        /// 系統工具程式資料夾裡的 App
        case location
        /// 對照表（bundle ID 或 .app 檔名）
        case table
        /// App 自填的 App Store 類別
        case category
    }

    struct Result: Sendable, Equatable {
        let folder: AppFolder
        let source: Source
    }

    /// bundle ID → 資料夾
    private let byBundleID: [String: AppFolder]
    /// 小寫的 .app 檔名 → 資料夾。bundle ID 對不上時的後備：同一個 App 從 App Store、官網、Setapp 安裝，
    /// bundle ID 可能不同（例如 OneDrive 的 App Store 版多了 "-mac"），檔名通常一樣
    private let byAppName: [String: AppFolder]

    init(byBundleID: [String: AppFolder], byAppName: [String: AppFolder]) {
        self.byBundleID = byBundleID
        self.byAppName = byAppName
    }

    /// 對照表檔案格式：`{"version": 1, "apps": {"<bundle ID>": {"folder": ..., "app": ..., "name": ...}}}`
    private struct TableFile: Decodable {
        struct Entry: Decodable {
            let folder: AppFolder
            let app: String?
        }
        let apps: [String: Entry]
    }

    /// 從 JSON 對照表建立。
    /// - Parameter data: AppCategories.json 的內容
    /// - Throws: JSON 格式錯誤，或 folder 不是已知的資料夾種類
    init(tableData data: Data) throws {
        let file = try JSONDecoder().decode(TableFile.self, from: data)
        // 檔名比對只採用沒有歧義的：同一個檔名在表裡對到不同資料夾（例如兩個不同的 Helium）時整個丟掉，
        // 免得結果取決於字典遍歷順序；這種 App 靠 bundle ID 比對即可
        var folders: [String: Set<AppFolder>] = [:]
        for entry in file.apps.values {
            if let app = entry.app?.lowercased(), !app.isEmpty { folders[app, default: []].insert(entry.folder) }
        }
        let byAppName = folders.compactMapValues { $0.count == 1 ? $0.first : nil }
        self.init(byBundleID: file.apps.mapValues(\.folder), byAppName: byAppName)
    }

    /// App 內建的對照表；讀不到時（理論上不會）退回只用位置與 App 類別判斷。
    static func bundled() -> AppClassifier {
        guard let url = Bundle.main.url(forResource: "AppCategories", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let classifier = try? AppClassifier(tableData: data) else {
            return AppClassifier(byBundleID: [:], byAppName: [:])
        }
        return classifier
    }

    /// 判斷 App 該放的資料夾。
    /// - Parameter entry: App
    /// - Returns: 資料夾與判斷依據；判斷不出來時為 nil（整理時留在資料夾外）
    func classify(_ entry: AppEntry) -> Result? {
        if Self.isSystemUtility(entry) { return Result(folder: .systemUtilities, source: .location) }
        if let id = entry.bundleID {
            if let folder = byBundleID[id] { return Result(folder: folder, source: .table) }
            // Setapp 版本的 bundle ID 是原版加上 "-setapp"
            if id.hasSuffix("-setapp"), let folder = byBundleID[String(id.dropLast("-setapp".count))] {
                return Result(folder: folder, source: .table)
            }
        }
        if let folder = byAppName[URL(fileURLWithPath: entry.path).lastPathComponent.lowercased()] {
            return Result(folder: folder, source: .table)
        }
        if let folder = entry.category.flatMap(Self.folder(forCategory:)) {
            return Result(folder: folder, source: .category)
        }
        return nil
    }

    /// 系統「工具程式」資料夾裡的 App（仿經典啟動台，收成一個資料夾）。
    static func isSystemUtility(_ entry: AppEntry) -> Bool {
        entry.resolvedPath.hasPrefix("/System/Applications/Utilities/") || entry.path.hasPrefix("/Applications/Utilities/")
    }

    /// App Store 類別（LSApplicationCategoryType）→ 資料夾。
    /// productivity、utilities、business 範圍太廣，對應不到單一資料夾，回傳 nil。
    static func folder(forCategory category: String) -> AppFolder? {
        let key = category.replacingOccurrences(of: "public.app-category.", with: "")
        if key == "games" || key.hasSuffix("-games") { return .games }
        switch key {
        case "developer-tools": return .developer
        case "graphics-design", "photography": return .design
        case "video", "music", "entertainment": return .media
        case "social-networking": return .communication
        case "education", "reference", "books": return .education
        case "finance": return .finance
        case "news", "healthcare-fitness", "medical", "lifestyle", "weather", "travel", "navigation", "food-and-drink", "sports":
            return .lifestyle
        default: return nil
        }
    }
}
