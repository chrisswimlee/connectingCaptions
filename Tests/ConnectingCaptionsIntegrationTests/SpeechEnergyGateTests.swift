@testable import ConnectingCaptions_Debug
import XCTest

final class SpeechEnergyGateTests: XCTestCase {
    /// A laptop mic in a quiet room reads about 0.006–0.007 RMS. That must not
    /// hold the pause clock open.
    func testRoomNoiseIsNotSpeech() {
        var gate = SpeechEnergyGate()
        for rms in [0.0065, 0.0061, 0.0070, 0.0066, 0.0068] as [Float] {
            XCTAssertFalse(gate.isVoiced(rms: rms), "room noise \(rms)")
        }
    }

    func testSpeechOverTheRoomIsVoiced() {
        var gate = SpeechEnergyGate()
        for _ in 0..<50 { _ = gate.isVoiced(rms: 0.0065) }
        XCTAssertTrue(gate.isVoiced(rms: 0.03))
        XCTAssertTrue(gate.isVoiced(rms: 0.02))
        XCTAssertFalse(gate.isVoiced(rms: 0.0068))
    }

    func testStartingMidSentenceStillFindsThePause() {
        var gate = SpeechEnergyGate()
        for _ in 0..<20 { _ = gate.isVoiced(rms: 0.03) }
        var sawSilence = false
        for _ in 0..<60 where !gate.isVoiced(rms: 0.0065) {
            sawSilence = true
        }
        XCTAssertTrue(sawSilence)
    }

    func testALongTalkDoesNotLearnTheVoiceAsTheFloor() {
        var gate = SpeechEnergyGate()
        _ = gate.isVoiced(rms: 0.0065)
        for _ in 0..<(94 * 60) { _ = gate.isVoiced(rms: 0.03) }
        XCTAssertLessThanOrEqual(gate.floorRMS ?? 1, SpeechEnergyGate.maximumFloorRMS)
        XCTAssertTrue(gate.isVoiced(rms: 0.035))
        XCTAssertFalse(gate.isVoiced(rms: 0.0065))
    }

    func testResetForgetsTheLastRoom() {
        var gate = SpeechEnergyGate()
        _ = gate.isVoiced(rms: 0.02)
        gate.reset()
        XCTAssertNil(gate.floorRMS)
    }
}
