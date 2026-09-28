import Foundation

/// App language for Setup Wizard chrome and language names.
/// Caption languages stay on I speak and Show as.
enum AppLanguage {
    static func text(_ english: String, languageID: String? = nil) -> String {
        let id = languageID ?? SettingsStore.shared.appLanguageID
        guard id != TranslationLanguageCatalog.english.id else { return english }
        return AppLanguageCopy.translation(languageID: id, english: english) ?? english
    }

    static func stepLabel(current: Int, total: Int, title: String, languageID: String? = nil) -> String {
        let id = languageID ?? SettingsStore.shared.appLanguageID
        let format = self.text("Step %d of %d · %@", languageID: id)
        return String(
            format: format,
            locale: Locale(identifier: self.localeIdentifier(for: id)),
            current,
            total,
            title
        )
    }

    /// English keeps the catalog name. Other app languages use that language's own name.
    static func localizedName(for language: TranslationLanguage, languageID: String? = nil) -> String {
        let id = languageID ?? SettingsStore.shared.appLanguageID
        guard id != TranslationLanguageCatalog.english.id else { return language.displayName }
        let locale = Locale(identifier: self.localeIdentifier(for: id))
        if let name = locale.localizedString(forLanguageCode: language.appleLanguageCode), !name.isEmpty {
            return name
        }
        return language.displayName
    }

    /// Voice engines use `no`. Apple and Locale use `nb`.
    static func localeIdentifier(for languageID: String) -> String {
        TranslationLanguageCatalog.language(id: languageID)?.appleLanguageCode
            ?? TranslationLanguageCatalog.english.appleLanguageCode
    }

    static func layoutIsRightToLeft(languageID: String? = nil) -> Bool {
        let id = languageID ?? SettingsStore.shared.appLanguageID
        return id == "ar" || id == "he"
    }
}
