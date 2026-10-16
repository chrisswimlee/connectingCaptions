import Foundation

/// Playback has its own voices and devices, independent of speech recognition.
enum SpokenCaptionAvailability: Equatable {
    case ready, sameLanguage, voiceMissing, outputMissing

    static func evaluate(sameLanguage: Bool, targetVoice: Bool, reverseVoice: Bool,
                         bidirectional: Bool, outputAvailable: Bool) -> Self {
        if sameLanguage { return .sameLanguage }
        if !targetVoice || (bidirectional && !reverseVoice) { return .voiceMissing }
        if !outputAvailable { return .outputMissing }
        return .ready
    }

    @MainActor
    static func current(settings: SettingsStore = .shared, outputUIDs: [String]) -> Self {
        let source = SpokenLanguageResolver.sourceLanguage(settings: settings)
        let target = SpokenLanguageResolver.targetLanguage(settings: settings)
        let uid = settings.preferredOutputDeviceUID ?? ""
        return self.evaluate(
            sameLanguage: SpokenLanguageResolver.isSameLanguagePair(settings: settings),
            targetVoice: TheaterSpokenDelivery.lookupVoice(for: target.id) != nil,
            reverseVoice: TheaterSpokenDelivery.lookupVoice(for: source.id) != nil,
            bidirectional: SpokenLanguageResolver.isDynamicPairingEnabled(settings: settings),
            outputAvailable: uid.isEmpty || outputUIDs.contains(uid)
        )
    }

    var detail: String {
        switch self {
        case .ready: return AppLanguage.text(TheaterReadiness.speakCaptions)
        case .sameLanguage: return AppLanguage.text("Speak captions is available when translating into another language.")
        case .voiceMissing: return AppLanguage.text("A playback voice is missing for this pair. Add a voice in macOS Accessibility settings, then return here. Either way needs voices for both languages.")
        case .outputMissing: return AppLanguage.text("The selected speaker is disconnected. Choose an available output below.")
        }
    }
}
