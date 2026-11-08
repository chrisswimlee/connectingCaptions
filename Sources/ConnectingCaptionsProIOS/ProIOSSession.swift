import AVFoundation
import ConnectingCaptionsCore
import FluidAudio
import UIKit

/// Theater listen on iPhone and iPad. FluidVoice supplies the words. This type admits
/// finished sentences onto the board and asks Apple Translation for Show as.
@MainActor
final class ProIOSSession: ObservableObject {
    static let shared = ProIOSSession()

    @Published private(set) var board = TheaterBoardState()
    @Published private(set) var openTail = ""
    @Published private(set) var status = "Ready"
    @Published private(set) var isListening = false
    @Published private(set) var isPaused = false
    @Published private(set) var isStarting = false
    @Published var source = TranslationLanguageCatalog.english {
        didSet { self.bindListenLanguage() }
    }
    @Published var target = TranslationLanguageCatalog.spanish

    let translator = ProIOSTranslation()
    let settings = ProIOSSettings.shared
    private let recognizer: ProIOSRecognizer
    private let microphone = ProIOSMicrophone()
    private let speaker = ProIOSSpeaker()
    private var inFlight: [String] = []
    private var identities = Set<String>()
    /// Sentences Clear or Undo removed. The recognizer still has them until the next Listen.
    private var suppressedSources: [String] = []
    private var suppressedIdentities = Set<String>()
    /// Cumulative text already handled. Pause and Clear keep the suffix only.
    private var heardCut = HeardCut()
    private var lastHypothesis = ""
    private var listenGeneration = 0
    private var boardGeneration = 0
    private var activeEngine: StreamingModelVariant?
    private var interruptionObserver: NSObjectProtocol?
    private let listenLanguage = ListenLanguageBox()

    private init() {
        self.recognizer = ProIOSRecognizer(variant: ProIOSSettings.shared.engine)
        self.bindListenLanguage()
        self.translator.prepare(source: self.source, target: self.target)
        self.interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            Task { @MainActor in
                self?.audioInterrupted(note)
            }
        }
    }

    private func bindListenLanguage() {
        self.listenLanguage.set(self.source.id)
        let box = self.listenLanguage
        ListenLanguageID.resolve = { _ in box.get() }
    }

    /// Parakeet EOU hears English only. Other languages use Nemotron.
    private func engineForCurrentSource() -> StreamingModelVariant {
        guard self.source.id != "en" else { return self.settings.engine }
        switch self.settings.engine {
        case .parakeetEou160ms, .parakeetEou320ms:
            return .nemotron560ms
        case .parakeetEou1280ms:
            return .nemotron1120ms
        default:
            return self.settings.engine
        }
    }

    func selectEngine(_ engine: StreamingModelVariant) {
        guard !self.isListening, !self.isStarting else { return }
        Task { await self.recognizer.select(engine) }
    }

    func toggleListen() {
        if self.isListening || self.isStarting {
            Task { await self.stop() }
        } else {
            Task { await self.start() }
        }
    }

    func start() async {
        ProIOSLicenseStore.shared.rereadClock()
        if let blocked = ProIOSLicenseStore.shared.blockListenStart() {
            self.status = blocked
            return
        }
        self.translator.prepare(source: self.source, target: self.target)
        if self.source.id != self.target.id {
            await self.translator.refreshPackStatus()
            switch self.translator.packStatus {
            case .needsDownload, .downloading, .checking, .unsupported:
                self.status = self.packMessage
                return
            case .installed, .notNeeded:
                break
            }
        }
        let engine = self.engineForCurrentSource()
        let switchedFromEnglishOnlyParakeet = engine != self.settings.engine
        let generation = self.listenGeneration + 1
        self.listenGeneration = generation
        self.isStarting = true
        self.status = switchedFromEnglishOnlyParakeet
            ? "Parakeet EOU hears English only. Using Nemotron for \(self.source.displayName)."
            : "Downloading the FluidVoice model if this iPhone does not have it yet…"
        do {
            await self.recognizer.select(engine)
            await self.recognizer.setHandler { [weak self] text in
                Task { @MainActor in
                    self?.notePartial(text)
                }
            }
            try await self.recognizer.prepare()
            guard generation == self.listenGeneration else { return }
            self.microphone.onPacket = { [weak self] packet in
                Task {
                    await self?.ingest(packet, generation: generation)
                }
            }
            try self.microphone.start(preferredUID: self.settings.inputUID)
            guard generation == self.listenGeneration else {
                self.microphone.stop()
                return
            }
            self.forgetDroppedSpeech()
            self.replaceBoard()
            self.isStarting = false
            self.isPaused = false
            self.isListening = true
            self.activeEngine = engine
            self.setScreenAwake(true)
            guard ProIOSLicenseStore.shared.noteListenStarted() else {
                let message = ProIOSLicenseStore.shared.statusMessage
                    ?? "The trial clock could not be saved. Listen stays off."
                await self.stop(status: message)
                return
            }
            if let blocked = ProIOSLicenseStore.shared.blockListenStart() {
                await self.stop(status: blocked)
                return
            }
            self.status = "Listening with \(engine.displayName)"
        } catch {
            guard generation == self.listenGeneration else { return }
            self.isStarting = false
            self.isListening = false
            self.microphone.stop()
            self.setScreenAwake(false)
            self.status = error.localizedDescription
        }
    }

    func stop(status stoppedStatus: String = "Stopped") async {
        self.listenGeneration += 1
        let wasListening = self.isListening || self.isStarting
        self.isListening = false
        self.isPaused = false
        self.isStarting = false
        self.microphone.stop()
        self.speaker.stop()
        self.setScreenAwake(false)
        guard wasListening else { return }
        let final = await self.recognizer.finish()
        let raw = final.isEmpty ? self.lastHypothesis : final
        self.commitLeftover(self.heardCut.audible(after: raw) ?? "")
        self.openTail = ""
        self.refreshInsertLine()
        self.status = stoppedStatus
    }

    private func audioInterrupted(_ note: Notification) {
        guard self.interruptionObserver != nil else { return }
        guard
            let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
            let type = AVAudioSession.InterruptionType(rawValue: raw),
            type == .began,
            self.isListening || self.isStarting
        else { return }
        Task {
            await self.stop(status: "The microphone stopped because another app used it. Tap Listen to start again.")
        }
    }

    func togglePause() {
        guard self.isListening else { return }
        self.isPaused.toggle()
        if self.isPaused {
            self.speaker.stop()
            self.heardCut.freeze(self.lastHypothesis)
            self.openTail = ""
            self.setScreenAwake(false)
            self.status = "Paused"
        } else {
            self.setScreenAwake(true)
            self.status = "Listening with \((self.activeEngine ?? self.settings.engine).displayName)"
        }
    }

    func undo() {
        guard !self.board.rows.isEmpty else { return }
        let removed = self.board.rows.removeLast()
        self.suppress(removed.source)
        self.speaker.stop()
        self.refreshInsertLine()
    }

    func copyBoard() {
        let text = self.board.rows.map(\.translated).filter { !$0.isEmpty }.joined(separator: "\n")
        guard !text.isEmpty else { return }
        UIPasteboard.general.string = text
        self.status = "Copied"
    }

    func clearBoard() {
        for row in self.board.rows {
            self.suppress(row.source)
        }
        for pending in self.inFlight {
            self.suppress(pending)
        }
        self.heardCut.freeze(self.lastHypothesis)
        self.speaker.stop()
        self.replaceBoard()
        self.refreshInsertLine()
    }

    /// Drops translations that were already running. Row ids keep climbing so a new board cannot reuse an old row.
    private func replaceBoard() {
        let nextID = self.board.nextID
        self.boardGeneration += 1
        self.board = TheaterBoardState(nextID: nextID)
        self.openTail = ""
        self.inFlight = []
        self.identities = []
    }

    private func setScreenAwake(_ awake: Bool) {
        UIApplication.shared.isIdleTimerDisabled = awake
    }

    private func ingest(_ packet: MicPacket, generation: Int) async {
        guard generation == self.listenGeneration, self.isListening, !self.isPaused else { return }
        do {
            try await self.recognizer.ingest(packet)
        } catch {
            guard generation == self.listenGeneration else { return }
            self.status = error.localizedDescription
            await self.stop()
        }
    }

    private func notePartial(_ text: String) {
        guard self.isListening, !self.isPaused else { return }
        let hypothesis = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !hypothesis.isEmpty else { return }
        self.lastHypothesis = hypothesis
        guard let heard = self.heardCut.audible(after: hypothesis), !heard.isEmpty else {
            self.openTail = ""
            return
        }
        let unread = self.unread(from: heard)
        self.openTail = unread
        self.drain(unread, hypothesis: heard)
    }

    private func drain(_ text: String, hypothesis: String) {
        var rest = text
        for _ in 0 ..< 12 {
            guard let next = TranslationClauseSegmenter.nextMidTalkUnit(rest, languageID: self.source.id) else {
                self.openTail = rest
                return
            }
            if case .admit = TheaterBoardAdmission.decide(
                next.unit,
                languageID: self.source.id,
                phase: .propose,
                context: self.admissionContext(hypothesis: hypothesis)
            ) {
                self.admit(next.unit)
            }
            if next.rest.isEmpty || next.rest == rest {
                self.openTail = next.rest
                return
            }
            rest = next.rest
            self.openTail = rest
        }
    }

    private func commitLeftover(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var rest = self.unread(from: trimmed)
        // A full peel means this text was already printed or cleared. Putting it
        // back would undo Clear and Undo.
        if rest.isEmpty,
           self.suppressedSources.isEmpty,
           self.board.rows.isEmpty,
           self.inFlight.isEmpty
        {
            rest = trimmed
        }
        guard !rest.isEmpty else { return }
        for _ in 0 ..< 12 {
            guard let next = TranslationClauseSegmenter.nextCommitUnit(
                rest,
                languageID: self.source.id,
                allowPauseFinalize: true
            ) else { return }
            if TranslationClauseSegmenter.isTooThinToCommit(next.unit, languageID: self.source.id) {
                return
            }
            if case .admit = TheaterBoardAdmission.decide(
                next.unit,
                languageID: self.source.id,
                phase: .propose,
                context: self.admissionContext(hypothesis: text)
            ) {
                self.admit(next.unit)
            }
            if next.rest.isEmpty || next.rest == rest { return }
            rest = next.rest
        }
    }

    private func admit(_ unit: String) {
        self.inFlight.append(unit)
        self.identities.insert(TranslationClauseSegmenter.clauseIdentity(unit))
        let source = self.source
        let target = self.target
        let rowID = self.board.nextID
        self.board.nextID += 1
        let generation = self.boardGeneration
        Task {
            let translated: String
            do {
                translated = try await self.translator.translate(unit, source: source, target: target)
            } catch {
                guard generation == self.boardGeneration else { return }
                self.inFlight.removeAll { TranslationClauseSegmenter.isSameClause($0, unit) }
                self.suppress(unit)
                self.status = error.localizedDescription
                return
            }
            guard generation == self.boardGeneration else { return }
            self.publish(id: rowID, source: unit, translated: translated, sourceLanguage: source, targetLanguage: target)
        }
    }

    private func publish(
        id: UInt64,
        source: String,
        translated: String,
        sourceLanguage: TranslationLanguage,
        targetLanguage: TranslationLanguage
    ) {
        self.inFlight.removeAll { TranslationClauseSegmenter.isSameClause($0, source) }
        guard !self.board.rows.contains(where: { TranslationClauseSegmenter.isSameClause($0.source, source) }) else {
            return
        }
        self.board.rows.append(TheaterBoardRow(
            id: id,
            source: source,
            translated: translated,
            sourceLanguageID: sourceLanguage.id,
            targetLanguageID: targetLanguage.id
        ))
        if self.board.rows.count > 48 {
            self.board.rows.removeFirst(self.board.rows.count - 48)
        }
        self.refreshInsertLine()
        if self.isListening, !self.isPaused, self.settings.speakCaptions, sourceLanguage.id != targetLanguage.id {
            self.speaker.speak(translated, languageCode: targetLanguage.appleLanguageCode)
        }
    }

    private func refreshInsertLine() {
        let allowed = ProIOSLicenseStore.shared.blockListenStart() == nil
        let line = self.board.rows.last?.translated ?? ""
        ProIOSAppGroup.publish(line: allowed ? line : "", allowed: allowed && !line.isEmpty)
    }

    private func unread(from hypothesis: String) -> String {
        TranslationClauseSegmenter.leftoverTail(
            hypothesis,
            already: self.suppressedSources + self.board.rows.map(\.source) + self.inFlight,
            languageID: self.source.id
        )
    }

    private func admissionContext(hypothesis: String) -> TheaterBoardAdmission.Context {
        TheaterBoardAdmission.Context(
            peelSources: self.suppressedSources + self.board.rows.map(\.source),
            inFlightSources: self.inFlight,
            commitIdentities: self.suppressedIdentities.union(self.identities),
            latestHypothesis: hypothesis,
            audioContainsSpeech: true
        )
    }

    /// Clear and Undo drop a line the recognizer is still repeating.
    /// The line stays in this set until the next Listen, so it cannot print again.
    private func suppress(_ source: String) {
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if !self.suppressedSources.contains(where: { TranslationClauseSegmenter.isSameClause($0, trimmed) }) {
            self.suppressedSources.append(trimmed)
            if self.suppressedSources.count > 48 {
                self.suppressedSources.removeFirst(self.suppressedSources.count - 48)
            }
        }
        self.suppressedIdentities.insert(TranslationClauseSegmenter.clauseIdentity(trimmed))
        self.identities.remove(TranslationClauseSegmenter.clauseIdentity(trimmed))
    }

    /// A new Listen hears from scratch. Clear and Undo do not call this.
    private func forgetDroppedSpeech() {
        self.suppressedSources = []
        self.suppressedIdentities = []
        self.heardCut.clear()
        self.lastHypothesis = ""
    }

    private final class ListenLanguageBox: @unchecked Sendable {
        private let lock = NSLock()
        private var id = "en"

        func set(_ id: String) {
            self.lock.lock()
            self.id = id
            self.lock.unlock()
        }

        func get() -> String {
            self.lock.lock()
            defer { self.lock.unlock() }
            return self.id
        }
    }

    private var packMessage: String {
        switch self.translator.packStatus {
        case .needsDownload:
            return "Download the language pack, then Listen."
        case .downloading, .checking:
            return "Checking the language pack…"
        case .unsupported:
            return "Apple Translation does not have this language pair on this device."
        case .installed, .notNeeded:
            return ""
        }
    }
}

/// Speech already handled before Pause or Clear. The recognizer's cumulative line still
/// contains it; the board only hears the suffix.
private struct HeardCut {
    private(set) var frozen = ""

    mutating func freeze(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        self.frozen = trimmed
    }

    mutating func clear() {
        self.frozen = ""
    }

    /// Matches by words, ignoring case and punctuation. A later update often
    /// rewrites "The weather" as "The weather." and must not bring those words back.
    func audible(after text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard !self.frozen.isEmpty else { return trimmed }
        if self.frozen.hasPrefix(trimmed) {
            return nil
        }
        if trimmed.hasPrefix(self.frozen) {
            let suffix = trimmed.dropFirst(self.frozen.count)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return suffix.isEmpty ? nil : String(suffix)
        }
        let frozenWords = Self.words(self.frozen).map(Self.normalized)
        let words = Self.words(trimmed)
        let normalized = words.map(Self.normalized)
        if normalized.count <= frozenWords.count {
            return Array(frozenWords.prefix(normalized.count)) == normalized ? nil : trimmed
        }
        guard Array(normalized.prefix(frozenWords.count)) == frozenWords else { return trimmed }
        let suffix = words.dropFirst(frozenWords.count).joined(separator: " ")
        return suffix.isEmpty ? nil : suffix
    }

    private static func words(_ text: String) -> [String] {
        text.split(whereSeparator: \.isWhitespace).map(String.init)
    }

    private static func normalized(_ word: String) -> String {
        word.lowercased().filter { !$0.isPunctuation }
    }
}
