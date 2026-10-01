import Foundation

/// Apple Translation is the caption engine.
enum TheaterTranslationEngineKind: String, CaseIterable, Identifiable {
    /// Translation Engine is Apple Translation only for now. The local LLM
    /// keeps its implementation; flip to `false` to offer it again.
    static let appleTranslationOnly = true

    case apple
    case localLLM

    var id: String { self.rawValue }

    var displayName: String {
        switch self {
        case .apple: return "Apple Translation"
        case .localLLM: return "Local small LLM (experimental)"
        }
    }

    var purpose: String {
        switch self {
        case .apple:
            return "Turns that text into a supported language. On this Mac. Not a chat model."
        case .localLLM:
            return "Experimental. A running local model can sharpen the first print. Apple Translation stays the fallback."
        }
    }
}

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
            return "Prints while you talk. The recognizer macOS has included for years. Hears the languages already on this Mac. No download."
        case .appleSpeechAnalyzer:
            return "Prints while you talk. The recognizer added in macOS 26. Hears the Speech Analyzer languages installed on this Mac."
        default:
            let when = model.supportsStreaming ? "Prints while you talk" : "Prints when you stop"
            return "\(when). \(model.languageSupport) · \(model.downloadSize)"
        }
    }

    static let translationTitle = "Translation Engine"
    static let translationPurpose = "Apple Translation on this Mac, not a chat model."

    static func translationName(settings: SettingsStore = .shared) -> String {
        settings.theaterTranslationEngine.displayName
    }

    static func voiceRunningLine(settings: SettingsStore = .shared) -> String {
        SpokenLanguageResolver.stageEngineSummary(settings: settings)
    }

    static func translationRunningLine(
        mode: TheaterSessionMode,
        sameLanguage: Bool,
        pack: TranslationPackAvailability,
        engine: TheaterTranslationEngineKind = .apple
    ) -> String {
        switch mode {
        case .transcription:
            return "Voice writes what you say. Translation Engine stays off."
        case .translation:
            if sameLanguage {
                return "Same language — Apple Translation is not needed."
            }
            if engine == .localLLM {
                return "Experimental local LLM can sharpen the first print. Apple Translation stays the fallback."
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
