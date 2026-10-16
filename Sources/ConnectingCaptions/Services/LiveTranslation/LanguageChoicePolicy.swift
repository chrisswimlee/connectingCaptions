import Foundation

@MainActor
enum LanguageChoicePolicy {
    static func spokenLanguages(settings: SettingsStore = .shared) -> [TranslationLanguage] {
        let target = SpokenLanguageResolver.targetLanguage(settings: settings)
        return VoiceEngineLanguageReadiness.offeredLanguages(for: settings.selectedSpeechModel).filter {
            settings.theaterSessionMode == .transcription || self.translationOffered(
                AppleTranslationEngine.shared.cachedPackAvailability(source: $0, target: target)
            )
        }
    }

    static func targetLanguages(settings: SettingsStore = .shared) -> [TranslationLanguage] {
        let source = SpokenLanguageResolver.sourceLanguage(settings: settings)
        return TranslationLanguageCatalog.menuOrder.filter {
            self.translationOffered(AppleTranslationEngine.shared.cachedPackAvailability(source: source, target: $0))
        }
    }

    /// Onboarding picks the language before the Voice Engine, so only translation filters it.
    static func onboardingSourceLanguages(settings: SettingsStore = .shared) -> [TranslationLanguage] {
        let target = SpokenLanguageResolver.targetLanguage(settings: settings)
        return TranslationLanguageCatalog.menuOrder.filter {
            settings.theaterSessionMode == .transcription || self.translationOffered(
                AppleTranslationEngine.shared.cachedPackAvailability(source: $0, target: target)
            )
        }
    }

    /// Swap uses the same rule as the menus: only a confirmed "cannot" blocks it.
    /// A not-yet-checked engine or pair stays allowed; Listen readiness reports what is missing.
    static func canSwap(settings: SettingsStore = .shared) -> Bool {
        self.swapUnavailableReason(settings: settings) == nil
    }

    /// Why Swap is disabled, for its tooltip. `nil` means Swap is allowed.
    static func swapUnavailableReason(settings: SettingsStore = .shared) -> String? {
        let source = SpokenLanguageResolver.sourceLanguage(settings: settings)
        let target = SpokenLanguageResolver.targetLanguage(settings: settings)
        guard source.id != target.id else {
            return AppLanguage.text("I speak and Show as are the same language.")
        }
        let model = settings.selectedSpeechModel
        if VoiceEngineLanguageCatalog.supportStatus(model, languageID: target.id) == false {
            return AppLanguage.format(
                "{0} cannot hear {1}. Choose another Voice Engine to swap.",
                TheaterEngineCopy.voiceEngineName(model),
                AppLanguage.localizedName(for: target)
            )
        }
        if settings.theaterSessionMode == .translation,
           !self.translationOffered(AppleTranslationEngine.shared.cachedPackAvailability(source: target, target: source))
        {
            return AppLanguage.format(
                "Apple Translation cannot translate {0} into {1}.",
                AppLanguage.localizedName(for: target),
                AppLanguage.localizedName(for: source)
            )
        }
        return nil
    }

    /// Known to work, possibly after a download. Swap requires this.
    nonisolated static func translationSupported(_ status: TranslationPackAvailability) -> Bool {
        status == .installed || status == .supported
    }

    /// Shown in menus. Only a confirmed `.unsupported` hides a pair; `.unknown` is listed as Checking.
    nonisolated static func translationOffered(_ status: TranslationPackAvailability) -> Bool {
        status != .unsupported
    }
}
