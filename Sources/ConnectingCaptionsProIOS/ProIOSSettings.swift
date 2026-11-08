import AVFoundation
import FluidAudio
import Foundation

/// Choices that stay on this phone. The voice engine is one of FluidVoice's streaming models.
@MainActor
final class ProIOSSettings: ObservableObject {
    static let shared = ProIOSSettings()

    @Published var engine: StreamingModelVariant {
        didSet { self.defaults.set(self.engine.rawValue, forKey: Key.engine) }
    }
    @Published var spokenLine: Bool {
        didSet { self.defaults.set(self.spokenLine, forKey: Key.spokenLine) }
    }
    @Published var speakCaptions: Bool {
        didSet { self.defaults.set(self.speakCaptions, forKey: Key.speakCaptions) }
    }
    @Published var captionSize: Double {
        didSet { self.defaults.set(self.captionSize, forKey: Key.captionSize) }
    }
    @Published var inputUID: String? {
        didSet { self.defaults.set(self.inputUID, forKey: Key.inputUID) }
    }

    private let defaults = UserDefaults.standard

    private init() {
        let raw = self.defaults.string(forKey: Key.engine)
        self.engine = raw.flatMap(StreamingModelVariant.init(rawValue:)) ?? .parakeetEou320ms
        self.spokenLine = self.defaults.object(forKey: Key.spokenLine) as? Bool ?? true
        self.speakCaptions = self.defaults.bool(forKey: Key.speakCaptions)
        self.captionSize = self.defaults.object(forKey: Key.captionSize) as? Double ?? 28
        self.inputUID = self.defaults.string(forKey: Key.inputUID)
    }

    private enum Key {
        static let engine = "pro.engine"
        static let spokenLine = "pro.spokenLine"
        static let speakCaptions = "pro.speakCaptions"
        static let captionSize = "pro.captionSize"
        static let inputUID = "pro.inputUID"
    }
}

enum ProIOSAppGroup {
    static let identifier = "group.com.connectingcaptions.ios.pro"
    static let insertLineKey = "keyboard.insertLine"
    static let insertAllowedKey = "keyboard.insertAllowed"
    static let insertLineDidChange = "com.connectingcaptions.ios.pro.keyboard.insertLine"

    static func publish(line: String, allowed: Bool) {
        guard let defaults = UserDefaults(suiteName: Self.identifier) else { return }
        defaults.set(line, forKey: Self.insertLineKey)
        defaults.set(allowed, forKey: Self.insertAllowedKey)
        defaults.synchronize()
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(Self.insertLineDidChange as CFString),
            nil,
            nil,
            true
        )
    }
}

@MainActor
final class ProIOSSpeaker {
    private let synthesizer = AVSpeechSynthesizer()

    func speak(_ text: String, languageCode: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let utterance = AVSpeechUtterance(string: trimmed)
        utterance.voice = AVSpeechSynthesisVoice(language: languageCode)
        self.synthesizer.speak(utterance)
    }

    func stop() {
        self.synthesizer.stopSpeaking(at: .immediate)
    }
}
