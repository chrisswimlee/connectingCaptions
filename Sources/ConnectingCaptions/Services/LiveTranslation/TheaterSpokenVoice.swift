import AVFoundation
import CoreAudio
import Foundation

/// How fast Speak captions reads. Faster keeps an Either way conversation
/// moving and shortens the time the microphone is held.
enum TheaterSpokenSpeed: String, CaseIterable, Identifiable {
    case slower, normal, faster, fastest

    var id: String { self.rawValue }

    var rate: Float {
        switch self {
        case .slower: return 0.42
        case .normal: return AVSpeechUtteranceDefaultSpeechRate
        case .faster: return 0.56
        case .fastest: return 0.62
        }
    }

    var title: String {
        switch self {
        case .slower: return AppLanguage.text("Slower")
        case .normal: return AppLanguage.text("Normal")
        case .faster: return AppLanguage.text("Faster")
        case .fastest: return AppLanguage.text("Fastest")
        }
    }

    static func resolved(_ raw: String?) -> Self {
        raw.flatMap(Self.init(rawValue:)) ?? .normal
    }
}

/// Picks the voice for a language. The basic voice macOS hands out first is
/// replaced by an Enhanced or Premium one when the person has downloaded it.
enum TheaterSpokenVoice {
    struct Candidate: Equatable {
        var identifier: String
        var language: String
        var quality: Int
        /// Siri, novelty, and Personal Voice are left out: apps cannot always
        /// render Siri voices, and the others are not a caption voice.
        var usable: Bool
    }

    /// The highest quality usable voice for exactly this locale, but only when
    /// it beats the default. Otherwise the default, so nothing gets worse.
    static func bestIdentifier(locale: String, defaultIdentifier: String?, candidates: [Candidate]) -> String? {
        let key = Self.normalized(locale)
        let matching = candidates.filter { $0.usable && Self.normalized($0.language) == key }
        let floor = matching.first { $0.identifier == defaultIdentifier }?.quality ?? 0
        let better = matching
            .filter { $0.quality > floor }
            .sorted { $0.quality != $1.quality ? $0.quality > $1.quality : $0.identifier < $1.identifier }
            .first
        return better?.identifier ?? defaultIdentifier ?? matching.first?.identifier
    }

    /// The same locale's best installed voice, or `base` when none is better.
    static func upgraded(_ base: AVSpeechSynthesisVoice) -> AVSpeechSynthesisVoice {
        let installed = AVSpeechSynthesisVoice.speechVoices()
        let best = self.bestIdentifier(
            locale: base.language,
            defaultIdentifier: base.identifier,
            candidates: installed.map(Candidate.init(voice:))
        )
        return installed.first { $0.identifier == best } ?? base
    }

    private static func normalized(_ locale: String) -> String {
        locale.replacingOccurrences(of: "_", with: "-").lowercased()
    }
}

extension TheaterSpokenVoice.Candidate {
    init(voice: AVSpeechSynthesisVoice) {
        let traits = voice.voiceTraits
        self.init(
            identifier: voice.identifier,
            language: voice.language,
            quality: voice.quality.rawValue,
            usable: !voice.identifier.lowercased().contains(".siri")
                && !traits.contains(.isNoveltyVoice)
                && !traits.contains(.isPersonalVoice)
        )
    }
}

/// Whether the room can hear Speak captions. Headphones in the Mac's own jack
/// keep it out of the microphone. Bluetooth and USB outputs cannot be told
/// apart from speakers, so they are treated as speakers.
enum TheaterSpokenOutput {
    /// 'hdpn', the built-in output's headphone source.
    static let headphonesDataSource: UInt32 = 0x6864_706E

    static func reachesMicrophone(transportType: UInt32, outputDataSource: UInt32?) -> Bool {
        !(transportType == kAudioDeviceTransportTypeBuiltIn && outputDataSource == Self.headphonesDataSource)
    }

    /// The output Speak captions plays on: the chosen one, or the system default.
    static func currentReachesMicrophone(preferredUID: String?) -> Bool {
        let uid = preferredUID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let device = uid.isEmpty
            ? AudioDevice.getDefaultOutputDevice()
            : AudioDevice.listOutputDevices().first { $0.uid == uid }
        guard let device else { return true }
        return self.reachesMicrophone(
            transportType: device.transportType,
            outputDataSource: self.outputDataSource(device.id)
        )
    }

    private static func outputDataSource(_ deviceID: AudioObjectID) -> UInt32? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDataSource,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }
}
