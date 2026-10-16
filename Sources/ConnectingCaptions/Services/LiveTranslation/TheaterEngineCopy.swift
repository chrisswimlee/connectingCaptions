import Foundation

/// User-facing copy that keeps Voice Engine (speech to text) separate from
/// Translation Engine (Apple Translation).
enum TheaterEngineCopy {
    static let voiceTitle = "Voice Engine"
    static let voicePurpose = "Sharpens speech into text for the language you speak."

    /// Name on the Voice Engine screen. The stored display names still say
    /// "Blazing Fast" and "Apple ASR Legacy" for older cards.
    static func voiceEngineName(_ model: SettingsStore.SpeechModel) -> String {
        switch model {
        case .parakeetTDT: return "Parakeet TDT v3"
        case .parakeetTDTv2: return "Parakeet TDT v2"
        case .parakeetRealtime: return "Parakeet Flash"
        case .qwen3Asr: return "Qwen3"
        case .cohereTranscribeSixBit: return "Cohere Transcribe"
        case .nemotronOffline: return "Nemotron 3.5"
        case .nemotronStreaming, .nemotronStreaming320: return "Nemotron Speech 3.5"
        case .appleSpeech: return "Apple Speech (older)"
        case .appleSpeechAnalyzer: return "Apple Speech Analyzer (newer)"
        case .whisperTiny: return "Whisper Tiny"
        case .whisperBase: return "Whisper Base"
        case .whisperSmall: return "Whisper Small"
        case .whisperMedium: return "Whisper Medium"
        case .whisperLargeTurbo: return "Whisper Large Turbo"
        case .whisperLarge: return "Whisper Large"
        }
    }

    static func voiceEngineDetail(_ model: SettingsStore.SpeechModel) -> String {
        switch model {
        case .appleSpeech:
            return "Prints while you talk. The recognizer macOS has included for years. Offline language support varies by Mac."
        case .appleSpeechAnalyzer:
            return "Prints while you talk. The recognizer added in macOS 26. Supported languages may need a speech asset download."
        case .whisperSmall:
            return "Prints while you talk. Also supports Either way for compatible translation pairs."
        default:
            let when = model.supportsStreaming ? "Prints while you talk" : "Prints when you stop"
            return "\(when). \(model.downloadSize). Runs locally after download."
        }
    }

    /// What `model` actually hears, spelled out by name instead of a vague
    /// "supported languages" badge — the thing someone picking an engine needs to know.
    static func languagesLine(for model: SettingsStore.SpeechModel) -> String {
        let names = VoiceEngineLanguageCatalog.supportedProductLanguages(for: model).map(\.displayName)
        if names.isEmpty {
            return "No caption languages available on this Mac right now"
        }
        if names.count == TranslationLanguageCatalog.all.count {
            return "Hears every caption language"
        }
        return "Hears \(names.joined(separator: ", "))"
    }

    static let translationTitle = "Translation Engine"
    static let translationPurpose = "Apple Translation on this Mac, not a chat model."

    static let translationName = "Apple Translation"

    static func voiceRunningLine(settings: SettingsStore = .shared) -> String {
        SpokenLanguageResolver.stageEngineSummary(settings: settings)
    }

    static func translationRunningLine(
        mode: TheaterSessionMode,
        sameLanguage: Bool,
        pack: TranslationPackAvailability
    ) -> String {
        switch mode {
        case .transcription:
            return "Voice writes what you say. Translation Engine stays off."
        case .translation:
            if sameLanguage {
                return "Same language — Apple Translation is not needed."
            }
            switch pack {
            case .installed:
                return "Running Apple Translation on this Mac."
            case .supported:
                return "Apple Translation needs this language pack once."
            case .unsupported:
                return "This pair is not supported by Apple Translation."
            case .unknown:
                return "Apple Translation is not ready yet."
            }
        }
    }
}
