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
    @Published var speakSpeed: ProIOSSpeakSpeed {
        didSet { self.defaults.set(self.speakSpeed.rawValue, forKey: Key.speakSpeed) }
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
        self.speakSpeed = self.defaults.string(forKey: Key.speakSpeed).flatMap(ProIOSSpeakSpeed.init(rawValue:)) ?? .normal
        self.captionSize = self.defaults.object(forKey: Key.captionSize) as? Double ?? 28
        self.inputUID = self.defaults.string(forKey: Key.inputUID)
    }

    private enum Key {
        static let engine = "pro.engine"
        static let spokenLine = "pro.spokenLine"
        static let speakCaptions = "pro.speakCaptions"
        static let speakSpeed = "pro.speakSpeed"
        static let captionSize = "pro.captionSize"
        static let inputUID = "pro.inputUID"
    }
}

/// How fast Read captions aloud speaks.
enum ProIOSSpeakSpeed: String, CaseIterable, Identifiable {
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

    var title: LocalizedStringResource {
        switch self {
        case .slower: return "Slower"
        case .normal: return "Normal"
        case .faster: return "Faster"
        case .fastest: return "Fastest"
        }
    }
}

/// The language's voice, upgraded to an Enhanced or Premium one the person
/// downloaded. Siri, novelty, and Personal Voice are left out.
@MainActor
enum ProIOSVoice {
    private static var cache: [String: AVSpeechSynthesisVoice?] = [:]

    static func voice(languageCode: String) -> AVSpeechSynthesisVoice? {
        if let cached = self.cache[languageCode] { return cached }
        let base = AVSpeechSynthesisVoice(language: languageCode)
        var found = base
        if let base {
            let better = AVSpeechSynthesisVoice.speechVoices()
                .filter { voice in
                    voice.language == base.language
                        && voice.quality.rawValue > base.quality.rawValue
                        && !voice.identifier.lowercased().contains(".siri")
                        && !voice.voiceTraits.contains(.isNoveltyVoice)
                        && !voice.voiceTraits.contains(.isPersonalVoice)
                }
                .sorted { $0.quality.rawValue != $1.quality.rawValue ? $0.quality.rawValue > $1.quality.rawValue : $0.identifier < $1.identifier }
                .first
            found = better ?? base
        }
        self.cache[languageCode] = found
        return found
    }

    /// A voice downloaded in Settings is used from the next line.
    static func forget() {
        self.cache.removeAll()
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
final class ProIOSSpeaker: NSObject, AVSpeechSynthesizerDelegate {
    /// How long the microphone stays held after the last line ends, so Listen
    /// does not hear the end of its own voice.
    nonisolated static let microphoneTailSeconds: TimeInterval = 0.35
    /// A voice that reports nothing for this long is treated as finished, so a
    /// line that never ends cannot keep the microphone closed.
    nonisolated static let stalledVoiceSeconds: TimeInterval = 10

    private let synthesizer = AVSpeechSynthesizer()
    /// Lines queued or speaking. `isSpeaking` can lag a finish or a Stop.
    private var pending: Set<ObjectIdentifier> = []
    private var quietUntil = Date.distantPast
    /// Last time a line was queued, started, reached a word, or ended.
    private var lastVoiceActivity = Date.distantPast

    override init() {
        super.init()
        self.synthesizer.delegate = self
        NotificationCenter.default.addObserver(
            forName: AVSpeechSynthesizer.availableVoicesDidChangeNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in ProIOSVoice.forget() }
        }
    }

    /// Listen drops microphone packets while this is true. Without it the
    /// phone captions its own voice through the speaker.
    var holdsMicrophone: Bool {
        let now = Date()
        if !self.pending.isEmpty, Self.voiceStalled(lastActivity: self.lastVoiceActivity, now: now) {
            self.pending.removeAll()
        }
        let speaking = !self.pending.isEmpty || now < self.quietUntil
        guard speaking else { return false }
        return Self.holdsMicrophone(
            speaking: speaking,
            outputPorts: AVAudioSession.sharedInstance().currentRoute.outputs.map(\.portType)
        )
    }

    /// Wired headphones, a hands-free headset, and LE earbuds or hearing aids
    /// keep the voice out of the room, so the microphone stays open. A
    /// Bluetooth music route may be a loudspeaker and is held like one.
    nonisolated static func holdsMicrophone(speaking: Bool, outputPorts: [AVAudioSession.Port]) -> Bool {
        guard speaking else { return false }
        let inEar: Set<AVAudioSession.Port> = [.headphones, .bluetoothHFP, .bluetoothLE]
        return outputPorts.isEmpty || outputPorts.contains { !inEar.contains($0) }
    }

    nonisolated static func voiceStalled(lastActivity: Date, now: Date) -> Bool {
        now.timeIntervalSince(lastActivity) > Self.stalledVoiceSeconds
    }

    func speak(_ text: String, languageCode: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let utterance = AVSpeechUtterance(string: trimmed)
        utterance.voice = ProIOSVoice.voice(languageCode: languageCode)
        utterance.rate = ProIOSSettings.shared.speakSpeed.rate
        self.pending.insert(ObjectIdentifier(utterance))
        self.lastVoiceActivity = Date()
        self.synthesizer.speak(utterance)
    }

    func stop() {
        self.synthesizer.stopSpeaking(at: .immediate)
        if !self.pending.isEmpty {
            self.pending.removeAll()
            self.quietUntil = Date().addingTimeInterval(Self.microphoneTailSeconds)
        }
    }

    private func utteranceEnded(_ id: ObjectIdentifier) {
        self.lastVoiceActivity = Date()
        guard self.pending.remove(id) != nil, self.pending.isEmpty else { return }
        self.quietUntil = Date().addingTimeInterval(Self.microphoneTailSeconds)
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor in self.utteranceEnded(id) }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        Task { @MainActor in self.lastVoiceActivity = Date() }
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        willSpeakRangeOfSpeechString characterRange: NSRange,
        utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in self.lastVoiceActivity = Date() }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor in self.utteranceEnded(id) }
    }
}
