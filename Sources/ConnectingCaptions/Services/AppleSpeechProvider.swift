// Upstream: FluidVoice (altic-dev), GPLv3. Apple Speech engine. Do not rewrite it to look original.
import AVFoundation
import Foundation
import Speech

// MARK: - Apple Speech Provider

/// A TranscriptionProvider that uses Apple's native SFSpeechRecognizer.
/// Recognition stays on device; the chosen language must support offline speech.
final class AppleSpeechProvider: TranscriptionProvider {
    var name: String { "Apple Speech (Legacy)" }

    /// Always available on macOS 10.15+ (Catalina and later)
    var isAvailable: Bool {
        SFSpeechRecognizer.authorizationStatus() != .restricted
    }

    /// Apple Speech is "always ready" (no downloads needed),
    /// but we track if we've checked permissions.
    private(set) var isReady: Bool = false

    /// The recognizer instance. We intentionally re-create it if the locale changes,
    /// using the language selected in Voice Engine/onboarding.
    private var recognizer: SFSpeechRecognizer?
    private var recognizerLocaleIdentifier: String?

    /// One recognition task for the whole Listen. Ticks append new audio and
    /// read the latest partial. They do not start a new recognizer.
    var streamingPreviewMode: StreamingPreviewMode { .incrementalDelta }
    var acceptedStreamingSampleCount: Int? {
        self.streamingLock.lock()
        defer { self.streamingLock.unlock() }
        return self.streamedSampleCount
    }

    private let streamingLock = NSLock()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var streamedSampleCount = 0
    private var streamEpoch: UInt64 = 0
    private var streamGeneration = 0
    private var streamCommitted = ""
    private var streamVolatile = ""
    private var streamText = ""
    private var streamFinished = true
    private var streamFailure: Error?
    private var streamSawEnd = false
    private var streamRestartStreak = 0
    private var streamLastRestart = Date.distantPast
    private var streamLocaleID = ""

    init() {
        _ = self.updateRecognizerIfNeeded()
    }

    // MARK: - Lifecycle

    func prepare(progressHandler: ((ModelPreparationProgress) -> Void)?) async throws {
        self.isReady = false
        // 1. Request Authorization
        let status = await self.requestAuthorization()

        switch status {
        case .authorized:
            guard let recognizer = self.updateRecognizerIfNeeded(), recognizer.supportsOnDeviceRecognition else {
                throw NSError(domain: "AppleSpeechProvider", code: 7, userInfo: [
                    NSLocalizedDescriptionKey: "This language is unavailable for offline Apple Speech on this Mac. Choose a supported language or another Voice Engine."
                ])
            }
            self.isReady = true
            DebugLogger.shared.info("AppleSpeechProvider authorized and ready", source: "AppleSpeechProvider")
        case .denied:
            throw NSError(domain: "AppleSpeechProvider", code: 1, userInfo: [NSLocalizedDescriptionKey: "Speech recognition permission denied. Open Settings and turn Speech Recognition on."])
        case .restricted:
            throw NSError(domain: "AppleSpeechProvider", code: 2, userInfo: [NSLocalizedDescriptionKey: "Speech recognition is restricted on this device."])
        case .notDetermined:
            self.isReady = false
            throw NSError(domain: "AppleSpeechProvider", code: 7, userInfo: [NSLocalizedDescriptionKey: "Speech recognition permission did not finish. Open Settings and turn Speech Recognition on."])
        @unknown default:
            self.isReady = false
            throw NSError(domain: "AppleSpeechProvider", code: 8, userInfo: [NSLocalizedDescriptionKey: "Speech recognition permission is unavailable. Open Settings and turn Speech Recognition on."])
        }
    }

    func clearCache() async throws {
        // No cache to clear for system speech
    }

    func releaseMemory() async {
        await self.resetStreamingSession()
    }

    func resetStreamingSession() async {
        let (task, request) = self.takeDownStream()
        request?.endAudio()
        task?.cancel()
    }

    /// Locking stays in a synchronous function. `NSLock` is not available
    /// directly inside an async function.
    private func takeDownStream() -> (SFSpeechRecognitionTask?, SFSpeechAudioBufferRecognitionRequest?) {
        self.streamingLock.lock()
        defer { self.streamingLock.unlock() }
        self.streamEpoch += 1
        let task = self.recognitionTask
        let request = self.recognitionRequest
        self.recognitionTask = nil
        self.recognitionRequest = nil
        self.streamFinished = true
        self.streamedSampleCount = 0
        self.streamCommitted = ""
        self.streamVolatile = ""
        self.streamText = ""
        self.streamGeneration = 0
        self.streamFailure = nil
        self.streamSawEnd = false
        self.streamRestartStreak = 0
        self.streamLocaleID = ""
        return (task, request)
    }

    private func endOpenStreamAudio() {
        self.streamingLock.lock()
        self.recognitionRequest?.endAudio()
        self.streamingLock.unlock()
    }

    func modelsExistOnDisk() -> Bool {
        return true // System models are always "on disk"
    }

    // MARK: - Transcription

    func transcribe(_ samples: [Float]) async throws -> ASRTranscriptionResult {
        guard self.isAvailable else {
            throw NSError(domain: "AppleSpeechProvider", code: 3, userInfo: [NSLocalizedDescriptionKey: "Speech recognition unavailable"])
        }

        // 1. Convert [Float] samples to AVAudioPCMBuffer
        guard let buffer = self.createPCMBuffer(from: samples) else {
            throw NSError(domain: "AppleSpeechProvider", code: 4, userInfo: [NSLocalizedDescriptionKey: "Failed to create audio buffer"])
        }

        // A one-shot buffer uses its own recognizer so it cannot cancel the
        // continuous Listen task, which is the only task on `self.recognizer`.
        guard let recognizer = SFSpeechRecognizer(locale: self.theaterSpeechLocale()) else {
            throw NSError(domain: "AppleSpeechProvider", code: 5, userInfo: [NSLocalizedDescriptionKey: "Failed to initialize SFSpeechRecognizer"])
        }

        if !recognizer.isAvailable {
            throw NSError(domain: "AppleSpeechProvider", code: 6, userInfo: [NSLocalizedDescriptionKey: "SFSpeechRecognizer is currently unavailable"])
        }

        guard recognizer.supportsOnDeviceRecognition else {
            throw NSError(domain: "AppleSpeechProvider", code: 7, userInfo: [
                NSLocalizedDescriptionKey: "On-device speech recognition is unavailable for this language on this Mac."
            ])
        }

        // 3. Create Request
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = false // We want the final result for this chunk
        request.requiresOnDeviceRecognition = true
        request.contextualStrings = Array(TranslationGlossary.protectedTerms().prefix(100))
        request.append(buffer)
        request.endAudio() // Signal that this buffer is the complete utterance for this request

        // 4. Execute Recognition
        return try await withCheckedThrowingContinuation { continuation in
            var hasResumed = false

            recognizer.recognitionTask(with: request) { result, error in
                // Ensure we only resume once
                guard !hasResumed else { return }

                if let error = error {
                    hasResumed = true
                    if Self.isBenignNoSpeech(error) {
                        continuation.resume(returning: ASRTranscriptionResult(text: "", confidence: 0.0))
                    } else {
                        DebugLogger.shared.warning("Apple transcribed error: \(DiagnosticMetadata.error(error))", source: "AppleSpeechProvider")
                        continuation.resume(throwing: error)
                    }
                    return
                }

                if let result = result, result.isFinal {
                    hasResumed = true
                    let transcription = result.bestTranscription.formattedString
                    DebugLogger.shared.debug("AppleSpeechProvider: Final result characters: \(transcription.count)", source: "AppleSpeechProvider")
                    let segments = result.bestTranscription.segments.map {
                        ASRTimedSegment(text: $0.substring, start: $0.timestamp, end: $0.timestamp + $0.duration)
                    }
                    continuation.resume(returning: ASRTranscriptionResult(text: transcription, confidence: 1.0, timedSegments: segments))
                }
                // Partial results ignored as we requested final only
            }
        }
    }

    func transcribeStreamingDelta(
        _ newSamples: [Float],
        totalSampleCount: Int
    ) async throws -> ASRTranscriptionResult {
        try self.ensureStreamRequest()
        let generation = self.streamGenerationLocked()
        if !newSamples.isEmpty {
            // A request that ends on this audio already has it. Sending the
            // same samples again starts a second copy of those words.
            if try self.appendToStream(newSamples) == false {
                try self.ensureStreamRequest()
                _ = try self.appendToStream(newSamples)
            }
            self.setStreamedCount(totalSampleCount)
            let wait: TimeInterval = self.streamTextLocked().isEmpty ? 0.7 : 0.12
            await self.waitForStreamResult(after: generation, timeout: wait)
        }
        return try self.streamResult()
    }

    func transcribeFinalDelta(
        _ newSamples: [Float],
        totalSampleCount: Int
    ) async throws -> ASRTranscriptionResult {
        if !newSamples.isEmpty {
            try self.ensureStreamRequest()
            _ = try self.appendToStream(newSamples)
            self.setStreamedCount(totalSampleCount)
        }
        self.endOpenStreamAudio()
        let generation = self.streamGenerationLocked()
        await self.waitForStreamResult(after: generation, timeout: 1)
        let deadline = Date().addingTimeInterval(1)
        while Date() < deadline, !self.streamIsFinished() {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        let snapshot = self.consumeStreamSnapshot()
        await self.resetStreamingSession()
        if snapshot.text.isEmpty, let failure = snapshot.failure, !Self.isBenignNoSpeech(failure) {
            throw failure
        }
        return ASRTranscriptionResult(
            text: snapshot.text,
            confidence: snapshot.text.isEmpty ? 0 : 1,
            endOfUtterance: true
        )
    }

    // MARK: - Helpers

    private func streamResult() throws -> ASRTranscriptionResult {
        let snapshot = self.consumeStreamSnapshot()
        if snapshot.text.isEmpty, let failure = snapshot.failure, !Self.isBenignNoSpeech(failure) {
            throw failure
        }
        return ASRTranscriptionResult(
            text: snapshot.text,
            confidence: snapshot.text.isEmpty ? 0 : 1,
            endOfUtterance: snapshot.endOfUtterance
        )
    }

    private func ensureStreamRequest() throws {
        guard let recognizer = self.updateRecognizerIfNeeded(), recognizer.isAvailable else {
            throw NSError(domain: "AppleSpeechProvider", code: 5, userInfo: [
                NSLocalizedDescriptionKey: "Failed to initialize SFSpeechRecognizer",
            ])
        }
        guard recognizer.supportsOnDeviceRecognition else {
            throw NSError(domain: "AppleSpeechProvider", code: 7, userInfo: [
                NSLocalizedDescriptionKey: "On-device speech recognition is unavailable for this language on this Mac.",
            ])
        }
        self.streamingLock.lock()
        let currentLocale = self.recognizerLocaleIdentifier ?? ""
        let open = self.recognitionRequest != nil
            && !self.streamFinished
            && self.streamLocaleID == currentLocale
        let streak = self.streamRestartStreak
        let hasRequest = self.recognitionRequest != nil
        self.streamingLock.unlock()
        if open { return }
        if streak > 4 {
            throw NSError(domain: "AppleSpeechProvider", code: 9, userInfo: [
                NSLocalizedDescriptionKey: "Speech recognition stopped. Press Listen to start again.",
            ])
        }
        if hasRequest {
            self.abandonOpenStreamKeepingCaption()
        }
        self.streamingLock.lock()
        self.streamEpoch += 1
        let epoch = self.streamEpoch
        self.streamFinished = false
        self.streamFailure = nil
        self.streamingLock.unlock()

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true
        let phrases = Array(TranslationGlossary.protectedTerms().prefix(100))
        if !phrases.isEmpty {
            request.contextualStrings = phrases
        }
        let task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            self?.noteStream(result: result, error: error, epoch: epoch)
        }
        self.streamingLock.lock()
        if epoch != self.streamEpoch {
            self.streamingLock.unlock()
            task.cancel()
            return
        }
        self.recognitionRequest = request
        self.recognitionTask = task
        self.streamLocaleID = self.recognizerLocaleIdentifier ?? ""
        self.streamingLock.unlock()
    }

    private func abandonOpenStreamKeepingCaption() {
        self.streamingLock.lock()
        self.streamEpoch += 1
        let task = self.recognitionTask
        let request = self.recognitionRequest
        self.recognitionTask = nil
        self.recognitionRequest = nil
        self.streamFinished = true
        self.streamVolatile = ""
        self.streamText = self.streamCommitted
        self.streamingLock.unlock()
        request?.endAudio()
        task?.cancel()
    }

    /// False when the open request had already ended and did not take the audio.
    private func appendToStream(_ samples: [Float]) throws -> Bool {
        guard let buffer = self.createPCMBuffer(from: samples) else {
            throw NSError(domain: "AppleSpeechProvider", code: 4, userInfo: [
                NSLocalizedDescriptionKey: "Failed to create audio buffer",
            ])
        }
        self.streamingLock.lock()
        let request = self.recognitionRequest
        let finished = self.streamFinished
        self.streamingLock.unlock()
        guard let request, !finished else { return false }
        request.append(buffer)
        return true
    }

    private func setStreamedCount(_ count: Int) {
        self.streamingLock.lock()
        self.streamedSampleCount = count
        self.streamingLock.unlock()
    }

    private func streamIsFinished() -> Bool {
        self.streamingLock.lock()
        defer { self.streamingLock.unlock() }
        return self.streamFinished
    }

    private func streamGenerationLocked() -> Int {
        self.streamingLock.lock()
        defer { self.streamingLock.unlock() }
        return self.streamGeneration
    }

    private func streamTextLocked() -> String {
        self.streamingLock.lock()
        defer { self.streamingLock.unlock() }
        return self.streamText
    }

    private func noteStream(result: SFSpeechRecognitionResult?, error: Error?, epoch: UInt64) {
        self.streamingLock.lock()
        defer { self.streamingLock.unlock() }
        guard epoch == self.streamEpoch else { return }
        if let error {
            self.streamFinished = true
            if !Self.isBenignNoSpeech(error) {
                self.streamFailure = error
                let now = Date()
                if now.timeIntervalSince(self.streamLastRestart) < 2 {
                    self.streamRestartStreak += 1
                } else {
                    self.streamRestartStreak = 1
                }
                self.streamLastRestart = now
            }
            self.streamGeneration += 1
            return
        }
        guard let result else { return }
        let text = result.bestTranscription.formattedString
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if result.isFinal {
            if !text.isEmpty {
                self.streamCommitted = Self.joiningCaption(self.streamCommitted, text)
            }
            self.streamVolatile = ""
            self.streamFinished = true
            self.streamSawEnd = true
        } else if !text.isEmpty {
            self.streamVolatile = text
            self.streamRestartStreak = 0
        }
        self.streamText = Self.joiningCaption(self.streamCommitted, self.streamVolatile)
        self.streamGeneration += 1
    }

    private func consumeStreamSnapshot() -> (text: String, failure: Error?, endOfUtterance: Bool) {
        self.streamingLock.lock()
        defer { self.streamingLock.unlock() }
        let end = self.streamSawEnd
        self.streamSawEnd = false
        return (self.streamText, self.streamFailure, end)
    }

    private func waitForStreamResult(after generation: Int, timeout: TimeInterval) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if self.streamGenerationLocked() != generation { return }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    private static func joiningCaption(_ committed: String, _ next: String) -> String {
        RecognizedSegmentJoin.absorb(existing: committed, next: next)
    }

    private static func isBenignNoSpeech(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        let nsError = error as NSError
        guard nsError.domain == "kAFAssistantErrorDomain" else { return false }
        return nsError.code == 1110 || nsError.code == 203 || nsError.code == 216
    }

    private func updateRecognizerIfNeeded() -> SFSpeechRecognizer? {
        let locale = self.theaterSpeechLocale()
        let localeIdentifier = locale.identifier.replacingOccurrences(of: "_", with: "-")
        if self.recognizer == nil || self.recognizerLocaleIdentifier != localeIdentifier {
            self.recognizer = SFSpeechRecognizer(locale: locale)
            self.recognizerLocaleIdentifier = localeIdentifier
        }
        return self.recognizer
    }

    private func theaterSpeechLocale() -> Locale {
        let sourceID = SpokenLanguageResolver.sourceLanguage().id
        let identifier = VoiceEngineLanguageCatalog.appleSpeechLegacyLocaleIdentifier(for: sourceID)
            ?? VoiceEngineLanguageCatalog.preferredAppleSpeechAnalyzerLocale(forLanguageID: sourceID)
        return Locale(identifier: identifier)
    }

    /// Converts raw [Float] samples (16kHz mono) to AVAudioPCMBuffer
    private func createPCMBuffer(from samples: [Float]) -> AVAudioPCMBuffer? {
        // Define format: 16kHz, Mono, Float32 (standard for ML/ASR)
        guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false) else {
            return nil
        }

        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)) else {
            return nil
        }

        buffer.frameLength = AVAudioFrameCount(samples.count)

        // Efficient copy
        guard let channelData = buffer.floatChannelData else { return nil }

        // Use withUnsafeBufferPointer for safe memory access
        samples.withUnsafeBufferPointer { samplePtr in
            guard let baseAddress = samplePtr.baseAddress else { return }
            // Copy memory from array to AVAudioPCMBuffer
            // channelData[0] is UnsafeMutablePointer<Float>
            channelData[0].update(from: baseAddress, count: samples.count)
        }

        return buffer
    }

    /// Structured concurrency wrapper for authorization
    private func requestAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }
}
