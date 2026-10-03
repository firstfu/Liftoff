//
//  LocalizationTests.swift
//  LiftoffTests
//
//  字串目錄（Localizable.xcstrings）的完整性：每個字串在所有支援語言都有譯文、佔位符種類與數量與原文一致、
//  不殘留已經不用的字串。新增介面文字卻忘了翻譯，會在這裡直接失敗，而不是讓使用者看到中文或英文混雜。
//

import Foundation
import Testing

struct LocalizationTests {
    /// 介面支援的語言（來源語言 zh-Hant 也要有明確條目，否則預設語言為 en 時繁中使用者會退回英文）
    static let languages = ["zh-Hant", "zh-Hans", "en", "ja", "ko", "de", "fr", "es", "pt-BR", "it", "ru", "tr", "nl"]

    private struct Catalog: Decodable {
        struct Entry: Decodable {
            struct Localization: Decodable {
                struct Unit: Decodable { let value: String }
                let stringUnit: Unit?
            }
            let shouldTranslate: Bool?
            let localizations: [String: Localization]?
        }
        let sourceLanguage: String
        let strings: [String: Entry]
    }

    /// 直接讀原始碼樹裡的目錄檔（建置後的 bundle 只剩編譯過的 .strings）。
    private func loadCatalog() throws -> Catalog {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Liftoff/Resources/Localizable.xcstrings")
        return try JSONDecoder().decode(Catalog.self, from: Data(contentsOf: url))
    }

    /// 取出格式佔位符的種類（忽略位置參數編號），用來比對譯文與原文是否一致。
    private func placeholders(_ s: String) -> [String] {
        let regex = try! NSRegularExpression(pattern: #"%(?:\d+\$)?(lld|@)"#)
        let range = NSRange(s.startIndex..., in: s)
        return regex.matches(in: s, range: range).map { (s as NSString).substring(with: $0.range(at: 1)) }.sorted()
    }

    @Test func sourceLanguageIsTraditionalChinese() throws {
        #expect(try loadCatalog().sourceLanguage == "zh-Hant")
    }

    @Test func everyStringHasEveryLanguage() throws {
        let catalog = try loadCatalog()
        var missing: [String] = []
        for (key, entry) in catalog.strings where entry.shouldTranslate != false {
            for language in Self.languages where entry.localizations?[language]?.stringUnit?.value.isEmpty != false {
                missing.append("\(language)：\(key)")
            }
        }
        #expect(missing.isEmpty, "缺少譯文：\(missing.sorted().prefix(10))")
    }

    @Test func placeholdersMatchTheSource() throws {
        let catalog = try loadCatalog()
        var broken: [String] = []
        for (key, entry) in catalog.strings where entry.shouldTranslate != false {
            for language in Self.languages {
                guard let value = entry.localizations?[language]?.stringUnit?.value else { continue }
                if placeholders(value) != placeholders(key) { broken.append("\(language)：\(key) → \(value)") }
            }
        }
        #expect(broken.isEmpty, "佔位符與原文不一致：\(broken.prefix(5))")
    }

    @Test func noLeftoverChineseInOtherLanguages() throws {
        let catalog = try loadCatalog()
        let cjkLanguages: Set = ["zh-Hant", "zh-Hans", "ja", "ko"]
        var leaks: [String] = []
        for (key, entry) in catalog.strings where entry.shouldTranslate != false {
            for language in Self.languages where !cjkLanguages.contains(language) {
                guard let value = entry.localizations?[language]?.stringUnit?.value else { continue }
                // 中文標點與漢字區段；譯文裡不該出現
                if value.unicodeScalars.contains(where: { (0x3000...0x303F).contains($0.value) || (0x4E00...0x9FFF).contains($0.value) || (0xFF00...0xFFEF).contains($0.value) }) {
                    leaks.append("\(language)：\(key) → \(value)")
                }
            }
        }
        #expect(leaks.isEmpty, "非中日韓語言殘留中文：\(leaks.prefix(5))")
    }
}
