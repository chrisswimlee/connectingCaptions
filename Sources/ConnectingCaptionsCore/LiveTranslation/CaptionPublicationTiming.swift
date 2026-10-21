import Foundation

/// Owns one pause flush at a time. A cancelled flush must not clear the task
/// that replaced it, and a completed flush must not keep future captions waiting.
@MainActor
final public class CaptionPublicationTiming {
    private var flushID: UUID?
    private var lastPartialUptime: TimeInterval?
    public private(set) var partialCadence: TimeInterval = 0

    public init() {}

    public var isFlushing: Bool { self.flushID != nil }

    public func flush(onFinish: @escaping () -> Void, operation: @escaping () async -> Void) -> Task<Void, Never> {
        let id = UUID()
        self.flushID = id
        return Task {
            defer {
                if self.flushID == id {
                    self.flushID = nil
                    onFinish()
                }
            }
            await operation()
        }
    }

    public func cancelFlush() { self.flushID = nil }

    public func notePartial(at now: TimeInterval) {
        defer { self.lastPartialUptime = now }
        guard let last = self.lastPartialUptime else { return }
        let gap = now - last
        guard gap > 0, gap <= LiveTranslationTiming.partialCadenceMaxSeconds else { return }
        self.partialCadence = self.partialCadence > 0 ? self.partialCadence * 0.7 + gap * 0.3 : gap
    }

    public func reset() {
        self.cancelFlush()
        self.lastPartialUptime = nil
        self.partialCadence = 0
    }
}
