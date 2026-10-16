import Foundation

/// Occurrences inside a cumulative recognition result are distinct speech.
/// Re-reading that result must not accept those occurrences a second time.
/// Distinct speech ranges can also prove a later utterance in a sliding window.
/// The normal restitch/revision policy handles hypotheses without that evidence.
enum CaptionRecognizedOccurrences {
    struct State {
        var acceptedCounts: [String: Int] = [:]
        var speechEnds: [String: TimeInterval] = [:]
        var reservedKeys: Set<String> = []
        var confirmation = ""
        var isFinal = false
        var audioContainsSpeech: Bool?

        mutating func discard(_ hypothesis: String, languageID: String, timeline: CaptionSpeechTimeline) {
            self.acceptedCounts.merge(CaptionRecognizedOccurrences.counts(in: hypothesis, languageID: languageID), uniquingKeysWith: max)
            for unit in TranslationClauseSegmenter.split(hypothesis, languageID: languageID).completed {
                let key = TranslationClauseSegmenter.clauseIdentity(unit)
                if let timing = timeline.timing(for: unit) {
                    self.speechEnds[key] = max(self.speechEnds[key, default: 0], timing.end)
                }
            }
        }
    }

    struct Plan {
        var completed: [String]
        var tail: String
        var occurrenceOffsets: [String: Int] = [:]

        /// Some completed sentence in this hypothesis has not printed yet. Once
        /// every copy has, only the open tail is left, and the normal pause and
        /// open-tail settles must own it or it waits for the next utterance.
        func hasUnaccepted(_ accepted: [String: Int]) -> Bool {
            var seen = self.occurrenceOffsets
            for unit in self.completed {
                let key = TranslationClauseSegmenter.clauseIdentity(unit)
                seen[key, default: 0] += 1
                if seen[key, default: 0] > accepted[key, default: 0] { return true }
            }
            return false
        }

        /// Serialize identical pending text without losing later occurrences.
        /// A caller may synchronously publish (Original language), so pending
        /// state is read again after each acceptance.
        func drain(
            accepted: [String: Int],
            confirmed: String,
            languageID: String,
            isFinal: Bool,
            isWaiting: (String) -> Bool,
            accept: (String) -> Void
        ) -> String {
            let confirmedSplit = TranslationClauseSegmenter.split(confirmed, languageID: languageID)
            let confirmedCounts = Dictionary(
                confirmedSplit.completed.map { (TranslationClauseSegmenter.clauseIdentity($0), 1) },
                uniquingKeysWith: +
            )
            var seen = self.occurrenceOffsets
            var unread: [String] = []
            for (index, unit) in self.completed.enumerated() {
                let key = TranslationClauseSegmenter.clauseIdentity(unit)
                seen[key, default: 0] += 1
                let occurrence = seen[key, default: 0]
                if occurrence <= accepted[key, default: 0] { continue }
                let confirmedCount = confirmedCounts[key, default: 0] + self.occurrenceOffsets[key, default: 0]
                if isWaiting(unit) || (!isFinal && occurrence > confirmedCount) {
                    unread = Array(self.completed[index...])
                    break
                }
                accept(unit)
            }
            if !self.tail.isEmpty { unread.append(self.tail) }
            return unread.joined(separator: " ")
        }
    }

    static func plan(
        _ hypothesis: String,
        languageID: String,
        accepted: [String: Int] = [:],
        speechEnds: [String: TimeInterval] = [:],
        timeline: CaptionSpeechTimeline? = nil
    ) -> Plan? {
        let split = TranslationClauseSegmenter.split(hypothesis, languageID: languageID)
        let identities = split.completed.map(TranslationClauseSegmenter.clauseIdentity)
        let counts = Dictionary(identities.map { ($0, 1) }, uniquingKeysWith: +)
        var offsets: [String: Int] = [:]
        // A timed provider can prove a new utterance even when its current
        // text window contains only one copy. Overlapping re-decodes cannot.
        for (unit, key) in zip(split.completed, identities) where counts[key] == 1 {
            if let end = speechEnds[key], let timing = timeline?.timing(for: unit),
               timing.start >= end, accepted[key, default: 0] > 0 {
                offsets[key] = accepted[key]
            }
        }
        guard Set(identities).count < identities.count || !offsets.isEmpty else { return nil }
        return Plan(completed: split.completed, tail: split.tail, occurrenceOffsets: offsets)
    }

    static func counts(in hypothesis: String, languageID: String) -> [String: Int] {
        Dictionary(TranslationClauseSegmenter.split(hypothesis, languageID: languageID).completed.map {
            (TranslationClauseSegmenter.clauseIdentity($0), 1)
        }, uniquingKeysWith: +)
    }
}
