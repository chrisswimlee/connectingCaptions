import AVFoundation
@testable import ConnectingCaptions_Debug
import XCTest

final class AudioBufferConverterTests: XCTestCase {
    func testStereoDownmixIncludesRightChannel() throws {
        let buffer = try self.makeFloatBuffer(sampleRate: 16_000, channels: 2, frameCount: 16)
        self.fill(buffer, channel: 1, with: 1)

        let samples = try AudioBufferConverter.monoSamples(from: buffer, targetSampleRate: 16_000)

        XCTAssertEqual(samples.count, 16)
        self.assertAllSamples(samples, equalTo: 0.5)
    }

    func testStereoDownmixIncludesLeftChannel() throws {
        let buffer = try self.makeFloatBuffer(sampleRate: 16_000, channels: 2, frameCount: 16)
        self.fill(buffer, channel: 0, with: 1)

        let samples = try AudioBufferConverter.monoSamples(from: buffer, targetSampleRate: 16_000)

        XCTAssertEqual(samples.count, 16)
        self.assertAllSamples(samples, equalTo: 0.5)
    }

    func testStereoDownmixPreservesMatchingChannels() throws {
        let buffer = try self.makeFloatBuffer(sampleRate: 16_000, channels: 2, frameCount: 16)
        self.fill(buffer, channel: 0, with: 1)
        self.fill(buffer, channel: 1, with: 1)

        let samples = try AudioBufferConverter.monoSamples(from: buffer, targetSampleRate: 16_000)

        XCTAssertEqual(samples.count, 16)
        self.assertAllSamples(samples, equalTo: 1)
    }

    func testMonoFloatFastPathPreservesSamples() throws {
        let expected: [Float] = [0.25, -0.5, 0.75, -1]
        let buffer = try self.makeFloatBuffer(
            sampleRate: 16_000,
            channels: 1,
            frameCount: expected.count
        )
        let channelData = try XCTUnwrap(buffer.floatChannelData)
        for (index, sample) in expected.enumerated() {
            channelData[0][index] = sample
        }

        let samples = try AudioBufferConverter.monoSamples(from: buffer, targetSampleRate: 16_000)

        XCTAssertEqual(samples, expected)
    }

    func testStereoDownmixAndResampleIncludesRightChannel() throws {
        let buffer = try self.makeFloatBuffer(sampleRate: 48_000, channels: 2, frameCount: 480)
        self.fill(buffer, channel: 1, with: 1)

        let samples = try AudioBufferConverter.monoSamples(from: buffer, targetSampleRate: 16_000)

        XCTAssertEqual(samples.count, 160)
        let average = samples.reduce(0, +) / Float(samples.count)
        XCTAssertEqual(average, 0.5, accuracy: 0.01)
        XCTAssertGreaterThan(samples.map(abs).max() ?? 0, 0.4)
    }

    private func makeFloatBuffer(
        sampleRate: Double,
        channels: AVAudioChannelCount,
        frameCount: Int
    ) throws -> AVAudioPCMBuffer {
        let format = try XCTUnwrap(AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: channels,
            interleaved: false
        ))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: AVAudioFrameCount(frameCount)
        ))
        buffer.frameLength = AVAudioFrameCount(frameCount)
        return buffer
    }

    private func fill(_ buffer: AVAudioPCMBuffer, channel: Int, with value: Float) {
        guard let channelData = buffer.floatChannelData else {
            XCTFail("Expected Float32 channel data")
            return
        }
        for frame in 0..<Int(buffer.frameLength) {
            channelData[channel][frame] = value
        }
    }

    private func assertAllSamples(
        _ samples: [Float],
        equalTo expected: Float,
        accuracy: Float = 0.00_001
    ) {
        for sample in samples {
            XCTAssertEqual(sample, expected, accuracy: accuracy)
        }
    }
}


final class SpeechResamplingTests: XCTestCase {
    private func pipeline() -> AudioCapturePipeline {
        AudioCapturePipeline(audioBuffer: ThreadSafeAudioBuffer(), onAcceptedSamples: { _ in },
                             onFirstAudio: { _, _, _, _, _, _, _ in }, onLevel: { _ in },
                             onSpeechEnergy: { _, _ in }, onCaptureHealth: { _, _, _, _, _, _ in })
    }

    private func tone(frequency: Double, rate: Double, count: Int) -> [Float] {
        (0..<count).map { Float(sin(2 * Double.pi * frequency * Double($0) / rate)) }
    }

    private func rms(_ samples: ArraySlice<Float>) -> Float {
        sqrt(samples.reduce(0) { $0 + $1 * $1 } / Float(samples.count))
    }

    func test48kConversionRejects12kAliasAndPreservesSpeechBand() {
        let high = self.pipeline().resampleTo16kLocked(self.tone(frequency: 12_000, rate: 48_000, count: 48_000), sourceSampleRate: 48_000)
        let speech = self.pipeline().resampleTo16kLocked(self.tone(frequency: 1_000, rate: 48_000, count: 48_000), sourceSampleRate: 48_000)
        XCTAssertEqual(high.count, 16_000)
        XCTAssertLessThan(self.rms(high.dropFirst(100)), 0.001)
        XCTAssertEqual(self.rms(speech.dropFirst(100)), Float(1 / sqrt(2.0)), accuracy: 0.01)
    }

    func testPacketBoundariesPreservePhaseAndFilterHistoryAt44100() {
        let input = self.tone(frequency: 1_000, rate: 44_100, count: 44_100)
        let whole = self.pipeline().resampleTo16kLocked(input, sourceSampleRate: 44_100)
        let streaming = self.pipeline()
        var packets: [Float] = []
        for start in stride(from: 0, to: input.count, by: 137) {
            packets += streaming.resampleTo16kLocked(Array(input[start..<min(input.count, start + 137)]), sourceSampleRate: 44_100)
        }
        XCTAssertEqual(packets.count, whole.count)
        XCTAssertEqual(packets.count, 16_000)
        for (actual, expected) in zip(packets, whole) { XCTAssertEqual(actual, expected, accuracy: 0.00001) }
    }

    func testCommonHardwareRatesRejectAudioAboveOutputNyquist() {
        for rate in [44_100.0, 48_000.0, 96_000.0] {
            let output = self.pipeline().resampleTo16kLocked(
                self.tone(frequency: 8_500, rate: rate, count: Int(rate)), sourceSampleRate: rate
            )
            XCTAssertEqual(output.count, 16_000)
            XCTAssertLessThan(self.rms(output.dropFirst(100)), 0.005, "rate=\(rate)")
        }
    }

    func testRateChangeClearsFilterHistoryAnd16kRemainsUnchanged() {
        let stream = self.pipeline()
        _ = stream.resampleTo16kLocked(Array(repeating: 1, count: 4_800), sourceSampleRate: 48_000)
        let silence = stream.resampleTo16kLocked(Array(repeating: 0, count: 4_410), sourceSampleRate: 44_100)
        XCTAssertTrue(silence.allSatisfy { $0 == 0 })
        let native: [Float] = [0.1, -0.2, 0.3]
        XCTAssertEqual(stream.resampleTo16kLocked(native, sourceSampleRate: 16_000), native)
        XCTAssertTrue(stream.resampleTo16kLocked(native, sourceSampleRate: .nan).isEmpty)
        XCTAssertTrue(stream.resampleTo16kLocked(native, sourceSampleRate: 0).isEmpty)
    }
}
