import Foundation

/// App language for interface copy and language names. User content is never translated here.
/// Caption languages stay on I speak and Show as.
enum AppLanguage {
    static func text(_ english: String, languageID: String? = nil) -> String {
        let id = languageID ?? SettingsStore.shared.appLanguageID
        guard id != TranslationLanguageCatalog.english.id else { return english }
        return AppLanguageCopy.translation(languageID: id, english: english)
            ?? AppInterfaceTranslation.shared.text(english, languageID: id)
            ?? english
    }

    static func format(_ template: String, _ arguments: String...) -> String {
        self.format(template, arguments: arguments)
    }

    static func format(_ template: String, arguments: [String]) -> String {
        let translated = Self.text(template)
        guard !arguments.isEmpty else { return translated }
        guard let regex = try? NSRegularExpression(pattern: "\\{([0-9]+)\\}") else { return translated }
        let result = NSMutableString(string: translated)
        let original = translated as NSString
        // Replace only markers in the original template. Braces inside a name,
        // file path, or other user value are never interpreted as another slot.
        for match in regex.matches(in: translated, range: NSRange(location: 0, length: original.length)).reversed() {
            guard let index = Int(original.substring(with: match.range(at: 1))), arguments.indices.contains(index) else { continue }
            result.replaceCharacters(in: match.range, with: arguments[index])
        }
        return result as String
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
