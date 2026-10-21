import Foundation

/// Voiced versus room noise for the pause clock. The meter's fixed noise gate
/// sits below a normal laptop mic floor, so a quiet room counted as speech and
/// a pause never finished the last sentence. The floor follows the room: it
/// drops quickly to a quieter packet and climbs slowly, so a long talk does not
/// teach it the speaker's voice.
nonisolated public struct SpeechEnergyGate {
    public static let absoluteMinimumRMS: Float = 0.004
    public static let voicedOverFloor: Float = 2.0
    public static let maximumFloorRMS: Float = 0.015
    public static let floorFallRate: Float = 0.1
    public static let floorRiseRate: Float = 0.0005

    public private(set) var floorRMS: Float?

    public init() {}

    public mutating func reset() {
        self.floorRMS = nil
    }

    public mutating func isVoiced(rms: Float) -> Bool {
        guard rms.isFinite, rms >= 0 else { return false }
        let floor = self.floorRMS ?? rms
        let threshold = max(Self.absoluteMinimumRMS, floor * Self.voicedOverFloor)
        let rate = rms < floor ? Self.floorFallRate : Self.floorRiseRate
        self.floorRMS = min(Self.maximumFloorRMS, floor + (rms - floor) * rate)
        return rms >= threshold
    }

    /// Same bar as `isVoiced`, without teaching the floor. A nil floor uses the
    /// absolute minimum, so a cold start does not treat the first packet as the room.
    public static func isAboveSpeech(rms: Float, floorRMS: Float?) -> Bool {
        guard rms.isFinite, rms >= 0 else { return false }
        let floor = floorRMS ?? Self.absoluteMinimumRMS
        let threshold = max(Self.absoluteMinimumRMS, floor * Self.voicedOverFloor)
        return rms >= threshold
    }
}

/// A click or a single noisy packet must not reopen the pause clock. Real
/// speech reports once the run has lasted long enough to be a word, and the
/// first report uses the start of that run so the latency clock stays put.
nonisolated public struct SustainedSpeechRun {
    public static let minimumSeconds: TimeInterval = 0.08
    /// The input tap hands over about 85 ms at a time, so one noisy packet is
    /// already longer than `minimumSeconds`. A run also needs a second packet.
    public static let minimumPackets = 2
    /// A consonant or a syllable dip. Longer than this, the speaker has stopped.
    public static let allowedGapSeconds: TimeInterval = 0.06

    private var runSamples = 0
    private var runPackets = 0
    private var quietSamples = 0
    private var runHostTime: UInt64 = 0
    private var reporting = false

    public init() {}

    public mutating func reset() {
        self.runSamples = 0
        self.runPackets = 0
        self.quietSamples = 0
        self.runHostTime = 0
        self.reporting = false
    }

    public mutating func speechHostTime(voiced: Bool, samples: Int, hostTime: UInt64) -> UInt64? {
        guard samples > 0 else { return nil }
        if voiced == false {
            guard self.runSamples > 0 else { return nil }
            self.quietSamples += samples
            let allowed = Int((Self.allowedGapSeconds * 16_000).rounded())
            if self.quietSamples > allowed {
                self.reset()
            }
            return nil
        }
        self.quietSamples = 0
        if self.runSamples == 0 {
            self.runHostTime = hostTime
        }
        self.runSamples += samples
        self.runPackets += 1
        let minimum = Int((Self.minimumSeconds * 16_000).rounded())
        guard self.runSamples >= minimum, self.runPackets >= Self.minimumPackets else { return nil }
        let reported = self.reporting ? hostTime : self.runHostTime
        self.reporting = true
        return reported
    }
}
