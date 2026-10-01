@testable import ConnectingCaptions_Debug
import XCTest

final class PauseIntervalAudioTests: XCTestCase {
    private let floor: Float = 0.006

    func testRoomNoiseIsNotDecoded() {
        let prepared = PauseIntervalAudio.preparingForDecode(
            self.tone(2.0, amplitude: 0.006),
            floorRMS: self.floor
        )
        XCTAssertTrue(prepared.isPauseOnly)
        XCTAssertTrue(prepared.samples.isEmpty)
    }

    func testAColdFloorDoesNotTreatRoomNoiseAsSpeech() {
        let prepared = PauseIntervalAudio.preparingForDecode(
            self.tone(1.5, amplitude: 0.006),
            floorRMS: nil
        )
        XCTAssertTrue(prepared.isPauseOnly)
    }

    func testTrailingPauseIsCutBackToAShortPad() {
        let speech = self.tone(1.0, amplitude: 0.05)
        let pause = self.tone(2.0, amplitude: 0.001)
        let prepared = PauseIntervalAudio.preparingForDecode(speech + pause, floorRMS: self.floor)
        let pad = self.samples(PauseIntervalAudio.trailingPadSeconds)
        XCTAssertFalse(prepared.isPauseOnly)
        XCTAssertEqual(prepared.samples.count, speech.count + pad)
        XCTAssertEqual(Array(prepared.samples.prefix(speech.count)), speech)
        XCTAssertEqual(prepared.samples.last, 0.001)
    }

    func testAShortTailAfterSpeechStays() {
        let speech = self.tone(1.0, amplitude: 0.05)
        let tail = self.tone(0.2, amplitude: 0.001)
        let prepared = PauseIntervalAudio.preparingForDecode(speech + tail, floorRMS: self.floor)
        XCTAssertEqual(prepared.samples.count, speech.count + tail.count)
    }

    func testLeadingSilenceWallIsCut() {
        let wall = self.tone(1.5, amplitude: 0)
        let speech = self.tone(1.0, amplitude: 0.05)
        let prepared = PauseIntervalAudio.preparingForDecode(wall + speech, floorRMS: self.floor)
        let pad = self.samples(PauseIntervalAudio.leadingPadSeconds)
        XCTAssertEqual(prepared.samples.count, pad + speech.count)
        XCTAssertEqual(Array(prepared.samples.suffix(speech.count)), speech)
    }

    func testALongGapBetweenSentencesShrinks() {
        let speech = self.tone(1.0, amplitude: 0.05)
        let gap = self.tone(2.0, amplitude: 0.001)
        let prepared = PauseIntervalAudio.preparingForDecode(
            speech + gap + speech,
            floorRMS: self.floor
        )
        let pad = self.samples(PauseIntervalAudio.internalPadSeconds)
        XCTAssertEqual(prepared.samples.count, speech.count * 2 + pad)
        XCTAssertEqual(Array(prepared.samples.prefix(speech.count)), speech)
        XCTAssertEqual(Array(prepared.samples.suffix(speech.count)), speech)
    }

    func testALongGapKeepsHalfASecondForThePeriod() {
        XCTAssertEqual(PauseIntervalAudio.internalPadSeconds, 0.5)
    }

    func testABreathBetweenSentencesStays() {
        let speech = self.tone(1.0, amplitude: 0.05)
        let breath = self.tone(0.4, amplitude: 0.001)
        let prepared = PauseIntervalAudio.preparingForDecode(
            speech + breath + speech,
            floorRMS: self.floor
        )
        XCTAssertEqual(prepared.samples.count, speech.count * 2 + breath.count)
    }

    func testAnIsolatedPopInAPauseIsDropped() {
        let quiet = self.tone(1.0, amplitude: 0.001)
        let pop = self.tone(0.04, amplitude: 0.05)
        let prepared = PauseIntervalAudio.preparingForDecode(
            quiet + pop + quiet,
            floorRMS: self.floor
        )
        XCTAssertTrue(prepared.isPauseOnly)
        XCTAssertTrue(prepared.samples.isEmpty)
    }

    func testMinimumLengthBorrowsOnlyEnoughQuietAudio() {
        let speech = self.tone(0.2, amplitude: 0.05)
        let pause = self.tone(3.0, amplitude: 0.001)
        let prepared = PauseIntervalAudio.preparingForDecode(
            speech + pause,
            floorRMS: self.floor,
            minimumSamples: 16_000
        )
        XCTAssertFalse(prepared.isPauseOnly)
        XCTAssertEqual(prepared.samples.count, 16_000)
        XCTAssertEqual(Array(prepared.samples.prefix(speech.count)), speech)
    }

    func testAShortDipKeepsTheSpeechRun() {
        var run = SustainedSpeechRun()
        XCTAssertNil(run.speechHostTime(voiced: true, samples: 640, hostTime: 10))
        XCTAssertNil(run.speechHostTime(voiced: false, samples: 640, hostTime: 11))
        XCTAssertEqual(run.speechHostTime(voiced: true, samples: 640, hostTime: 12), 10)
    }

    func testALongGapResetsTheSpeechRun() {
        var run = SustainedSpeechRun()
        XCTAssertNil(run.speechHostTime(voiced: true, samples: 640, hostTime: 10))
        XCTAssertNil(run.speechHostTime(voiced: false, samples: 2_400, hostTime: 11))
        XCTAssertNil(run.speechHostTime(voiced: true, samples: 640, hostTime: 20))
        XCTAssertEqual(run.speechHostTime(voiced: true, samples: 640, hostTime: 21), 20)
    }

    func testFixtureSpeechSurvivesAndTrailingNoiseIsCut() throws {
        let speech = try AudioFixtureLoader.load16kMonoFloatSamples(named: "dictation_fixture", ext: "wav")
        let floor: Float = 0.006
        let noise = [Float](repeating: 0.001, count: PauseIntervalAudio.defaultSampleRate * 3)
        let prepared = PauseIntervalAudio.preparingForDecode(speech + noise, floorRMS: floor)
        XCTAssertFalse(prepared.isPauseOnly)
        let pad = self.samples(PauseIntervalAudio.trailingPadSeconds)
        XCTAssertLessThanOrEqual(prepared.samples.count, speech.count + pad)
        XCTAssertLessThan(prepared.samples.count, speech.count + noise.count)
        self.assertSpeechRunsSurvive(speech, floorRMS: floor, inside: prepared.samples)
    }

    /// The floor cannot rise past `maximumFloorRMS` (0.015). This fixture is
    /// loud: almost every voiced frame still clears that bar. Frames between
    /// 0.012 and that cap are the soft edge. Do not raise the cap to hide them.
    func testMaximumFloorDropsOnlyTheSoftEdgeOfTheFixture() throws {
        let speech = try AudioFixtureLoader.load16kMonoFloatSamples(named: "dictation_fixture", ext: "wav")
        let laptop = self.voicedFrameCount(speech, floorRMS: 0.006)
        let capped = self.voicedFrameCount(speech, floorRMS: SpeechEnergyGate.maximumFloorRMS)
        XCTAssertLessThan(capped, laptop)
        XCTAssertGreaterThan(capped, 0)
        let prepared = PauseIntervalAudio.preparingForDecode(
            speech,
            floorRMS: SpeechEnergyGate.maximumFloorRMS
        )
        XCTAssertFalse(prepared.isPauseOnly)
        self.assertSpeechRunsSurvive(
            speech,
            floorRMS: SpeechEnergyGate.maximumFloorRMS,
            inside: prepared.samples
        )
    }

    func testAStreamingEngineKeepsTheFullWindow() {
        let speech = self.tone(1.0, amplitude: 0.05)
        let pause = self.tone(2.0, amplitude: 0.001)
        let chunk = speech + pause
        let prepared = PauseIntervalAudio.preparingForDecode(chunk, floorRMS: self.floor)
        let decoded = PauseIntervalAudio.samplesForDecode(
            chunk: chunk,
            prepared: prepared,
            keepsSampleCursor: true,
            warmUpTick: false
        )
        XCTAssertLessThan(prepared.samples.count, chunk.count)
        XCTAssertEqual(decoded, chunk)
    }

    func testATrailingWindowLeavesThePauseOutAfterWarmUp() {
        let speech = self.tone(1.0, amplitude: 0.05)
        let pause = self.tone(2.0, amplitude: 0.001)
        let chunk = speech + pause
        let prepared = PauseIntervalAudio.preparingForDecode(chunk, floorRMS: self.floor)
        let decoded = PauseIntervalAudio.samplesForDecode(
            chunk: chunk,
            prepared: prepared,
            keepsSampleCursor: false,
            warmUpTick: false
        )
        XCTAssertEqual(decoded, prepared.samples)
    }

    func testTheWarmUpTickKeepsTheFullWindow() {
        let speech = self.tone(1.0, amplitude: 0.05)
        let pause = self.tone(2.0, amplitude: 0.001)
        let chunk = speech + pause
        let prepared = PauseIntervalAudio.preparingForDecode(chunk, floorRMS: self.floor)
        let decoded = PauseIntervalAudio.samplesForDecode(
            chunk: chunk,
            prepared: prepared,
            keepsSampleCursor: false,
            warmUpTick: true
        )
        XCTAssertEqual(decoded, chunk)
    }

    func testANoiseBlipDoesNotReopenSpeech() {
        var run = SustainedSpeechRun()
        XCTAssertNil(run.speechHostTime(voiced: true, samples: 320, hostTime: 10))
        XCTAssertNil(run.speechHostTime(voiced: false, samples: 320, hostTime: 11))
        XCTAssertNil(run.speechHostTime(voiced: true, samples: 640, hostTime: 12))
    }

    func testSustainedSpeechReportsFromTheStartOfTheRun() {
        var run = SustainedSpeechRun()
        XCTAssertNil(run.speechHostTime(voiced: true, samples: 640, hostTime: 10))
        XCTAssertEqual(run.speechHostTime(voiced: true, samples: 640, hostTime: 20), 10)
        XCTAssertEqual(run.speechHostTime(voiced: true, samples: 640, hostTime: 30), 30)
        run.reset()
        XCTAssertNil(run.speechHostTime(voiced: true, samples: 640, hostTime: 40))
    }

    /// A 4096-frame tap at 48 kHz is about 1,365 samples at 16 kHz, longer than
    /// the minimum run on its own.
    func testOneFullTapPacketIsNotSustainedSpeech() {
        var run = SustainedSpeechRun()
        XCTAssertNil(run.speechHostTime(voiced: true, samples: 1_365, hostTime: 10))
        XCTAssertNil(run.speechHostTime(voiced: false, samples: 1_365, hostTime: 11))
        XCTAssertNil(run.speechHostTime(voiced: true, samples: 1_365, hostTime: 12))
        XCTAssertEqual(run.speechHostTime(voiced: true, samples: 1_365, hostTime: 13), 12)
    }

    private func voicedFrameCount(_ samples: [Float], floorRMS: Float) -> Int {
        self.voicedFrameRanges(samples, floorRMS: floorRMS).count
    }

    private func voicedFrameRanges(_ samples: [Float], floorRMS: Float) -> [Range<Int>] {
        var ranges: [Range<Int>] = []
        var index = 0
        while index < samples.count {
            let end = min(index + PauseIntervalAudio.frameSamples, samples.count)
            var squareSum = 0.0
            for sample in samples[index..<end] {
                squareSum += Double(sample) * Double(sample)
            }
            let rms = Float(sqrt(squareSum / Double(end - index)))
            if SpeechEnergyGate.isAboveSpeech(rms: rms, floorRMS: floorRMS) {
                ranges.append(index..<end)
            }
            index = end
        }
        return ranges
    }

    /// A pop shorter than a word is removed on purpose. A voiced run long
    /// enough to be speech has to come through in order.
    private func assertSpeechRunsSurvive(
        _ samples: [Float],
        floorRMS: Float,
        inside prepared: [Float]
    ) {
        let minimum = Int((PauseIntervalAudio.ignoredBurstSeconds * Double(PauseIntervalAudio.defaultSampleRate)).rounded())
        var cursor = 0
        for range in self.mergedRuns(self.voicedFrameRanges(samples, floorRMS: floorRMS)) where range.count >= minimum {
            let run = Array(samples[range])
            guard let found = self.index(of: run, in: prepared, from: cursor) else {
                XCTFail("speech run at \(range.lowerBound) was trimmed")
                return
            }
            cursor = found + run.count
        }
    }

    private func mergedRuns(_ ranges: [Range<Int>]) -> [Range<Int>] {
        var merged: [Range<Int>] = []
        for range in ranges {
            if let last = merged.indices.last, merged[last].upperBound == range.lowerBound {
                merged[last] = merged[last].lowerBound..<range.upperBound
            } else {
                merged.append(range)
            }
        }
        return merged
    }

    private func index(of needle: [Float], in haystack: [Float], from start: Int) -> Int? {
        let last = haystack.count - needle.count
        guard needle.isEmpty == false, start <= last else { return nil }
        var index = start
        while index <= last {
            var matches = true
            for offset in needle.indices where haystack[index + offset] != needle[offset] {
                matches = false
                break
            }
            if matches { return index }
            index += PauseIntervalAudio.frameSamples
        }
        return nil
    }

    private func tone(_ seconds: Double, amplitude: Float) -> [Float] {
        let count = Int((seconds * Double(PauseIntervalAudio.defaultSampleRate)).rounded())
        return [Float](repeating: amplitude, count: count)
    }

    private func samples(_ seconds: TimeInterval) -> Int {
        Int((seconds * Double(PauseIntervalAudio.defaultSampleRate)).rounded())
    }
}
