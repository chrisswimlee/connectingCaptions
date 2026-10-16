import Foundation

/// Seconds on the microphone capture clock, relative to the first accepted PCM.
/// Optional on old history and engines that do not return speech timestamps.
nonisolated struct CaptionSpeechTiming: Codable, Equatable, Sendable {
    var start: TimeInterval
    var end: TimeInterval

    var isValid: Bool {
        self.start.isFinite && self.end.isFinite && self.start >= 0
            && self.end > self.start && self.end < Double(Int.max / 1000)
    }
}

nonisolated struct ASRTimedSegment: Equatable, Sendable {
    var text: String
    var start: TimeInterval
    var end: TimeInterval
}

/// A bounded recognition window. Match complete recognizer segments; never
/// invent word times by distributing a sentence across its character count.
nonisolated struct CaptionSpeechTimeline {
    private var segments: [ASRTimedSegment] = []
    /// Concatenated identity text and its per-segment spans, rebuilt once per
    /// `ingest` instead of once per `timing(for:)` call — the same window is
    /// looked up several times per committed caption.
    private var concatenatedText: String = ""
    private var spans: [(range: Range<Int>, segment: ASRTimedSegment)] = []

    mutating func ingest(_ incoming: [ASRTimedSegment]) {
        let valid = incoming.filter { CaptionSpeechTiming(start: $0.start, end: $0.end).isValid }
        guard let start = valid.map(\.start).min(), let end = valid.map(\.end).max() else { return }
        self.segments.removeAll { $0.end > start && $0.start < end }
        self.segments.append(contentsOf: valid)
        self.segments.sort { $0.start < $1.start }
        self.segments = Array(self.segments.filter { $0.end >= end - 60 }.suffix(2048))
        self.rebuildIndex()
    }

    func nextTiming(for source: String, occurrence: Int?, expectedOccurrences: Int?, after end: TimeInterval?) -> CaptionSpeechTiming? {
        if let end, expectedOccurrences == 1,
           let latest = self.timing(for: source), latest.start >= end {
            return latest
        }
        return self.timing(for: source, occurrence: occurrence, expectedOccurrences: expectedOccurrences)
    }

    private mutating func rebuildIndex() {
        var text = ""
        var spans: [(range: Range<Int>, segment: ASRTimedSegment)] = []
        for segment in self.segments {
            let part = Self.identity(segment.text)
            guard !part.isEmpty else { continue }
            let lower = text.count
            text += part
            spans.append((lower..<text.count, segment))
        }
        self.concatenatedText = text
        self.spans = spans
    }

    func timing(for source: String, occurrence: Int? = nil, expectedOccurrences: Int? = nil) -> CaptionSpeechTiming? {
        let needle = Self.identity(source)
        guard !needle.isEmpty else { return nil }
        let text = self.concatenatedText
        let spans = self.spans
        var searchEnd = text.endIndex
        var matches: [CaptionSpeechTiming] = []
        while searchEnd > text.startIndex,
              let match = text.range(of: needle, options: .backwards, range: text.startIndex..<searchEnd) {
            let lower = text.distance(from: text.startIndex, to: match.lowerBound)
            let upper = text.distance(from: text.startIndex, to: match.upperBound)
            if let first = spans.first(where: { $0.range.lowerBound == lower }),
               let last = spans.last(where: { $0.range.upperBound == upper }) {
                let timing = CaptionSpeechTiming(start: first.segment.start, end: last.segment.end)
                if timing.isValid {
                    if occurrence == nil { return timing }
                    matches.append(timing)
                }
            }
            searchEnd = match.lowerBound
        }
        // A bounded timing window may omit earlier copies. Never assign the
        // remaining copy's range to a different occurrence in the transcript.
        guard let occurrence, matches.count == expectedOccurrences,
              occurrence >= 0, occurrence < matches.count else { return nil }
        return matches[matches.count - 1 - occurrence]
    }

    private static func identity(_ text: String) -> String {
        String(String.UnicodeScalarView(text.lowercased().unicodeScalars.filter {
            CharacterSet.alphanumerics.contains($0) || CharacterSet.nonBaseCharacters.contains($0)
        }))
    }
}
