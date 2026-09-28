//
//  SettingsStore+AppLanguage.swift
//  Fluid
//
//  The language Setup and language names use. I speak and Show as stay separate.
//

import Combine
import Foundation

extension SettingsStore {
    private enum AppLanguageDefaults {
        static let id = "AppLanguageID"
    }

    /// Catalog id for the app language. English until Setup Wizard records a choice.
    var appLanguageID: String {
        get {
            let stored = self.defaults.string(forKey: AppLanguageDefaults.id)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if let stored, let language = TranslationLanguageCatalog.language(id: stored) {
                return language.id
            }
            return TranslationLanguageCatalog.english.id
        }
        set {
            let id = TranslationLanguageCatalog.language(id: newValue)?.id
                ?? TranslationLanguageCatalog.english.id
            if self.defaults.string(forKey: AppLanguageDefaults.id) == id { return }
            objectWillChange.send()
            self.defaults.set(id, forKey: AppLanguageDefaults.id)
            self.publishAppLanguageToSystem(id)
        }
    }

    var hasChosenAppLanguage: Bool {
        self.defaults.object(forKey: AppLanguageDefaults.id) != nil
    }

    /// Mac language when it is one of the setup languages. Otherwise English.
    static var suggestedAppLanguageID: String {
        for identifier in Locale.preferredLanguages {
            if let language = TranslationLanguageCatalog.language(id: identifier) {
                return language.id
            }
        }
        return TranslationLanguageCatalog.english.id
    }

    /// First time Setup Wizard opens, start from the Mac language so the picker is not stuck on English.
    func seedAppLanguageIfNeeded() {
        guard !self.hasChosenAppLanguage else { return }
        self.appLanguageID = Self.suggestedAppLanguageID
    }

    /// Per-app language for the next launch. Tests keep the shared domain alone.
    private func publishAppLanguageToSystem(_ languageID: String) {
        guard !Self.isRunningTests else { return }
        UserDefaults.standard.set(
            [AppLanguage.localeIdentifier(for: languageID)],
            forKey: "AppleLanguages"
        )
    }
}
