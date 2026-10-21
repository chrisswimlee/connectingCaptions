import Foundation

enum LiveTranslationThermalEngine {
    static let statusCopy = "Using Apple Speech because this Mac is hot."

    static func fallbackModel(isAppleSpeechAnalyzerAvailable: Bool) -> SettingsStore.SpeechModel {
        isAppleSpeechAnalyzerAvailable ? .appleSpeechAnalyzer : .appleSpeech
    }

    static func readyFallback(
        languageID: String,
        availableModels: [SettingsStore.SpeechModel] = SettingsStore.SpeechModel.availableModels,
        readiness: (SettingsStore.SpeechModel, String) -> VoiceEngineLanguageReadiness = VoiceEngineLanguageReadiness.current
    ) -> SettingsStore.SpeechModel? {
        [.appleSpeechAnalyzer, .appleSpeech].first {
            availableModels.contains($0) && readiness($0, languageID) == .ready
        }
    }

    static func shouldApply(
        current: SettingsStore.SpeechModel,
        thermal: ProcessInfo.ThermalState,
        alreadyOverridden: Bool
    ) -> Bool {
        guard !alreadyOverridden else { return false }
        guard LiveTranslationSilenceGate.shouldDowngradeEngine(thermal) else { return false }
        switch current {
        case .appleSpeech, .appleSpeechAnalyzer:
            return false
        default:
            return true
        }
    }
}

/// Mirrors `LiveTranslationThermalEngine`'s shape: a bad condition detected mid-session
/// (there, heat; here, the active engine going silent despite real audio) triggers a
/// session-only Voice Engine swap via `ASRService`'s override mechanism, with a status
/// line instead of a silent failure.
enum LiveTranslationSilenceFallbackEngine {
    /// Chunks of real (non-silent) audio in a row that produced no transcribed text
    /// before concluding the engine itself — not the room — is the problem.
    static let consecutiveVoicedSilentChunksThreshold = 5

    static func shouldApply(consecutiveVoicedSilentChunks: Int, alreadyOverridden: Bool) -> Bool {
        guard !alreadyOverridden else { return false }
        return consecutiveVoicedSilentChunks >= self.consecutiveVoicedSilentChunksThreshold
    }

    static func statusCopy(switchedFrom: SettingsStore.SpeechModel, to: SettingsStore.SpeechModel) -> String {
        "Switched to \(to.displayName) — \(switchedFrom.displayName) wasn't hearing you."
    }
}
