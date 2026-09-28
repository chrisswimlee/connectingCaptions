import AudioToolbox
import AVFoundation
import Foundation

enum TheaterSpokenPhase: Equatable {
    case idle
    case rendering
    case playing
}

struct TheaterSpokenLine: Equatable {
    var id: UInt64
    var text: String
    var languageID: String
}

struct TheaterSpokenRevision: Equatable {
    var pending: [TheaterSpokenLine]
    var cancelInFlight: Bool
}

enum TheaterSpokenOutputChoice: Equatable {
    case play
    case skipAndClear

    var clearsEngine: Bool { self == .skipAndClear }
}

enum TheaterSpokenEnginePlan: Equatable {
    case reuse
    case rebuild
}

/// Speaks a caption that has already been published. Drafts stay silent.
/// Playback uses the chosen output device and does not change the system default.
/// A line still waiting, or still being prepared, speaks the latest wording.
/// A line already playing finishes. A missed output stays silent.
@MainActor
final class TheaterSpokenDelivery {
    static let shared = TheaterSpokenDelivery()

    /// Preparing audio. This is not how long a line may play.
    nonisolated static let synthesisNanoseconds: UInt64 = 8_000_000_000
    nonisolated static let playbackSlackNanoseconds: UInt64 = 1_000_000_000
    /// How long a cancelled line may hold the queue. After this, the next line starts.
    nonisolated static let drainNanoseconds: UInt64 = 1_000_000_000
    /// How long `AVAudioEngine.start` may sit before this line is skipped.
    nonisolated static let engineStartNanoseconds: UInt64 = 2_000_000_000
    nonisolated static var maxPendingLines: Int { TheaterInbox.maxLines }

    private var pending: [TheaterSpokenLine] = []
    private var currentID: UInt64?
    private var phase: TheaterSpokenPhase = .idle
    private var generation: UInt64 = 0
    private var isDrainingPlayback = false
    private var sessionEnding = false
    private var engineStartInFlight = false
    private var playTask: Task<Void, Never>?
    private let synthesizer = AVSpeechSynthesizer()
    private var sessionEngine: AVAudioEngine?
    private var sessionPlayer: AVAudioPlayerNode?
    private var sessionSampleRate: Double = 0
    private var sessionChannelCount: AVAudioChannelCount = 0
    private var sessionOutputKey = ""
    private var outputSetFailedUID: String?
    private var cachedRouteUID: String?
    private var cachedRouteDeviceID: AudioDeviceID?
    private var cachedRouteFound = false
    private var cachedVoiceLanguageID: String?
    private var cachedVoice: AVSpeechSynthesisVoice?
    private var activeEngine: AVAudioEngine?
    private var activePlayer: AVAudioPlayerNode?
    private var activeFinish: PlaybackFinish?
    private var activeRender: RenderBox?
    private var activeRenderTimeout: Task<Void, Never>?

    func notePublished(id: UInt64, text: String, languageID: String) {
        guard Self.shouldSpeak(
            enabled: SettingsStore.shared.theaterSpeakCaptions,
            listenKind: LiveTranslationController.shared.listenKind,
            sameLanguage: SpokenLanguageResolver.isSameLanguagePair(),
            text: text,
            voiceInstalled: self.voice(for: languageID) != nil
        ) else { return }
        self.sessionEnding = false
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        self.pending = Self.enqueue(
            id: id,
            text: cleaned,
            languageID: languageID,
            pending: self.pending,
            currentID: self.currentID
        )
        self.pump()
    }

    /// A grown caption keeps this id. Pending and in-progress audio pick up the new wording.
    /// Playback that has already started finishes the line the room is hearing.
    func noteRevised(id: UInt64, text: String, languageID: String) {
        let revision = Self.revise(
            id: id,
            text: text,
            languageID: languageID,
            pending: self.pending,
            currentID: self.currentID,
            phase: self.phase
        )
        self.pending = revision.pending
        if revision.cancelInFlight {
            self.stopCurrent()
        }
    }

    func noteRemoved(id: UInt64) {
        self.pending.removeAll { $0.id == id }
        if self.currentID == id {
            self.stopCurrent()
        }
    }

    /// Drop lines that have not started. The line already speaking finishes.
    /// The shared output is released once nothing is left to play.
    func dropPending() {
        self.pending.removeAll()
        self.sessionEnding = true
        self.cachedVoiceLanguageID = nil
        self.cachedVoice = nil
        self.cachedRouteUID = nil
        self.outputSetFailedUID = nil
        if self.playTask == nil, self.currentID == nil, !self.engineStartInFlight {
            self.tearDownEngine()
        }
    }

    nonisolated static func shouldSpeak(
        enabled: Bool,
        listenKind: TranslationListenKind?,
        sameLanguage: Bool,
        text: String,
        voiceInstalled: Bool
    ) -> Bool {
        guard enabled, listenKind == .captions, !sameLanguage, voiceInstalled else { return false }
        return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Pending text is replaced in place. A line still being prepared is inserted
    /// at the front, and `cancelInFlight` tells the caller to stop that render
    /// only after the insert. A playing line and an unknown id stay as they are.
    nonisolated static func revise(
        id: UInt64,
        text: String,
        languageID: String,
        pending: [TheaterSpokenLine],
        currentID: UInt64?,
        phase: TheaterSpokenPhase
    ) -> TheaterSpokenRevision {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else {
            return TheaterSpokenRevision(pending: pending, cancelInFlight: false)
        }
        if let index = pending.firstIndex(where: { $0.id == id }) {
            var pending = pending
            pending[index].text = cleaned
            pending[index].languageID = languageID
            return TheaterSpokenRevision(pending: pending, cancelInFlight: false)
        }
        if currentID == id, phase == .rendering {
            var pending = pending
            pending.insert(
                TheaterSpokenLine(id: id, text: cleaned, languageID: languageID),
                at: 0
            )
            return TheaterSpokenRevision(pending: pending, cancelInFlight: true)
        }
        return TheaterSpokenRevision(pending: pending, cancelInFlight: false)
    }

    /// An id already waiting is replaced. An id already in flight is left alone.
    /// The queue keeps the latest lines, same bound as the task bar.
    nonisolated static func enqueue(
        id: UInt64,
        text: String,
        languageID: String,
        pending: [TheaterSpokenLine],
        currentID: UInt64?,
        maxLines: Int = TheaterSpokenDelivery.maxPendingLines
    ) -> [TheaterSpokenLine] {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return pending }
        if currentID == id { return pending }
        if let index = pending.firstIndex(where: { $0.id == id }) {
            var pending = pending
            pending[index].text = cleaned
            pending[index].languageID = languageID
            return pending
        }
        var pending = pending
        pending.append(TheaterSpokenLine(id: id, text: cleaned, languageID: languageID))
        if maxLines > 0, pending.count > maxLines {
            pending.removeFirst(pending.count - maxLines)
        }
        return pending
    }

    nonisolated static func enginePlan(
        running: Bool,
        formatMatches: Bool,
        outputMatches: Bool
    ) -> TheaterSpokenEnginePlan {
        if running, formatMatches, outputMatches { return .reuse }
        return .rebuild
    }

    /// Returns when the task finishes, or when `nanoseconds` elapses, whichever is first.
    /// The loser keeps running. A cancelled group child waiting on `task.value` would not.
    nonisolated static func waitForTask(_ task: Task<Void, Never>?, nanoseconds: UInt64) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let gate = DrainGate()
            if let task {
                Task {
                    await task.value
                    gate.finish(continuation)
                }
            }
            DispatchQueue.global(qos: .userInitiated).asyncAfter(
                deadline: .now() + .nanoseconds(Int(nanoseconds))
            ) {
                gate.finish(continuation)
            }
        }
    }

    nonisolated static func playbackNanoseconds(durationSeconds: Double) -> UInt64 {
        let seconds = max(0, durationSeconds)
        let duration = UInt64((seconds * 1_000_000_000).rounded(.up))
        return duration + Self.playbackSlackNanoseconds
    }

    nonisolated static func playbackNanoseconds(frameCount: Int, sampleRate: Double) -> UInt64 {
        guard frameCount > 0, sampleRate > 0 else { return Self.playbackSlackNanoseconds }
        return Self.playbackNanoseconds(durationSeconds: Double(frameCount) / sampleRate)
    }

    /// No chosen output plays on the current device. A chosen output that is
    /// missing or cannot be selected is `skipAndClear`.
    nonisolated static func outputChoice(
        preferredUID: String?,
        deviceFound: Bool,
        deviceSet: Bool
    ) -> TheaterSpokenOutputChoice {
        let uid = preferredUID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !uid.isEmpty else { return .play }
        guard deviceFound, deviceSet else { return .skipAndClear }
        return .play
    }

    static func lookupVoice(for languageID: String) -> AVSpeechSynthesisVoice? {
        let code = TranslationLanguageCatalog.language(id: languageID)?.appleLanguageCode ?? languageID
        if let voice = AVSpeechSynthesisVoice(language: code) {
            return voice
        }
        let prefix = code.lowercased()
        return AVSpeechSynthesisVoice.speechVoices().first {
            $0.language.lowercased().hasPrefix(prefix)
        }
    }

    private func pump() {
        guard !self.isDrainingPlayback,
              !self.engineStartInFlight,
              self.playTask == nil,
              self.currentID == nil,
              !self.pending.isEmpty
        else { return }
        let next = self.pending.removeFirst()
        let token = self.generation
        self.currentID = next.id
        self.phase = .rendering
        self.playTask = Task { [weak self] in
            await self?.play(next, generation: token)
            self?.finishPlay(id: next.id, generation: token)
        }
    }

    private func finishPlay(id: UInt64, generation token: UInt64) {
        guard token == self.generation else { return }
        if self.currentID == id {
            self.currentID = nil
        }
        self.playTask = nil
        self.phase = .idle
        if self.sessionEnding, self.pending.isEmpty, !self.engineStartInFlight {
            self.tearDownEngine()
            return
        }
        self.pump()
    }

    /// Cancel the line in flight and resume its waiter before the next `write`.
    /// The follow-up speaks whatever is at the front once that task has unwound.
    private func stopCurrent() {
        self.generation += 1
        let token = self.generation
        let task = self.playTask
        self.isDrainingPlayback = true
        self.playTask = nil
        self.currentID = nil
        self.phase = .idle
        self.activeRenderTimeout?.cancel()
        let render = self.activeRender
        self.activeRender = nil
        self.activeRenderTimeout = nil
        self.synthesizer.stopSpeaking(at: .immediate)
        self.activePlayer?.stop()
        self.activeFinish?.finish()
        render?.finish(discard: true)
        self.activePlayer = nil
        self.activeEngine = nil
        self.activeFinish = nil
        Task { [weak self] in
            await Self.waitForTask(task, nanoseconds: Self.drainNanoseconds)
            guard let self, self.generation == token else { return }
            self.isDrainingPlayback = false
            if self.sessionEnding, self.pending.isEmpty, !self.engineStartInFlight {
                self.tearDownEngine()
                return
            }
            self.pump()
        }
    }

    private func play(_ line: TheaterSpokenLine, generation token: UInt64) async {
        guard !Task.isCancelled, token == self.generation, self.currentID == line.id else { return }
        guard let voice = self.voice(for: line.languageID) else { return }
        let utterance = AVSpeechUtterance(string: line.text)
        utterance.voice = voice
        let buffers = await self.render(utterance)
        guard !Task.isCancelled, token == self.generation, self.currentID == line.id else { return }
        guard !buffers.isEmpty else { return }
        guard let player = await self.prepareSessionEngine(format: buffers[0].format, token: token) else { return }
        guard token == self.generation, self.currentID == line.id else { return }

        let finish = PlaybackFinish()
        self.activeFinish = finish
        self.phase = .playing
        player.play()
        let last = buffers.count - 1
        for (index, buffer) in buffers.enumerated() {
            let isLast = index == last
            player.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { _ in
                if isLast {
                    finish.finish()
                }
            }
        }
        let frameCount = buffers.reduce(0) { $0 + Int($1.frameLength) }
        let timeout = Self.playbackNanoseconds(
            frameCount: frameCount,
            sampleRate: buffers[0].format.sampleRate
        )
        await self.waitForPlayback(finish, timeoutNanoseconds: timeout, player: player)
        player.stop()
        if self.activeFinish === finish {
            self.activeFinish = nil
        }
        self.activePlayer = nil
        self.activeEngine = nil
    }

    /// Reuse the Listen engine when the format and output are unchanged.
    /// A start that does not return skips this line and leaves the queue free.
    private func prepareSessionEngine(format: AVAudioFormat, token: UInt64) async -> AVAudioPlayerNode? {
        if self.engineStartInFlight { return nil }
        let preferred = SettingsStore.shared.preferredOutputDeviceUID?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !preferred.isEmpty, self.outputSetFailedUID == preferred { return nil }
        let found = self.outputDeviceID(preferred: preferred)
        if !preferred.isEmpty, !found { return nil }
        let formatMatches = self.sessionSampleRate == format.sampleRate
            && self.sessionChannelCount == format.channelCount
        let plan = Self.enginePlan(
            running: self.sessionEngine?.isRunning == true,
            formatMatches: formatMatches,
            outputMatches: self.sessionOutputKey == preferred
        )
        if plan == .reuse, let player = self.sessionPlayer {
            self.activeEngine = self.sessionEngine
            self.activePlayer = player
            return player
        }
        self.tearDownEngine()
        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        if preferred.isEmpty == false, let deviceID = self.cachedRouteDeviceID {
            let deviceSet = Self.setOutputDevice(deviceID, engine: engine)
            let choice = Self.outputChoice(preferredUID: preferred, deviceFound: true, deviceSet: deviceSet)
            if choice.clearsEngine {
                self.outputSetFailedUID = preferred
                player.stop()
                engine.stop()
                return nil
            }
        }
        guard token == self.generation else {
            player.stop()
            engine.stop()
            return nil
        }
        let started = await self.startEngine(engine)
        guard started, token == self.generation, !self.engineStartInFlight else {
            if !self.engineStartInFlight {
                player.stop()
                engine.stop()
            }
            return nil
        }
        self.sessionEngine = engine
        self.sessionPlayer = player
        self.activeEngine = engine
        self.activePlayer = player
        self.sessionSampleRate = format.sampleRate
        self.sessionChannelCount = format.channelCount
        self.sessionOutputKey = preferred
        self.outputSetFailedUID = nil
        return player
    }

    private func outputDeviceID(preferred: String) -> Bool {
        if self.cachedRouteUID == preferred { return preferred.isEmpty || self.cachedRouteFound }
        self.cachedRouteUID = preferred
        guard !preferred.isEmpty else {
            self.cachedRouteDeviceID = nil
            self.cachedRouteFound = false
            return true
        }
        if let device = AudioDevice.listOutputDevices().first(where: { $0.uid == preferred }) {
            self.cachedRouteDeviceID = device.id
            self.cachedRouteFound = true
            return true
        }
        self.cachedRouteDeviceID = nil
        self.cachedRouteFound = false
        return false
    }

    private func voice(for languageID: String) -> AVSpeechSynthesisVoice? {
        if self.cachedVoiceLanguageID == languageID { return self.cachedVoice }
        let voice = Self.lookupVoice(for: languageID)
        self.cachedVoiceLanguageID = languageID
        self.cachedVoice = voice
        return voice
    }

    private func tearDownEngine() {
        self.sessionPlayer?.stop()
        self.sessionEngine?.stop()
        self.sessionPlayer = nil
        self.sessionEngine = nil
        self.activePlayer = nil
        self.activeEngine = nil
        self.activeFinish = nil
        self.sessionSampleRate = 0
        self.sessionChannelCount = 0
        self.sessionOutputKey = ""
    }

    /// `true` when the engine is running. A timeout leaves `engineStartInFlight` set
    /// until the late start returns, so the next line does not open a second engine.
    private func startEngine(_ engine: AVAudioEngine) async -> Bool {
        let startTask = Task.detached { () -> Bool in
            do {
                try engine.start()
                return true
            } catch {
                return false
            }
        }
        let outcome: Bool? = await withTaskGroup(of: Bool?.self) { group in
            group.addTask { await startTask.value }
            group.addTask {
                try? await Task.sleep(nanoseconds: Self.engineStartNanoseconds)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
        if outcome == true { return true }
        if outcome == false { return false }
        self.engineStartInFlight = true
        Task { @MainActor [weak self] in
            let ok = await startTask.value
            if ok { engine.stop() }
            guard let self else { return }
            self.engineStartInFlight = false
            self.pump()
        }
        return false
    }

    private func waitForPlayback(
        _ finish: PlaybackFinish,
        timeoutNanoseconds: UInt64,
        player: AVAudioPlayerNode
    ) async {
        let timeout = Task { @MainActor in
            try? await Task.sleep(nanoseconds: timeoutNanoseconds)
            guard !Task.isCancelled else { return }
            player.stop()
            finish.finish()
        }
        await finish.wait()
        timeout.cancel()
    }

    private func render(_ utterance: AVSpeechUtterance) async -> [AVAudioPCMBuffer] {
        let box = RenderBox()
        self.activeRender = box
        let buffers: [AVAudioPCMBuffer] = await withCheckedContinuation { continuation in
            box.arm(continuation)
            let timeout = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: Self.synthesisNanoseconds)
                guard !Task.isCancelled, let self, self.activeRender === box else { return }
                self.synthesizer.stopSpeaking(at: .immediate)
                box.finish(discard: true)
            }
            self.activeRenderTimeout = timeout
            self.synthesizer.write(utterance) { buffer in
                guard let pcm = buffer as? AVAudioPCMBuffer else {
                    timeout.cancel()
                    box.finish(discard: false)
                    return
                }
                if pcm.frameLength == 0 {
                    timeout.cancel()
                    box.finish(discard: false)
                } else {
                    box.append(pcm)
                }
            }
        }
        if self.activeRender === box {
            self.activeRender = nil
        }
        self.activeRenderTimeout?.cancel()
        self.activeRenderTimeout = nil
        return buffers
    }

    private static func setOutputDevice(_ deviceID: AudioDeviceID, engine: AVAudioEngine) -> Bool {
        guard let audioUnit = engine.outputNode.audioUnit else { return false }
        var id = deviceID
        let status = AudioUnitSetProperty(
            audioUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &id,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )
        return status == noErr
    }
}

private final class RenderBox: @unchecked Sendable {
    private let lock = NSLock()
    private var buffers: [AVAudioPCMBuffer] = []
    private var resumed = false
    private var continuation: CheckedContinuation<[AVAudioPCMBuffer], Never>?

    func arm(_ continuation: CheckedContinuation<[AVAudioPCMBuffer], Never>) {
        self.lock.lock()
        if self.resumed {
            self.lock.unlock()
            continuation.resume(returning: [])
            return
        }
        self.continuation = continuation
        self.lock.unlock()
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        self.lock.lock()
        if !self.resumed {
            self.buffers.append(buffer)
        }
        self.lock.unlock()
    }

    /// Resume once. `discard` drops buffers already received so a timeout
    /// cannot speak a chopped line.
    func finish(discard: Bool) {
        self.lock.lock()
        if self.resumed {
            self.lock.unlock()
            return
        }
        self.resumed = true
        let continuation = self.continuation
        let buffers = discard ? [] : self.buffers
        self.continuation = nil
        self.buffers = []
        self.lock.unlock()
        continuation?.resume(returning: buffers)
    }
}

private final class DrainGate: @unchecked Sendable {
    private let lock = NSLock()
    private var resumed = false

    func finish(_ continuation: CheckedContinuation<Void, Never>) {
        self.lock.lock()
        if self.resumed {
            self.lock.unlock()
            return
        }
        self.resumed = true
        self.lock.unlock()
        continuation.resume()
    }
}

private final class PlaybackFinish: @unchecked Sendable {
    private let lock = NSLock()
    private var finished = false
    private var resume: (() -> Void)?

    func wait() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            self.lock.lock()
            if self.finished {
                self.lock.unlock()
                continuation.resume()
                return
            }
            self.resume = { continuation.resume() }
            self.lock.unlock()
        }
    }

    func finish() {
        self.lock.lock()
        if self.finished {
            self.lock.unlock()
            return
        }
        self.finished = true
        let resume = self.resume
        self.lock.unlock()
        resume?()
    }
}
