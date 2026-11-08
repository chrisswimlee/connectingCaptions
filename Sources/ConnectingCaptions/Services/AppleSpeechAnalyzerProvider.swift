// Upstream: FluidVoice (altic-dev), GPLv3. Apple Speech engine. Do not rewrite it to look original.
import AVFoundation
import Combine
import Foundation

#if canImport(Speech)
import Speech
#endif

// swiftlint:disable function_body_length cyclomatic_complexity type_body_length
// Tracked grandfather: existing FluidVoice-era file. New work belongs in a smaller file.

// MARK: - Apple Speech Analyzer Provider (macOS 26+)

/// A TranscriptionProvider that uses Apple's new SpeechAnalyzer API (macOS 26+).
/// This provides advanced speech-to-text with streaming capabilities.
@available(macOS 26.0, *)
final class AppleSpeechAnalyzerProvider: TranscriptionProvider {
    var name: String { "Apple Speech (macOS 26+)" }

    var isAvailable: Bool {
        // SpeechAnalyzer is always available on macOS 26+
        true
    }

    private(set) var isReady: Bool = false
    var shouldClearCacheAfterCancellation: Bool { false }
    var streamingPreviewMode: StreamingPreviewMode { .incrementalDelta }
    var acceptedStreamingSampleCount: Int? { self.streamedSampleCount }

    private var streamedSampleCount = 0
    private var streamingAnalyzer: SpeechAnalyzer?
    private var streamingContinuation: AsyncStream<AnalyzerInput>.Continuation?
    private var streamingResultsTask: Task<Void, Never>?
    private var streamingCommitted = ""
    private var streamingVolatile = ""
    private var streamingText = ""
    private var streamingResultGeneration = 0
    private var streamingFailure: Error?
    private var streamingLocaleID = ""
    private var streamingEpoch: UInt64 = 0
    private var streamingResultsOpen = false
    private let streamingLock = NSLock()

    /// Buffer converter for audio format conversion
    private var converter: BufferConverter?

    /// The required audio format for the analyzer
    private var analyzerFormat: AVAudioFormat?
    private var preparedLocale: Locale?

    /// Thread-safe cache for model installation status.
    /// Protected by `_cacheQueue` for thread-safe access from both sync and async contexts.
    private var _modelsInstalledCache: Bool = false
    private let _cacheQueue = DispatchQueue(label: "com.connectingcaptions.speechanalyzer.cache")

    init() {}

    // MARK: - Lifecycle

    func prepare(progressHandler: ((ModelPreparationProgress) -> Void)?) async throws {
        try Task.checkCancellation()
        self.discardPreparedLocaleIfItDoesNotMatchISpeak()
        let supportedLocales = await SpeechTranscriber.supportedLocales
        try Task.checkCancellation()
        let locale = try self.resolveSupportedLocale(from: supportedLocales)
        let localeID = self.normalizedIdentifier(for: locale)
        self.persistResolvedLocaleIfNeeded(localeID)

        // 1. Create a transcriber to check locale support and download if needed
        let transcriber = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [],
            attributeOptions: []
        )

        // 3. Check if model is installed, download if needed
        let installedLocales = await SpeechTranscriber.installedLocales
        try Task.checkCancellation()
        let isInstalled = self.localeIsInstalled(localeID, in: installedLocales)

        if !isInstalled {
            DebugLogger.shared.info("Downloading speech model for locale: \(localeID)", source: "AppleSpeechAnalyzerProvider")
            if let downloader = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                progressHandler?(.preparingDownload)
                // Report progress periodically during download
                let progress = downloader.progress
                let progressTask = Task {
                    while !Task.isCancelled, !progress.isFinished, !progress.isCancelled {
                        progressHandler?(.downloading(progress.fractionCompleted))
                        try? await Task.sleep(for: .milliseconds(100))
                    }
                }
                defer { progressTask.cancel() }

                do {
                    try await withTaskCancellationHandler {
                        try await downloader.downloadAndInstall()
                    } onCancel: {
                        progress.cancel()
                    }
                } catch {
                    let nsError = error as NSError
                    if Task.isCancelled
                        || error is CancellationError
                        || (nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled)
                    {
                        throw CancellationError()
                    }
                    throw error
                }
                try Task.checkCancellation()
                progressHandler?(.optimizing)
            }
        }

        // 4. Get the best available audio format for conversion
        progressHandler?(.loading)
        self.analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber])
        try Task.checkCancellation()
        self.converter = BufferConverter()
        self.preparedLocale = locale

        try Task.checkCancellation()
        self.isReady = true

        // Update cache to reflect that model is now installed (thread-safe)
        self._cacheQueue.sync { self._modelsInstalledCache = true }

        DebugLogger.shared.info("AppleSpeechAnalyzerProvider ready", source: "AppleSpeechAnalyzerProvider")
    }

    func invalidateIfListeningLanguageChanged() {
        self.discardPreparedLocaleIfItDoesNotMatchISpeak()
        self.streamingLocaleID = ""
    }

    func resetStreamingSession() async {
        self.streamingLock.lock()
        self.streamingEpoch += 1
        self.streamingResultsOpen = false
        self.streamingLock.unlock()
        self.streamingContinuation?.finish()
        self.streamingContinuation = nil
        let results = self.streamingResultsTask
        self.streamingResultsTask = nil
        results?.cancel()
        if let analyzer = self.streamingAnalyzer {
            await analyzer.cancelAndFinishNow()
        }
        self.streamingAnalyzer = nil
        _ = await results?.value
        self.streamedSampleCount = 0
        self.streamingLock.lock()
        self.streamingCommitted = ""
        self.streamingVolatile = ""
        self.streamingText = ""
        self.streamingResultGeneration = 0
        self.streamingFailure = nil
        self.streamingLock.unlock()
        self.streamingLocaleID = ""
    }

    /// Confirmation and other one-shot buffers. The live cursor stays where the
    /// ring left it; this call does not feed the incremental session.
    func transcribeStreaming(_ samples: [Float]) async throws -> ASRTranscriptionResult {
        try await self.transcribe(samples)
    }

    func transcribeStreamingDelta(
        _ newSamples: [Float],
        totalSampleCount: Int
    ) async throws -> ASRTranscriptionResult {
        if self.streamingAnalyzer != nil, !self.streamingResultsAreOpen() {
            throw NSError(
                domain: "AppleSpeechAnalyzerProvider",
                code: 4,
                userInfo: [NSLocalizedDescriptionKey: "Speech Analyzer session ended."]
            )
        }
        try await self.ensureStreamingSession()
        let generation = self.streamingGeneration()
        if !newSamples.isEmpty, let buffer = self.convertedBuffer(from: newSamples) {
            self.streamingContinuation?.yield(AnalyzerInput(buffer: buffer))
            self.streamedSampleCount = totalSampleCount
            await self.waitForStreamingResult(after: generation)
        }
        let snapshot = self.streamingSnapshot()
        if snapshot.text.isEmpty, let failure = snapshot.failure, !Self.isCancellation(failure) {
            throw failure
        }
        return ASRTranscriptionResult(text: snapshot.text, confidence: snapshot.text.isEmpty ? 0 : 1)
    }

    func transcribeFinalDelta(
        _ newSamples: [Float],
        totalSampleCount: Int
    ) async throws -> ASRTranscriptionResult {
        try await self.ensureStreamingSession()
        var finishError: Error?
        do {
            if !newSamples.isEmpty, let buffer = self.convertedBuffer(from: newSamples) {
                self.streamingContinuation?.yield(AnalyzerInput(buffer: buffer))
                self.streamedSampleCount = totalSampleCount
            }
            self.streamingContinuation?.finish()
            self.streamingContinuation = nil
            if let analyzer = self.streamingAnalyzer {
                try await analyzer.finalizeAndFinishThroughEndOfInput()
            }
            await self.streamingResultsTask?.value
        } catch {
            finishError = error
        }
        let snapshot = self.streamingSnapshot()
        let failure = finishError ?? snapshot.failure
        await self.resetStreamingSession()
        if snapshot.text.isEmpty, let failure, !Self.isCancellation(failure) {
            throw failure
        }
        return ASRTranscriptionResult(text: snapshot.text, confidence: snapshot.text.isEmpty ? 0 : 1)
    }

    func markPreparedLocaleForTesting(_ identifier: String) {
        self.preparedLocale = Locale(identifier: identifier)
        self.isReady = true
    }

    func clearCache() async throws {
        // Release reserved locales
        let reserved = await AssetInventory.reservedLocales
        for locale in reserved {
            await AssetInventory.release(reservedLocale: locale)
        }

        // Reset cache to reflect models are no longer installed (thread-safe)
        self._cacheQueue.sync { self._modelsInstalledCache = false }

        self.isReady = false
        self.preparedLocale = nil
    }

    /// Returns the cached result of whether models are installed (thread-safe).
    ///
    /// **Important**: This method returns a cached value that defaults to `false`.
    /// For an accurate result, call `refreshModelsExistOnDiskAsync()` first.
    ///
    /// The synchronous nature of this protocol method makes it impossible to
    /// perform the actual async `SpeechTranscriber.installedLocales` check inline.
    /// Callers should use `refreshModelsExistOnDiskAsync()` during initialization
    /// to populate the cache before relying on this value.
    func modelsExistOnDisk() -> Bool {
        return self._cacheQueue.sync { self._modelsInstalledCache }
    }

    /// Performs an async check to determine if speech models are installed for the current locale.
    /// Updates the internal cache so that subsequent `modelsExistOnDisk()` calls return accurate results.
    /// Thread-safe: uses dispatch queue to update cache.
    ///
    /// - Returns: `true` if the current locale's speech model is installed on disk, `false` otherwise.
    func refreshModelsExistOnDiskAsync() async -> Bool {
        let supportedLocales = await SpeechTranscriber.supportedLocales
        let installedLocales = await SpeechTranscriber.installedLocales
        let localeID: String
        if let resolved = try? self.resolveSupportedLocale(from: supportedLocales) {
            localeID = self.normalizedIdentifier(for: resolved)
        } else {
            localeID = self.normalizedIdentifier(for: self.selectedSpeechLocale())
        }
        let isInstalled = self.localeIsInstalled(localeID, in: installedLocales)

        self._cacheQueue.sync { self._modelsInstalledCache = isInstalled }

        DebugLogger.shared.debug(
            "AppleSpeechAnalyzer: Model installed check - locale: \(localeID), installed: \(isInstalled)",
            source: "AppleSpeechAnalyzerProvider"
        )

        return isInstalled
    }

    // MARK: - Transcription

    func transcribe(_ samples: [Float]) async throws -> ASRTranscriptionResult {
        if self.preparedLocaleDoesNotMatchISpeak() {
            self.discardPreparedLocaleIfItDoesNotMatchISpeak()
            throw NSError(
                domain: "AppleSpeechAnalyzerProvider",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Speech Analyzer is still set to hear a different language."]
            )
        }
        guard self.isReady, let analyzerFormat = self.analyzerFormat else {
            throw NSError(
                domain: "AppleSpeechAnalyzerProvider",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Speech Analyzer not ready"]
            )
        }

        DebugLogger.shared.debug("AppleSpeechAnalyzer: Starting transcription with \(samples.count) samples", source: "AppleSpeechAnalyzerProvider")
        let transcriptionLocale = self.preparedLocale ?? self.selectedSpeechLocale()

        // 1. Create a FRESH transcriber for this transcription
        let freshTranscriber = SpeechTranscriber(
            locale: transcriptionLocale,
            transcriptionOptions: [],
            reportingOptions: [],
            attributeOptions: [.audioTimeRange]
        )

        // 2. Create input stream
        let (inputStream, inputContinuation) = AsyncStream<AnalyzerInput>.makeStream()

        // 3. Create a fresh analyzer with the fresh transcriber
        let analyzer = SpeechAnalyzer(modules: [freshTranscriber])
        await self.applyGlossaryContext(to: analyzer)

        // 4. Convert samples to AVAudioPCMBuffer
        guard let buffer = createPCMBuffer(from: samples) else {
            throw NSError(
                domain: "AppleSpeechAnalyzerProvider",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: "Failed to create audio buffer"]
            )
        }

        // 5. Convert to analyzer format if needed
        let convertedBuffer: AVAudioPCMBuffer
        if let converter = self.converter {
            do {
                convertedBuffer = try converter.convertBuffer(buffer, to: analyzerFormat)
            } catch {
                DebugLogger.shared.warning("Buffer conversion failed: \(error)", source: "AppleSpeechAnalyzerProvider")
                convertedBuffer = buffer
            }
        } else {
            convertedBuffer = buffer
        }

        // 6. Set up results collector FIRST (before starting analyzer - per Apple's pattern)
        var finalText = ""
        var timedSegments: [ASRTimedSegment] = []
        let resultsTask = Task {
            DebugLogger.shared.debug("AppleSpeechAnalyzer: Results task started, waiting for results...", source: "AppleSpeechAnalyzerProvider")
            for try await case let result in freshTranscriber.results {
                let text = String(result.text.characters)
                DebugLogger.shared.debug("AppleSpeechAnalyzer: Got result - isFinal: \(result.isFinal), characters: \(text.count)", source: "AppleSpeechAnalyzerProvider")
                if result.isFinal {
                    // ACCUMULATE results (per Apple's pattern) - don't break!
                    if !finalText.isEmpty && !text.isEmpty {
                        finalText += " "
                    }
                    finalText += text
                    for run in result.text.runs {
                        guard let range = run.audioTimeRange else { continue }
                        timedSegments.append(ASRTimedSegment(
                            text: String(result.text[run.range].characters),
                            start: range.start.seconds,
                            end: CMTimeRangeGetEnd(range).seconds
                        ))
                    }
                }
                // Continue iterating until stream ends (after finalizeAndFinish)
            }
            DebugLogger.shared.debug("AppleSpeechAnalyzer: Results iteration complete, characters: \(finalText.count)", source: "AppleSpeechAnalyzerProvider")
        }

        // 7. Start the analyzer (this kicks off processing)
        DebugLogger.shared.debug("AppleSpeechAnalyzer: Starting analyzer...", source: "AppleSpeechAnalyzerProvider")
        try await analyzer.start(inputSequence: inputStream)
        DebugLogger.shared.debug("AppleSpeechAnalyzer: Analyzer started", source: "AppleSpeechAnalyzerProvider")

        // 8. Feed audio and signal end of input
        let input = AnalyzerInput(buffer: convertedBuffer)
        inputContinuation.yield(input)
        inputContinuation.finish()
        DebugLogger.shared.debug("AppleSpeechAnalyzer: Audio fed and input finished", source: "AppleSpeechAnalyzerProvider")

        // 9. Finalize - this tells the analyzer to process remaining audio and complete the results stream
        var recognitionError: Error?
        do {
            try await analyzer.finalizeAndFinishThroughEndOfInput()
            DebugLogger.shared.debug("AppleSpeechAnalyzer: Analyzer finalized", source: "AppleSpeechAnalyzerProvider")
        } catch {
            recognitionError = error
            DebugLogger.shared.warning("Analyzer finalize error: \(DiagnosticMetadata.error(error))", source: "AppleSpeechAnalyzerProvider")
        }

        // 10. Now wait for results task to complete (it will finish once stream closes)
        do {
            try await resultsTask.value
        } catch {
            recognitionError = recognitionError ?? error
            DebugLogger.shared.warning("Speech recognition error: \(DiagnosticMetadata.error(error))", source: "AppleSpeechAnalyzerProvider")
        }
        if finalText.isEmpty, let recognitionError, !Self.isCancellation(recognitionError) {
            throw recognitionError
        }

        DebugLogger.shared.debug("AppleSpeechAnalyzer: Transcription complete - characters: \(finalText.count)", source: "AppleSpeechAnalyzerProvider")
        return ASRTranscriptionResult(text: finalText, confidence: 1.0, timedSegments: timedSegments)
    }

    // MARK: - Helpers

    private func selectedSpeechLocale() -> Locale {
        let sourceID = SpokenLanguageResolver.sourceLanguage().id
        let identifier = VoiceEngineLanguageCatalog.preferredAppleSpeechAnalyzerLocale(
            forLanguageID: sourceID
        )
        return Locale(identifier: identifier)
    }

    private func preparedLocaleDoesNotMatchISpeak() -> Bool {
        guard let prepared = self.preparedLocale else { return false }
        let preparedPrefix = VoiceEngineLanguageCatalog.languagePrefix(
            self.normalizedIdentifier(for: prepared)
        )
        let sourcePrefix = VoiceEngineLanguageCatalog.languagePrefix(
            SpokenLanguageResolver.sourceLanguage().id
        )
        return preparedPrefix != sourcePrefix
    }

    private func discardPreparedLocaleIfItDoesNotMatchISpeak() {
        guard self.preparedLocaleDoesNotMatchISpeak() else { return }
        self.isReady = false
        self.preparedLocale = nil
        self.analyzerFormat = nil
        self.converter = nil
    }

    private func resolveSupportedLocale(from supportedLocales: [Locale]) throws -> Locale {
        let languageID = SpokenLanguageResolver.sourceLanguage().id
        let preferredID = self.normalizedIdentifier(for: self.selectedSpeechLocale())
        let supportedIDs = supportedLocales.map { self.normalizedIdentifier(for: $0) }
        guard let resolvedID = VoiceEngineLanguageCatalog.resolveAppleSpeechAnalyzerLocale(
            preferredIdentifier: preferredID,
            languageID: languageID,
            supportedIdentifiers: supportedIDs
        ) else {
            let name = TranslationLanguageCatalog.language(id: languageID)?.displayName ?? languageID
            throw NSError(
                domain: "AppleSpeechAnalyzerProvider",
                code: 1,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Speech Analyzer does not include \(name) on this Mac. Use Whisper or Apple Speech.",
                ]
            )
        }
        return supportedLocales.first {
            self.normalizedIdentifier(for: $0).caseInsensitiveCompare(resolvedID) == .orderedSame
        } ?? Locale(identifier: resolvedID)
    }

    private func persistResolvedLocaleIfNeeded(_ localeID: String) {
        let current = VoiceEngineLanguageCatalog.normalizeLocaleID(
            SettingsStore.shared.selectedAppleSpeechLocaleIdentifier
        )
        guard current.caseInsensitiveCompare(localeID) != .orderedSame else { return }
        SettingsStore.shared.selectedAppleSpeechLocaleIdentifier = localeID
    }

    private func localeIsInstalled(_ localeID: String, in installedLocales: [Locale]) -> Bool {
        installedLocales.contains {
            self.normalizedIdentifier(for: $0).caseInsensitiveCompare(localeID) == .orderedSame
        }
    }

    private func ensureStreamingSession() async throws {
        let locale = self.preparedLocale ?? self.selectedSpeechLocale()
        let localeID = self.normalizedIdentifier(for: locale)
        if self.streamingAnalyzer != nil,
           self.streamingLocaleID == localeID,
           self.streamingResultsAreOpen()
        {
            return
        }
        await self.resetStreamingSession()
        guard self.isReady else {
            throw NSError(
                domain: "AppleSpeechAnalyzerProvider",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Speech Analyzer not ready"]
            )
        }
        let transcriber = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [.volatileResults],
            attributeOptions: [.audioTimeRange]
        )
        let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        await self.applyGlossaryContext(to: analyzer)
        self.streamingContinuation = continuation
        self.streamingAnalyzer = analyzer
        self.streamingLocaleID = localeID
        let epoch = self.streamingEpoch
        self.streamingLock.lock()
        self.streamingResultsOpen = true
        self.streamingLock.unlock()
        self.streamingResultsTask = Task {
            defer { self.markStreamingResultsClosed(epoch) }
            do {
                for try await result in transcriber.results {
                    let text = String(result.text.characters)
                    self.noteStreamingResult(text, isFinal: result.isFinal, epoch: epoch)
                }
            } catch {
                self.noteStreamingFailure(error, epoch: epoch)
            }
        }
        do {
            try await analyzer.start(inputSequence: stream)
        } catch {
            await self.resetStreamingSession()
            throw error
        }
    }

    /// Final segments accumulate. A volatile result is the unstable tail, or
    /// the whole hypothesis when it already starts with the committed text.
    private func noteStreamingResult(_ text: String, isFinal: Bool, epoch: UInt64) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        self.streamingLock.lock()
        defer { self.streamingLock.unlock() }
        guard epoch == self.streamingEpoch else { return }
        if isFinal {
            if !trimmed.isEmpty {
                self.streamingCommitted = Self.joiningCaption(self.streamingCommitted, trimmed)
            }
            self.streamingVolatile = ""
        } else if !trimmed.isEmpty {
            self.streamingVolatile = trimmed
        }
        self.streamingText = Self.joiningCaption(self.streamingCommitted, self.streamingVolatile)
        self.streamingResultGeneration += 1
    }

    private func noteStreamingFailure(_ error: Error, epoch: UInt64) {
        self.streamingLock.lock()
        defer { self.streamingLock.unlock() }
        guard epoch == self.streamingEpoch else { return }
        self.streamingFailure = error
        self.streamingResultGeneration += 1
    }

    private func markStreamingResultsClosed(_ epoch: UInt64) {
        self.streamingLock.lock()
        defer { self.streamingLock.unlock() }
        guard epoch == self.streamingEpoch else { return }
        self.streamingResultsOpen = false
    }

    private func streamingResultsAreOpen() -> Bool {
        self.streamingLock.lock()
        defer { self.streamingLock.unlock() }
        return self.streamingResultsOpen
    }

    private func streamingGeneration() -> Int {
        self.streamingLock.lock()
        defer { self.streamingLock.unlock() }
        return self.streamingResultGeneration
    }

    private func streamingSnapshot() -> (text: String, failure: Error?) {
        self.streamingLock.lock()
        defer { self.streamingLock.unlock() }
        return (self.streamingText, self.streamingFailure)
    }

    /// One short wait after new audio. A quiet tick returns the text already held.
    private func waitForStreamingResult(after generation: Int) async {
        let deadline = Date().addingTimeInterval(0.12)
        while Date() < deadline {
            if self.streamingGeneration() != generation { return }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    private static func joiningCaption(_ committed: String, _ next: String) -> String {
        if next.isEmpty { return committed }
        if committed.isEmpty { return next }
        if next == committed || next.hasPrefix(committed) { return next }
        return RecognizedSegmentJoin.join(committed, next)
    }

    private func convertedBuffer(from samples: [Float]) -> AVAudioPCMBuffer? {
        guard let buffer = self.createPCMBuffer(from: samples) else { return nil }
        guard let analyzerFormat = self.analyzerFormat, let converter = self.converter else {
            return buffer
        }
        return (try? converter.convertBuffer(buffer, to: analyzerFormat)) ?? buffer
    }

    private func applyGlossaryContext(to analyzer: SpeechAnalyzer) async {
        let phrases = await MainActor.run {
            TranslationGlossary.protectedTerms().prefix(100).map { String($0) }
        }
        guard !phrases.isEmpty else { return }
        let context = AnalysisContext()
        context.contextualStrings = [.general: phrases]
        do {
            try await analyzer.setContext(context)
        } catch {
            DebugLogger.shared.warning(
                "Speech Analyzer context: \(DiagnosticMetadata.error(error))",
                source: "AppleSpeechAnalyzerProvider"
            )
        }
    }

    private static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        let nsError = error as NSError
        return nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled
    }

    private func normalizedIdentifier(for locale: Locale) -> String {
        let bcp47 = locale.identifier(.bcp47).replacingOccurrences(of: "_", with: "-")
        if !bcp47.isEmpty {
            return VoiceEngineLanguageCatalog.normalizeLocaleID(bcp47)
        }
        return VoiceEngineLanguageCatalog.normalizeLocaleID(locale.identifier)
    }

    /// Converts raw [Float] samples (16kHz mono) to AVAudioPCMBuffer
    private func createPCMBuffer(from samples: [Float]) -> AVAudioPCMBuffer? {
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16_000,
            channels: 1,
            interleaved: false
        ) else {
            return nil
        }

        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: AVAudioFrameCount(samples.count)
        ) else {
            return nil
        }

        buffer.frameLength = AVAudioFrameCount(samples.count)

        guard let channelData = buffer.floatChannelData else { return nil }

        samples.withUnsafeBufferPointer { samplePtr in
            guard let baseAddress = samplePtr.baseAddress else { return }
            channelData[0].update(from: baseAddress, count: samples.count)
        }

        return buffer
    }
}

// MARK: - Buffer Converter (from Apple's sample)

@available(macOS 26.0, *)
private class BufferConverter {
    enum Error: Swift.Error {
        case failedToCreateConverter
        case failedToCreateConversionBuffer
        case conversionFailed(NSError?)
    }

    private var converter: AVAudioConverter?

    func convertBuffer(_ buffer: AVAudioPCMBuffer, to format: AVAudioFormat) throws -> AVAudioPCMBuffer {
        let inputFormat = buffer.format
        guard inputFormat != format else {
            return buffer
        }

        if converter == nil || converter?.outputFormat != format {
            converter = AVAudioConverter(from: inputFormat, to: format)
            converter?.primeMethod = .none
        }

        guard let converter else {
            throw Error.failedToCreateConverter
        }

        let sampleRateRatio = converter.outputFormat.sampleRate / converter.inputFormat.sampleRate
        let scaledInputFrameLength = Double(buffer.frameLength) * sampleRateRatio
        let frameCapacity = AVAudioFrameCount(scaledInputFrameLength.rounded(.up))

        guard let conversionBuffer = AVAudioPCMBuffer(
            pcmFormat: converter.outputFormat,
            frameCapacity: frameCapacity
        ) else {
            throw Error.failedToCreateConversionBuffer
        }

        var nsError: NSError?
        var bufferProcessed = false

        let status = converter.convert(to: conversionBuffer, error: &nsError) { _, inputStatusPointer in
            defer { bufferProcessed = true }
            inputStatusPointer.pointee = bufferProcessed ? .noDataNow : .haveData
            return bufferProcessed ? nil : buffer
        }

        guard status != .error else {
            throw Error.conversionFailed(nsError)
        }

        return conversionBuffer
    }
}
