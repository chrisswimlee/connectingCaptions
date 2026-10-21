import Darwin
import Foundation

/// Converts Core Audio host ticks into `ProcessInfo` uptime so tests can inject both clocks.
public enum LiveTranslationHostClock {
    public static let ticksPerSecond: Double = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        guard info.numer != 0, info.denom != 0 else { return 1_000_000_000 }
        return 1_000_000_000.0 * Double(info.denom) / Double(info.numer)
    }()

    public static func ticks(forSeconds seconds: TimeInterval) -> UInt64 {
        let value = (seconds * self.ticksPerSecond).rounded()
        guard value.isFinite, value > 0 else { return 0 }
        if value >= Double(UInt64.max) { return .max }
        return UInt64(value)
    }

    public static func uptime(
        fromHostTime hostTime: UInt64,
        nowUptime: TimeInterval,
        nowHostTime: UInt64
    ) -> TimeInterval {
        guard hostTime > 0, self.ticksPerSecond > 0 else { return nowUptime }
        let (elapsedTicks, overflowed) = nowHostTime.subtractingReportingOverflow(hostTime)
        guard !overflowed else { return nowUptime }
        let elapsed = Double(elapsedTicks) / self.ticksPerSecond
        guard elapsed.isFinite else { return nowUptime }
        return nowUptime - elapsed
    }
}

public enum LiveTranslationSilenceGate {
    public static func isPastHold(
        lastVoicedUptime: TimeInterval?,
        now: TimeInterval,
        holdSeconds: TimeInterval = LiveTranslationTiming.silenceHoldSeconds
    ) -> Bool {
        guard let lastVoicedUptime else { return true }
        return now - lastVoicedUptime >= holdSeconds
    }

    public static func shouldSkipASRTick(
        hadFirstTick: Bool,
        lastVoicedUptime: TimeInterval?,
        now: TimeInterval,
        holdSeconds: TimeInterval = LiveTranslationTiming.silenceHoldSeconds,
        consumedSilenceEdgeTick: Bool = false,
        thermal: ProcessInfo.ThermalState = .nominal
    ) -> Bool {
        guard hadFirstTick else { return false }
        guard self.isPastHold(
            lastVoicedUptime: lastVoicedUptime,
            now: now,
            holdSeconds: holdSeconds
        ) else { return false }
        return consumedSilenceEdgeTick || self.treatsSilenceEdgeAsConsumed(thermal)
    }

    /// Hot Macs skip the post-hold silence-edge tick so pause does not keep the Neural Engine warm.
    /// `.nominal`, `.fair`, and unknown states keep the existing consume-flag policy.
    public static func treatsSilenceEdgeAsConsumed(_ thermal: ProcessInfo.ThermalState) -> Bool {
        switch thermal {
        case .serious, .critical:
            return true
        case .nominal, .fair:
            return false
        @unknown default:
            return false
        }
    }

    /// Critical thermal is the only state that swaps the Voice Engine.
    /// Serious keeps silence-edge tick thinning only.
    public static func shouldDowngradeEngine(_ thermal: ProcessInfo.ThermalState) -> Bool {
        switch thermal {
        case .critical:
            return true
        default:
            return false
        }
    }
}

public enum LiveTranslationThermalReadout {
    public static func label(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal:
            return "nominal"
        case .fair:
            return "fair"
        case .serious:
            return "serious"
        case .critical:
            return "critical"
        @unknown default:
            return "unknown"
        }
    }
}

public struct LiveTranslationLatencySample: Equatable {
    public var micMilliseconds: Int?
    public var endToEndMilliseconds: Int?
    public var asrMilliseconds: Int?
    public var machineTranslationMilliseconds: Int?
    public var thermalState: ProcessInfo.ThermalState = .nominal

    public init(
        micMilliseconds: Int? = nil,
        endToEndMilliseconds: Int? = nil,
        asrMilliseconds: Int? = nil,
        machineTranslationMilliseconds: Int? = nil,
        thermalState: ProcessInfo.ThermalState = .nominal
    ) {
        self.micMilliseconds = micMilliseconds
        self.endToEndMilliseconds = endToEndMilliseconds
        self.asrMilliseconds = asrMilliseconds
        self.machineTranslationMilliseconds = machineTranslationMilliseconds
        self.thermalState = thermalState
    }

    public var displayText: String {
        var parts: [String] = []
        if let micMilliseconds {
            let label = "mic"
            parts.append("\(label) \(micMilliseconds)")
        }
        if let endToEndMilliseconds {
            parts.append("\(endToEndMilliseconds)ms e2e")
        }
        if let asrMilliseconds {
            parts.append("ASR \(asrMilliseconds)")
        }
        if let machineTranslationMilliseconds, endToEndMilliseconds != nil || asrMilliseconds != nil {
            parts.append("MT \(machineTranslationMilliseconds)")
        } else if let machineTranslationMilliseconds {
            parts.append("MT \(machineTranslationMilliseconds)ms")
        }
        parts.append("thermal \(LiveTranslationThermalReadout.label(self.thermalState))")
        return parts.joined(separator: " · ")
    }

    public var compactText: String {
        if let endToEndMilliseconds {
            return "\(endToEndMilliseconds)ms"
        }
        if let machineTranslationMilliseconds {
            return "MT \(machineTranslationMilliseconds)ms"
        }
        return ""
    }
}

public struct LiveTranslationLatencyTracker: Equatable {
    public init() {}

    public private(set) var listenStart: TimeInterval?
    public private(set) var firstBuffer: TimeInterval?
    public private(set) var speechStart: TimeInterval?
    public private(set) var asrReady: TimeInterval?
    public private(set) var lastSample = LiveTranslationLatencySample()

    public mutating func markListenStart(_ time: TimeInterval) {
        if self.listenStart == nil {
            self.listenStart = time
        }
    }

    public mutating func markFirstBuffer(_ time: TimeInterval) {
        if self.firstBuffer == nil {
            self.firstBuffer = time
        }
        if self.listenStart == nil {
            self.listenStart = time
        }
    }

    public mutating func markSpeechStart(_ time: TimeInterval) {
        if self.speechStart == nil {
            self.speechStart = time
        }
    }

    public mutating func markASRReady(_ time: TimeInterval) {
        if self.asrReady == nil {
            self.asrReady = time
        }
    }

    @discardableResult
    public mutating func markTranslated(
        at time: TimeInterval,
        mtMilliseconds: Int,
        thermal: ProcessInfo.ThermalState
    ) -> LiveTranslationLatencySample {
        let mic: Int?
        if let start = self.listenStart, let buffer = self.firstBuffer {
            mic = Int((max(0, buffer - start) * 1000).rounded())
        } else {
            mic = nil
        }
        let endToEnd = self.speechStart.map { start in
            Int((max(0, time - start) * 1000).rounded())
        }
        let asr: Int?
        if let start = self.speechStart, let ready = self.asrReady {
            asr = Int((max(0, ready - start) * 1000).rounded())
        } else {
            asr = nil
        }
        self.lastSample = LiveTranslationLatencySample(
            micMilliseconds: mic,
            endToEndMilliseconds: endToEnd,
            asrMilliseconds: asr,
            machineTranslationMilliseconds: mtMilliseconds,
            thermalState: thermal
        )
        return self.lastSample
    }

    public mutating func refreshThermal(_ thermal: ProcessInfo.ThermalState) -> LiveTranslationLatencySample {
        self.lastSample.thermalState = thermal
        return self.lastSample
    }

    public mutating func resetUtterance() {
        self.listenStart = nil
        self.firstBuffer = nil
        self.speechStart = nil
        self.asrReady = nil
    }
}

/// Last successful Theater clause clock, for filling docs after a real Listen.
public enum LastListenLatencyStore {
    public struct Record: Codable, Equatable {
        public var micMilliseconds: Int?
        public var endToEndMilliseconds: Int?
        public var asrMilliseconds: Int?
        public var machineTranslationMilliseconds: Int?
        public var thermal: String
        public var recordedAt: Date
    }

    public static func write(
        _ sample: LiveTranslationLatencySample,
        to url: URL? = nil,
        fileManager: FileManager = .default
    ) {
        guard sample.endToEndMilliseconds != nil || sample.machineTranslationMilliseconds != nil else { return }
        let record = Record(
            micMilliseconds: sample.micMilliseconds,
            endToEndMilliseconds: sample.endToEndMilliseconds,
            asrMilliseconds: sample.asrMilliseconds,
            machineTranslationMilliseconds: sample.machineTranslationMilliseconds,
            thermal: LiveTranslationThermalReadout.label(sample.thermalState),
            recordedAt: Date()
        )
        let destination = url ?? self.url(fileManager: fileManager)
        do {
            try fileManager.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(record)
            try data.write(to: destination, options: .atomic)
        } catch {
            CoreLog.debug(
                "Could not write last Listen latency: \(error.localizedDescription)",
                source: "LiveTranslation"
            )
        }
    }

    public static func read(from url: URL? = nil, fileManager: FileManager = .default) -> Record? {
        let source = url ?? self.url(fileManager: fileManager)
        guard let data = try? Data(contentsOf: source) else { return nil }
        return try? JSONDecoder().decode(Record.self, from: data)
    }

    public static func url(fileManager: FileManager = .default) -> URL {
        AppSupportDirectory.url(fileManager: fileManager).appendingPathComponent("LastListenLatency.json")
    }
}
