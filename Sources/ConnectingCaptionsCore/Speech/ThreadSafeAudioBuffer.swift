import Foundation

nonisolated public enum LiveAudioRetention {
    public static let sampleRate = 16_000
    public static let maximumRetainedSeconds = 30
    public static let maximumRetainedSamples = sampleRate * maximumRetainedSeconds
    public static let incrementalOverlapSeconds = 1
    public static let incrementalOverlapSamples = sampleRate * incrementalOverlapSeconds
    /// Theater re-decodes this recent slice, not the whole 30 s ring, so a tick
    /// cannot stall for tens of seconds and then dump a paragraph.
    public static let theaterPreviewSeconds = 8
    public static let theaterPreviewSamples = sampleRate * theaterPreviewSeconds
    /// Zeros written ahead of the first packet after Resume. Not the real pause.
    public static let resumeSilenceWallSeconds = 1.5
    public static var resumeSilenceWallSamples: Int {
        Int(Double(sampleRate) * resumeSilenceWallSeconds)
    }
}

/// Thread-safe PCM ring. `count` is the logical session length; only the newest
/// retained window stays in RAM.
final nonisolated public class ThreadSafeAudioBuffer {
    private var buffer: [Float] = []
    private var droppedSampleCount = 0
    private var captureTimeline = CaptureAudioTimeline()
    private let lock = NSLock()
    private let maximumRetainedSamples: Int

    public init(maximumRetainedSamples: Int = LiveAudioRetention.maximumRetainedSamples) {
        self.maximumRetainedSamples = max(1, maximumRetainedSamples)
    }

    /// Appends new samples and drops anything older than the retention cap.
    public func append(_ newSamples: [Float], hostTime: UInt64 = 0) {
        guard !newSamples.isEmpty else { return }
        self.lock.lock()
        defer { self.lock.unlock() }
        self.captureTimeline.append(start: self.droppedSampleCount + self.buffer.count, count: newSamples.count, hostTime: hostTime)
        self.buffer.append(contentsOf: newSamples)
        self.dropOverflowLocked()
        self.captureTimeline.trim(before: self.droppedSampleCount)
    }

    public func clear(keepingCapacity: Bool = false) {
        self.lock.lock()
        defer { self.lock.unlock() }
        self.buffer.removeAll(keepingCapacity: keepingCapacity)
        self.droppedSampleCount = 0
        self.captureTimeline = CaptureAudioTimeline()
    }

    public var timingSnapshot: CaptureAudioTimeline {
        self.lock.withLock { self.captureTimeline }
    }

    /// Logical samples captured this session, including already-dropped audio.
    public var count: Int {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.droppedSampleCount + self.buffer.count
    }

    public var retainedCount: Int {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.buffer.count
    }

    public var logicalStart: Int {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.droppedSampleCount
    }

    /// Drops retained samples whose logical index is below `logicalIndex`.
    public func dropSamples(before logicalIndex: Int) {
        self.lock.lock()
        defer { self.lock.unlock() }
        let clamped = min(max(logicalIndex, self.droppedSampleCount), self.droppedSampleCount + self.buffer.count)
        let removeCount = clamped - self.droppedSampleCount
        guard removeCount > 0 else { return }
        self.buffer.removeFirst(removeCount)
        self.droppedSampleCount += removeCount
        self.captureTimeline.trim(before: self.droppedSampleCount)
    }

    /// First `length` retained samples. Never returns dropped audio.
    public func getPrefix(_ length: Int) -> [Float] {
        self.lock.lock()
        defer { self.lock.unlock() }
        let safeLength = min(max(0, length), self.buffer.count)
        return Array(self.buffer[0..<safeLength])
    }

    /// Exact logical range when every requested sample is still retained.
    public func getRange(startingAt start: Int, count: Int) -> [Float] {
        self.lock.lock()
        defer { self.lock.unlock() }
        guard start >= 0,
              count > 0,
              start >= self.droppedSampleCount,
              start <= self.droppedSampleCount + self.buffer.count,
              count <= self.droppedSampleCount + self.buffer.count - start
        else {
            return []
        }
        let localStart = start - self.droppedSampleCount
        return Array(self.buffer[localStart..<(localStart + count)])
    }

    public func getRetained() -> [Float] {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.buffer
    }

    /// Retained window only. Long sessions do not materialize dropped PCM.
    public func getAll() -> [Float] {
        self.getRetained()
    }

    private func dropOverflowLocked() {
        guard self.buffer.count > self.maximumRetainedSamples else { return }
        let overflow = self.buffer.count - self.maximumRetainedSamples
        self.buffer.removeFirst(overflow)
        self.droppedSampleCount += overflow
    }
}

/// Packet anchors preserve real pauses, device discontinuities and Resume's
/// synthetic silence wall. Only anchors for retained PCM stay in memory.
nonisolated public struct CaptureAudioTimeline {
    private struct Anchor {
        public var start: Int
        public var count: Int
        public var hostTime: UInt64
    }
    private var anchors: [Anchor] = []
    private var origin: UInt64?

    public init() {}

    public mutating func append(start: Int, count: Int, hostTime: UInt64) {
        guard hostTime > 0 else { return }
        if self.origin == nil { self.origin = hostTime }
        self.anchors.append(Anchor(start: start, count: count, hostTime: hostTime))
    }

    public mutating func trim(before sample: Int) {
        self.anchors.removeAll { $0.start + $0.count < sample }
    }

    public func seconds(at sample: Int, isEnd: Bool = false) -> TimeInterval? {
        guard let origin = self.origin,
              let anchor = (isEnd
                ? self.anchors.first(where: { $0.start < sample && sample <= $0.start + $0.count })
                : self.anchors.last(where: { $0.start <= sample && sample < $0.start + $0.count })),
              anchor.hostTime >= origin
        else { return nil }
        return Double(anchor.hostTime - origin) / LiveTranslationHostClock.ticksPerSecond
            + Double(sample - anchor.start) / 16_000
    }

    public func map(
        _ segments: [ASRTimedSegment],
        sourceStart: Int,
        removedSilence: PauseIntervalAudio.Prepared? = nil
    ) -> [ASRTimedSegment] {
        segments.compactMap { segment in
            guard segment.start.isFinite, segment.end.isFinite,
                  segment.start >= 0, segment.end > segment.start,
                  segment.end < Double(Int.max / 16_000) else { return nil }
            let decodedStart = Int((segment.start * 16_000).rounded())
            let decodedEnd = Int((segment.end * 16_000).rounded())
            let start = removedSilence.map { $0.sourceSample(at: decodedStart) } ?? decodedStart
            let end = removedSilence.map { $0.sourceSample(at: decodedEnd, isEnd: true) } ?? decodedEnd
            guard let start, let end,
                  let from = self.seconds(at: sourceStart + start),
                  let to = self.seconds(at: sourceStart + end, isEnd: true), to > from else { return nil }
            return ASRTimedSegment(text: segment.text, start: from, end: to)
        }
    }
}
