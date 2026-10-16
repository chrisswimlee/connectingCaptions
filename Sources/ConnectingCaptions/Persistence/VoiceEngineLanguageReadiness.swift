import Foundation
import Speech

/// Speech recognition and translation packs are independent. These states describe
/// only the selected speech model and its assets for one spoken language.
enum VoiceEngineLanguageReadiness: Equatable {
    case checking, permissionRequired, unsupported, needsDownload, ready

    static func evaluate(
        supported: Bool?,
        installed: Bool?,
        permissionRequired: Bool = false
    ) -> Self {
        if permissionRequired { return .permissionRequired }
        guard let supported else { return .checking }
        guard supported else { return .unsupported }
        guard let installed else { return .checking }
        return installed ? .ready : .needsDownload
    }

    static func current(model: SettingsStore.SpeechModel, languageID: String) -> Self {
        let languageID = VoiceEngineLanguageCatalog.languagePrefix(languageID)
        return self.evaluate(
            supported: VoiceEngineLanguageCatalog.supportStatus(model, languageID: languageID),
            installed: VoiceEngineLanguageCatalog.isLanguageInstalled(model, languageID: languageID),
            permissionRequired: model == .appleSpeech && SFSpeechRecognizer.authorizationStatus() != .authorized
        )
    }

    /// Confirmed on this Mac. Used where a choice must be known to work (swap, "Supported languages").
    static func supportedLanguages(for model: SettingsStore.SpeechModel) -> [TranslationLanguage] {
        TranslationLanguageCatalog.menuOrder.filter {
            VoiceEngineLanguageCatalog.supportStatus(model, languageID: $0.id) == true
        }
    }

    /// What I speak menus offer: confirmed plus not-yet-known. Unknown rows show
    /// "Checking" or "Speech permission needed" instead of vanishing.
    static func offeredLanguages(for model: SettingsStore.SpeechModel) -> [TranslationLanguage] {
        TranslationLanguageCatalog.menuOrder.filter {
            VoiceEngineLanguageCatalog.supportStatus(model, languageID: $0.id) != false
        }
    }

    func message(model: SettingsStore.SpeechModel, language: TranslationLanguage) -> String {
        let modelName = TheaterEngineCopy.voiceEngineName(model)
        let languageName = AppLanguage.localizedName(for: language)
        switch self {
        case .checking:
            return AppLanguage.format("Checking {0} language support on this Mac…", modelName)
        case .permissionRequired:
            return AppLanguage.text("Allow Speech Recognition in Voice Engine to check offline language support.")
        case .unsupported:
            return AppLanguage.format("{0} cannot hear {1} offline on this Mac. Choose a supported language or another Voice Engine.", modelName, languageName)
        case .needsDownload:
            return AppLanguage.format("Download {0} for {1} in Voice Engine before Listen.", languageName, modelName)
        case .ready:
            return AppLanguage.format("Ready to hear {0}.", languageName)
        }
    }
}

enum EitherWayAvailability {
    /// Unknown and unsupported pairs stay hidden. Downloads remain explicit in Setup.
    static func isVisible(
        speechReady: Bool,
        forward: TranslationPackAvailability,
        reverse: TranslationPackAvailability
    ) -> Bool {
        speechReady && forward == .installed && reverse == .installed
    }
}
