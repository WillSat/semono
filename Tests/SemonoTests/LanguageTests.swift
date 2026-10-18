import Foundation
import Testing
@testable import Semono

struct LanguageTests {
    @Test func legacyCodesResolveToSupportedLanguages() {
        #expect(AppLanguage.resolve("zh") == .simplifiedChinese)
        #expect(AppLanguage.resolve("zh-Hans") == .simplifiedChinese)
        #expect(AppLanguage.resolve("zh-Hant") == .traditionalChinese)
        #expect(AppLanguage.resolve("zh-TW") == .traditionalChinese)
        #expect(AppLanguage.resolve("zh-HK") == .traditionalChinese)
        #expect(AppLanguage.resolve("en") == .english)
        #expect(AppLanguage.resolve("es") == .spanish)
        #expect(AppLanguage.resolve("ja") == .japanese)
        #expect(AppLanguage.resolve("ko") == .korean)
        #expect(AppLanguage.resolve("emoji") == .emoji)
        #expect(AppLanguage.resolve("lzh") == .traditionalChinese)
        #expect(AppLanguage.resolve("fr") == .english)
    }

    @Test func pickerOrderAndNames() {
        #expect(AppLanguage.allCases.count == 7)
        #expect(AppLanguage.allCases.map(\.nativeName) == [
            "Emoji 🎉", "简体中文", "繁體中文", "English", "日本語", "한국어", "Español",
        ])
    }

    @Test func emojiModePickerNamesContainNoEnglish() {
        let names = AppLanguage.allCases.map { $0.displayName(in: .emoji) }
        #expect(names == ["🎉", "🇨🇳", "🏮", "🇬🇧", "🇯🇵", "🇰🇷", "🇪🇸"])
        for name in names {
            #expect(name.range(of: "[A-Za-z]", options: .regularExpression) == nil)
        }
    }

    @Test func systemLanguageAlwaysResolvesToASupportedCode() {
        let detected = LocaleManager.detectSystemLanguage()
        #expect(AppLanguage(rawValue: detected) != nil)
    }

    @Test func systemIdentifiersChooseTheRightScript() {
        #expect(AppLanguage.forSystemIdentifier("en-US") == .english)
        #expect(AppLanguage.forSystemIdentifier("zh-Hans-CN") == .simplifiedChinese)
        #expect(AppLanguage.forSystemIdentifier("zh-Hant-TW") == .traditionalChinese)
        #expect(AppLanguage.forSystemIdentifier("zh-TW") == .traditionalChinese)
        #expect(AppLanguage.forSystemIdentifier("zh-HK") == .traditionalChinese)
        #expect(AppLanguage.forSystemIdentifier("zh-CN") == .simplifiedChinese)
        #expect(AppLanguage.forSystemIdentifier("es-MX") == .spanish)
        #expect(AppLanguage.forSystemIdentifier("ja-JP") == .japanese)
        #expect(AppLanguage.forSystemIdentifier("ko-KR") == .korean)
        #expect(AppLanguage.forSystemIdentifier("fr-FR") == .english)
        #expect(AppLanguage.forSystemIdentifier("lzh") == .english)
    }

    @Test func chineseTechnicalLabelsCoverChineseAndEmoji() {
        #expect(AppLanguage.simplifiedChinese.usesChineseTechnicalLabels)
        #expect(AppLanguage.traditionalChinese.usesChineseTechnicalLabels)
        #expect(AppLanguage.emoji.usesChineseTechnicalLabels)
        #expect(!AppLanguage.english.usesChineseTechnicalLabels)
        #expect(!AppLanguage.spanish.usesChineseTechnicalLabels)
        #expect(!AppLanguage.japanese.usesChineseTechnicalLabels)
        #expect(!AppLanguage.korean.usesChineseTechnicalLabels)
    }
}
