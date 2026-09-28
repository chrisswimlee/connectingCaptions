import Foundation

/// Voiced versus room noise for the pause clock. The meter's fixed noise gate
/// sits below a normal laptop mic floor, so a quiet room counted as speech and
/// a pause never finished the last sentence. The floor follows the room: it
/// drops quickly to a quieter packet and climbs slowly, so a long talk does not
/// teach it the speaker's voice.
nonisolated struct SpeechEnergyGate {
    static let absoluteMinimumRMS: Float = 0.004
    static let voicedOverFloor: Float = 2.0
    static let maximumFloorRMS: Float = 0.015
    static let floorFallRate: Float = 0.1
    static let floorRiseRate: Float = 0.0005

    private(set) var floorRMS: Float?

    mutating func reset() {
        self.floorRMS = nil
    }

    mutating func isVoiced(rms: Float) -> Bool {
        guard rms.isFinite, rms >= 0 else { return false }
        let floor = self.floorRMS ?? rms
        let threshold = max(Self.absoluteMinimumRMS, floor * Self.voicedOverFloor)
        let rate = rms < floor ? Self.floorFallRate : Self.floorRiseRate
        self.floorRMS = min(Self.maximumFloorRMS, floor + (rms - floor) * rate)
        return rms >= threshold
    }
}
