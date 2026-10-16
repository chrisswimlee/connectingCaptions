import Foundation

/// Shared by setup and caption menus. A supported language may still need assets.
enum LanguageOptionStatus: Equatable {
    case ready, speechDownload, translationDownload, checking, permissionRequired, unsupported

    static func resolve(speech: VoiceEngineLanguageReadiness?, translation: TranslationPackAvailability) -> Self {
        switch speech {
        case .unsupported: return .unsupported
        case .permissionRequired: return .permissionRequired
        case .checking: return .checking
        case .needsDownload: return .speechDownload
        case .ready, nil: break
        }
        switch translation {
        case .installed: return .ready
        case .supported: return .translationDownload
        case .unknown: return .checking
        case .unsupported: return .unsupported
        }
    }

    var title: String {
        switch self {
        case .ready: return AppLanguage.text("Ready")
        case .speechDownload: return AppLanguage.text("Speech download needed")
        case .translationDownload: return AppLanguage.text("Translation download needed")
        case .checking: return AppLanguage.text("Checking availability…")
        case .permissionRequired: return AppLanguage.text("Speech permission needed")
        case .unsupported: return AppLanguage.text("Not supported")
        }
    }

    var symbol: String {
        switch self {
        case .ready: return "checkmark.circle"
        case .speechDownload, .translationDownload: return "arrow.down.circle"
        case .checking: return "clock"
        case .permissionRequired, .unsupported: return "exclamationmark.triangle"
        }
    }
}

extension LanguageChoicePolicy {
    static func status(for language: TranslationLanguage, isSource: Bool, includeSpeech: Bool = true,
                       settings: SettingsStore = .shared) -> LanguageOptionStatus {
        let source = isSource ? language : SpokenLanguageResolver.sourceLanguage(settings: settings)
        let target = isSource ? SpokenLanguageResolver.targetLanguage(settings: settings) : language
        let speech = isSource && includeSpeech
            ? VoiceEngineLanguageReadiness.current(model: settings.selectedSpeechModel, languageID: source.id) : nil
        let translation: TranslationPackAvailability = settings.theaterSessionMode == .transcription
            ? .installed : AppleTranslationEngine.shared.cachedPackAvailability(source: source, target: target)
        return .resolve(speech: speech, translation: translation)
    }
}
