import XCTest
@testable import ConnectingCaptions_Debug

final class LiveAudioRetentionTests: XCTestCase {
    func testCaptureTimelinePreservesRealPauseAcrossSyntheticResumeWall() throws {
        var timeline = CaptureAudioTimeline()
        timeline.append(start: 0, count: 16_000, hostTime: LiveTranslationHostClock.ticks(forSeconds: 100))
        timeline.append(start: 40_000, count: 16_000, hostTime: LiveTranslationHostClock.ticks(forSeconds: 110))
        XCTAssertNil(timeline.seconds(at: 20_000), "Synthetic silence is not a microphone timestamp")
        XCTAssertEqual(try XCTUnwrap(timeline.seconds(at: 40_000)), 10, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(timeline.seconds(at: 56_000, isEnd: true)), 11, accuracy: 0.001)
        timeline.trim(before: 40_000)
        XCTAssertNil(timeline.seconds(at: 0))
        XCTAssertEqual(try XCTUnwrap(timeline.seconds(at: 40_000)), 10, accuracy: 0.001)
    }

    func testRecognizerTimingMapsBackAcrossRemovedSilence() throws {
        let prepared = PauseIntervalAudio.Prepared(
            samples: [], isPauseOnly: false, sourceRanges: [0..<16_000, 48_000..<64_000]
        )
        var timeline = CaptureAudioTimeline()
        timeline.append(start: 0, count: 64_000, hostTime: LiveTranslationHostClock.ticks(forSeconds: 100))
        let mapped = timeline.map([
            ASRTimedSegment(text: "one", start: 0, end: 1),
            ASRTimedSegment(text: "two", start: 1, end: 2),
        ], sourceStart: 0, removedSilence: prepared)
        XCTAssertEqual(mapped, [
            ASRTimedSegment(text: "one", start: 0, end: 1),
            ASRTimedSegment(text: "two", start: 3, end: 4),
        ])
        XCTAssertTrue(timeline.map([ASRTimedSegment(text: "outside", start: 3, end: 4)], sourceStart: 0, removedSilence: prepared).isEmpty)
    }

    func testSpeechTimelineUsesCompleteSegmentsAndAcceptsRecognitionCorrections() {
        var timeline = CaptionSpeechTimeline()
        timeline.ingest([
            ASRTimedSegment(text: "hello", start: 2, end: 2.5),
            ASRTimedSegment(text: "world", start: 2.6, end: 3),
        ])
        XCTAssertEqual(timeline.timing(for: "Hello, world!"), CaptionSpeechTiming(start: 2, end: 3))
        XCTAssertNil(timeline.timing(for: "hell"), "A partial word has no invented speech range")
        timeline.ingest([ASRTimedSegment(text: "everyone", start: 2.6, end: 3.2)])
        XCTAssertNil(timeline.timing(for: "hello world"))
        XCTAssertEqual(timeline.timing(for: "hello everyone"), CaptionSpeechTiming(start: 2, end: 3.2))
    }

    func testSpeechTimelineFindsAWholeWordBeforeALaterSubstring() {
        var timeline = CaptionSpeechTimeline()
        timeline.ingest([
            ASRTimedSegment(text: "the", start: 1, end: 2),
            ASRTimedSegment(text: "other", start: 3, end: 4),
        ])
        XCTAssertEqual(timeline.timing(for: "the"), CaptionSpeechTiming(start: 1, end: 2))
    }

    func testRingBufferDropsSamplesPastCapAndKeepsLogicalIndices() {
        let buffer = ThreadSafeAudioBuffer(maximumRetainedSamples: 8)
        buffer.append([0, 1, 2, 3, 4, 5, 6, 7, 8, 9])

        XCTAssertEqual(buffer.count, 10)
        XCTAssertEqual(buffer.logicalStart, 2)
        XCTAssertEqual(buffer.retainedCount, 8)
        XCTAssertEqual(buffer.getRetained(), [2, 3, 4, 5, 6, 7, 8, 9])
        XCTAssertEqual(buffer.getRange(startingAt: 0, count: 2), [])
        XCTAssertEqual(buffer.getRange(startingAt: 2, count: 3), [2, 3, 4])
        XCTAssertEqual(buffer.getPrefix(4), [2, 3, 4, 5])
        XCTAssertEqual(buffer.getAll(), buffer.getRetained())
    }

    func testDropSamplesBeforeAdvancesLogicalStart() {
        let buffer = ThreadSafeAudioBuffer(maximumRetainedSamples: 16)
        buffer.append(Array(0..<10).map(Float.init))
        buffer.dropSamples(before: 6)

        XCTAssertEqual(buffer.logicalStart, 6)
        XCTAssertEqual(buffer.getRetained(), [6, 7, 8, 9])
        XCTAssertEqual(buffer.getRange(startingAt: 6, count: 2), [6, 7])
        XCTAssertEqual(buffer.getRange(startingAt: 4, count: 2), [])
    }

    func testIncrementalPreviewCopiesDeltaOnly() {
        let tenMinutes = 10 * 60 * 16_000
        let retained = Array(repeating: Float(1), count: LiveAudioRetention.maximumRetainedSamples)
        let deltaStart = tenMinutes - 16_000
        let preview = StreamingTranscriptStitcher.previewChunk(
            logicalSampleCount: tenMinutes,
            logicalStart: tenMinutes - retained.count,
            incrementalDeltaStart: deltaStart,
            retained: retained
        )

        XCTAssertEqual(preview.kind, .incrementalDelta)
        XCTAssertEqual(preview.samples.count, 16_000)
        XCTAssertLessThan(preview.samples.count, tenMinutes)
    }

    func testIncrementalPreviewCanCopyDeltaFromTheRingWithoutTheFullWindow() {
        let buffer = ThreadSafeAudioBuffer(maximumRetainedSamples: 32)
        buffer.append(Array(0..<32).map(Float.init))
        let delta = buffer.getRange(startingAt: 24, count: 8)
        XCTAssertEqual(delta, Array(24..<32).map(Float.init))
        XCTAssertEqual(delta.count, 8)
        XCTAssertEqual(buffer.retainedCount, 32)
    }

    func testWindowedPreviewCopiesLastThirtySecondsNeverFullPrefix() {
        let tenMinutes = 10 * 60 * 16_000
        let retained = Array(repeating: Float(0.5), count: LiveAudioRetention.maximumRetainedSamples)
        let preview = StreamingTranscriptStitcher.previewChunk(
            logicalSampleCount: tenMinutes,
            logicalStart: tenMinutes - retained.count,
            incrementalDeltaStart: nil,
            retained: retained
        )

        XCTAssertEqual(preview.kind, .retainedWindow)
        XCTAssertEqual(preview.samples.count, LiveAudioRetention.maximumRetainedSamples)
        XCTAssertLessThan(preview.samples.count, tenMinutes)
    }

    func testLiveTranscriptBoundKeepsTheNewestSentences() {
        let older = (1...80).map { "This is committed sentence number \($0) of the talk." }.joined(separator: " ")
        let newest = "And this is the clause we are speaking now."
        let bounded = StreamingTranscriptStitcher.boundLiveTranscript(older + " " + newest)
        XCTAssertLessThanOrEqual(bounded.count, StreamingTranscriptStitcher.maximumLiveCharacters)
        XCTAssertTrue(bounded.hasSuffix(newest))
        XCTAssertFalse(bounded.contains("sentence number 1 of the talk"))
        XCTAssertEqual(StreamingTranscriptStitcher.boundLiveTranscript("Short."), "Short.")
    }

    func testWindowStitchRewritesOverlapWithoutDuplicatingSentences() {
        let committed = "Welcome everyone. Today we will cover memory."
        let incoming = "Today we will cover memory. Please silence your phones."
        let stitched = StreamingTranscriptStitcher.stitch(committed: committed, incoming: incoming)

        XCTAssertEqual(stitched, "Welcome everyone. Today we will cover memory. Please silence your phones.")
        XCTAssertEqual(stitched.components(separatedBy: "Today we will cover memory.").count - 1, 1)
    }

    /// Voice log, 2026-09-19: the full ring re-decoded "what it on me" as
    /// "what it all means", the exact overlap failed, and the whole half
    /// minute was appended again on every tick.
    func testFullRingRedecodeWithARevisedWordDoesNotRepeatTheWindow() {
        let committed = "I just woke up from my dream But you and I had to say goodbye And I don't know what it on me."
        let incoming = "I just woke up from my dream But you and I had to say goodbye And I don't know what it all means. But since I"
        let stitched = StreamingTranscriptStitcher.stitch(committed: committed, incoming: incoming)

        XCTAssertEqual(
            stitched,
            "I just woke up from my dream But you and I had to say goodbye And I don't know what it all means. But since I"
        )
        XCTAssertEqual(stitched.components(separatedBy: "I just woke up").count - 1, 1)

        // The window slid: its first words are gone from the decode and the
        // opening word is different. Only the fresh tail may be appended.
        let slid = "Well, you and I had to say goodbye. And I don't know what it all means. But since I survived, I realized"
        let next = StreamingTranscriptStitcher.stitch(committed: stitched, incoming: slid)
        XCTAssertEqual(
            next,
            "I just woke up from my dream But you and I had to say goodbye. And I don't know what it all means. But since I survived, I realized"
        )
        XCTAssertEqual(next.components(separatedBy: "say goodbye").count - 1, 1)
    }

    /// Voice log, 16:19: every tick is a fresh decode of the whole ring and
    /// the words drift ("I feel the fine" → "I really fine"). A one-word
    /// exact overlap ("I") used to duplicate the whole block.
    func testDriftingFullDecodesOnlyGrowAtTheTail() {
        let ticks = [
            "I feel fine.",
            "I feel the fine about it.",
            "I feel the fine about it.  Clear.",
            "I really fine about it.  Clear.",
            "I really fine about it.  Cle.  Exactly.",
            "I really fine about it.  Cle.  something.  Exactly.  It was no big.  I mean, sure, I wasted a bit.",
            "I really fine about it.  Cle.  something.  Exactly.  It was no big.  I mean, sure, I wasted a bit of time shaving my legs.  Never mind this one week later.  I",
            "I really fine about it.  Cle.  something.  Exactly.  It was no big.  I mean, sure, I wasted a bit of time shaving my legs.  Never mind this one week later.  I'm a cute gallery.",
        ]
        var committed = ""
        var previousCount = 0
        for tick in ticks {
            committed = StreamingTranscriptStitcher.stitch(committed: committed, incoming: tick)
            XCTAssertLessThanOrEqual(committed.count, previousCount + tick.count + 1, tick)
            XCTAssertLessThanOrEqual(committed.components(separatedBy: "fine about it").count - 1, 1, committed)
            previousCount = committed.count
        }
        XCTAssertTrue(committed.hasSuffix("shaving my legs. Never mind this one week later. I'm a cute gallery."), committed)
        XCTAssertFalse(committed.contains("a bit. of time"), committed)
    }

    /// Once the decoder hears the sentence end it re-spells "meaningful, but"
    /// as "meaningful. But". The shared run takes the fresh spelling so the
    /// sentence can split while talking.
    func testSharedRunTakesTheFreshDecodePunctuation() {
        let stitched = StreamingTranscriptStitcher.stitch(
            committed: "It is quietly destroying your ability to do anything meaningful, but what if I told you",
            incoming: "It is quietly destroying your ability to do anything meaningful. But what if I told you that the same"
        )
        XCTAssertEqual(
            stitched,
            "It is quietly destroying your ability to do anything meaningful. But what if I told you that the same"
        )
    }

    func testUnrelatedWindowStillAppends() {
        let stitched = StreamingTranscriptStitcher.stitch(
            committed: "Welcome everyone to the talk.",
            incoming: "Let us begin with memory."
        )
        XCTAssertEqual(stitched, "Welcome everyone to the talk. Let us begin with memory.")
    }

    func testUnspacedScriptAlignsOnSharedCharacters() {
        let committed = "今日はモデルを学習しました。次に適用しま"
        let incoming = "モデルを学習しました。次に適用しました。そして出荷しました"
        let stitched = StreamingTranscriptStitcher.stitch(committed: committed, incoming: incoming)
        XCTAssertEqual(stitched, "今日はモデルを学習しました。次に適用しました。そして出荷しました")
    }

    func testWhisperReleaseMemoryLeavesDiskCacheUntouched() async {
        let provider = WhisperProvider()
        let existedOnDisk = provider.modelsExistOnDisk()
        await provider.releaseMemory()
        XCTAssertEqual(provider.modelsExistOnDisk(), existedOnDisk)
        XCTAssertFalse(provider.isReady)
    }

    #if arch(arm64)
    func testFluidAudioReleaseMemoryLeavesDiskCacheUntouched() async {
        let provider = FluidAudioProvider()
        let existedOnDisk = provider.modelsExistOnDisk()
        await provider.releaseMemory()
        XCTAssertEqual(provider.modelsExistOnDisk(), existedOnDisk)
        XCTAssertFalse(provider.isReady)
    }
    #endif

    func testCaptureHandoffPreservesOrderHostTimeAndWrap() {
        let handoff = CapturePacketHandoff(frameCapacity: 8, descriptorCapacity: 4)
        XCTAssertTrue(self.write([1, 2, 3, 4, 5, 6], to: handoff, hostTime: 11, sampleTime: 100))
        let first = handoff.pop()
        XCTAssertEqual(first?.frames, [1, 2, 3, 4, 5, 6])
        XCTAssertEqual(first?.inputHostTime, 11)
        XCTAssertEqual(first?.inputSampleTime, 100)

        XCTAssertTrue(self.write([7, 8, 9, 10], to: handoff, hostTime: 22, sampleTime: 200))
        let second = handoff.pop()
        XCTAssertEqual(second?.frames, [7, 8, 9, 10])
        XCTAssertEqual(second?.inputHostTime, 22)
        XCTAssertEqual(second?.inputSampleTime, 200)
        XCTAssertNil(handoff.pop())
    }

    func testCaptureHandoffRejectsWhenFullWithoutLosingQueuedPCM() {
        let handoff = CapturePacketHandoff(frameCapacity: 4, descriptorCapacity: 2)
        XCTAssertTrue(self.write([1, 2, 3], to: handoff, hostTime: 1, sampleTime: 1))
        XCTAssertFalse(self.write([4, 5], to: handoff, hostTime: 2, sampleTime: 2))
        XCTAssertEqual(handoff.droppedPacketCount, 1)
        XCTAssertTrue(handoff.consumeDropNotice())
        XCTAssertFalse(handoff.consumeDropNotice())
        XCTAssertEqual(handoff.pop()?.frames, [1, 2, 3])
        XCTAssertTrue(self.write([4, 5], to: handoff, hostTime: 3, sampleTime: 3))
        XCTAssertEqual(handoff.pop()?.frames, [4, 5])
    }

    @MainActor
    func testIncrementalPCMIsConsumedExactlyOnceIncludingEmptyFinalTail() {
        let service = ASRService()
        var accepted = 0
        var consumed: [Float] = []
        for tick in 0..<3 {
            service.audioBuffer.append(Array((tick * 16_000)..<((tick + 1) * 16_000)).map(Float.init))
            let preview = service.previewChunk(
                logicalSampleCount: service.audioBuffer.count,
                logicalStart: service.audioBuffer.logicalStart,
                incrementalDeltaStart: accepted
            )
            consumed.append(contentsOf: preview.samples)
            accepted = service.audioBuffer.count
            service.audioBuffer.dropSamples(before: accepted - LiveAudioRetention.incrementalOverlapSamples)
        }
        let final = service.previewChunk(
            logicalSampleCount: service.audioBuffer.count,
            logicalStart: service.audioBuffer.logicalStart,
            incrementalDeltaStart: accepted
        )
        XCTAssertEqual(consumed, Array(0..<48_000).map(Float.init))
        XCTAssertEqual(final.kind, .incrementalDelta)
        XCTAssertTrue(final.samples.isEmpty, "Retained overlap must not become new PCM on Stop")
    }

    @MainActor
    func testQuarantineReplacesAllStatefulCachedProviders() {
        let service = ASRService()
        let flash = service.getParakeetRealtimeProvider()
        let nemotron = service.getNemotronProvider(mode: .streaming)
        let parakeet = service.getFluidAudioProvider()
        service.quarantineTranscriptionProvider()
        XCTAssertFalse(service.getParakeetRealtimeProvider() === flash)
        XCTAssertFalse(service.getNemotronProvider(mode: .streaming) === nemotron)
        XCTAssertFalse(service.getFluidAudioProvider() === parakeet)
    }

    func testFinalDecodeUsesProviderModeAndResetDropsPreviousListen() async throws {
        let windowed = SessionTestProvider(mode: .trailingWindow)
        let incremental = SessionTestProvider(mode: .incrementalDelta)
        let full = try await windowed.transcribeStoppedAudio([1, 2], totalSampleCount: 2)
        XCTAssertEqual(full.text, "full")
        _ = try await incremental.transcribeStreamingDelta([1, 2], totalSampleCount: 2)
        await incremental.resetStreamingSession()
        _ = try await incremental.transcribeStreamingDelta([3], totalSampleCount: 1)
        let delta = try await incremental.transcribeStoppedAudio([], totalSampleCount: 1)
        XCTAssertEqual(delta.text, "delta")
        XCTAssertEqual(incremental.samples, [3], "A new Listen cannot retain old audio")
    }

    func testDiscardedRecordingIsRemovedWhilePendingSavesStayProtected() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("audio-discard-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = DictationAudioHistoryStore(audioDirectory: directory)
        let metadata = try store.save(
            snapshot: DictationAudioSnapshot(samples: [0.25, -0.25], sampleRate: 16_000, channels: 1),
            entryID: UUID(), timestamp: Date(), model: "test"
        )
        let url = directory.appendingPathComponent(metadata.fileName)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        XCTAssertEqual(store.deleteUnreferencedAudioFiles(referencedFileNames: []).fileCount, 0)
        store.discardPendingAudio(fileName: metadata.fileName)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    private func write(
        _ samples: [Float],
        to handoff: CapturePacketHandoff,
        hostTime: UInt64,
        sampleTime: Int64
    ) -> Bool {
        samples.withUnsafeBufferPointer { buffer in
            guard let base = buffer.baseAddress else { return false }
            return handoff.write(
                samples: base,
                frameCount: samples.count,
                sampleRate: 16_000,
                inputHostTime: hostTime,
                inputSampleTime: sampleTime
            )
        }
    }
}

private final class SessionTestProvider: TranscriptionProvider {
    let name = "Session test"
    let isAvailable = true
    let isReady = true
    let streamingPreviewMode: StreamingPreviewMode
    var samples: [Float] = []
    var acceptedStreamingSampleCount: Int? { self.samples.count }

    init(mode: StreamingPreviewMode) { self.streamingPreviewMode = mode }
    func prepare(progressHandler: ((ModelPreparationProgress) -> Void)?) async throws {}
    func transcribe(_ samples: [Float]) async throws -> ASRTranscriptionResult {
        ASRTranscriptionResult(text: "full")
    }
    func transcribeStreamingDelta(_ newSamples: [Float], totalSampleCount: Int) async throws -> ASRTranscriptionResult {
        self.samples.append(contentsOf: newSamples)
        return ASRTranscriptionResult(text: "preview")
    }
    func transcribeFinalDelta(_ newSamples: [Float], totalSampleCount: Int) async throws -> ASRTranscriptionResult {
        self.samples.append(contentsOf: newSamples)
        return ASRTranscriptionResult(text: "delta")
    }
    func resetStreamingSession() async { self.samples.removeAll() }
}
