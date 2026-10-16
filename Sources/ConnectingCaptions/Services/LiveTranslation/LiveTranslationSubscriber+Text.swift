import Foundation

extension LiveTranslationSubscriber {
    /// Drop the committed unit from leftover by range. Do not wipe the rest
    /// of the draft when peel cannot find a prefix.
    static func remainingAfterCommittedUnit(_ unit: String, in remaining: String) -> String {
        let unit = unit.trimmingCharacters(in: .whitespacesAndNewlines)
        let remaining = remaining.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !unit.isEmpty, !remaining.isEmpty else { return remaining }
        if remaining.hasPrefix(unit) {
            return remaining.dropFirst(unit.count).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return remaining
    }

    static func translatingStatus(for source: String) -> String {
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Translating…" }
        let limit = 60
        if trimmed.count <= limit {
            return "Translating… \(trimmed)"
        }
        let head = trimmed.prefix(limit)
        if let space = head.lastIndex(of: " "),
           trimmed.distance(from: head.startIndex, to: space) > 24
        {
            return "Translating… \(head[..<space])…"
        }
        return "Translating… \(head)…"
    }

    /// Words that start the next sentence mean this one is done. A lowercase
    /// continuation, or "and" / "but" / "so", stays on this line. A period with
    /// nothing after it can still be taken back.
    static func followingSpeechConfirms(
        unit: String,
        rest: String,
        languageID: String
    ) -> Bool {
        guard TranslationClauseSegmenter.looksComplete(unit, languageID: languageID) else {
            return false
        }
        return TranslationClauseSegmenter.continuesAsNewSentence(rest, languageID: languageID)
    }

    /// The confirmed prefix already includes this sentence, ending included.
    /// The rest of the confirmed text may still be an open tail. A period that
    /// exists only on this tick does not count.
    static func confirmedSentenceAgreed(
        unit: String,
        confirmed: String,
        languageID: String
    ) -> Bool {
        let unit = unit.trimmingCharacters(in: .whitespacesAndNewlines)
        let confirmed = confirmed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !unit.isEmpty, !confirmed.isEmpty else { return false }
        guard TranslationClauseSegmenter.looksComplete(unit, languageID: languageID) else {
            return false
        }
        if confirmed == unit || confirmed.hasPrefix(unit) || confirmed.hasPrefix(unit + " ") {
            return true
        }
        let stripped = unit.trimmingCharacters(in: CharacterSet(charactersIn: ".?!。！？…"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !stripped.isEmpty, stripped != unit, confirmed.hasPrefix(stripped) else { return false }
        let after = confirmed.dropFirst(stripped.count)
        guard let first = after.first else { return false }
        return ".?!。！？…".contains(first)
    }

    static func priorClauses(
        entries: [LectureCaptionEntry],
        listenBatchStart: Int,
        incoming: String,
        limit: Int = LiveTranslationTiming.contextSentenceCount
    ) -> (sources: [String], translations: [String]) {
        LiveTranslationCommitContext.priorClauses(
            entries: entries,
            listenBatchStart: listenBatchStart,
            incoming: incoming,
            limit: limit
        )
    }

    static func suppressionUnits(from text: String) -> [String] {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return [] }
        let languageID = SpokenLanguageResolver.listenLanguageID(for: cleaned)
        let split = TranslationClauseSegmenter.split(cleaned, languageID: languageID)
        var units = split.completed
        let tail = split.tail.trimmingCharacters(in: .whitespacesAndNewlines)
        if !tail.isEmpty { units.append(tail) }
        units.append(cleaned)
        return units
    }

    static func isSameCaption(_ left: String, _ right: String) -> Bool {
        let a = left.trimmingCharacters(in: .whitespacesAndNewlines)
        let b = right.trimmingCharacters(in: .whitespacesAndNewlines)
        if a.isEmpty || b.isEmpty { return false }
        if a == b { return true }
        return TranslationClauseSegmenter.isSameClause(a, b)
    }
}
