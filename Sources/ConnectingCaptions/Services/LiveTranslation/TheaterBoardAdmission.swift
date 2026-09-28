import Foundation

/// Whether a finished sentence may become a Theater board row.
/// Propose runs before a sentence is queued. Publish runs after translation,
/// while this sentence is still the in-flight entry. Both phases use the same
/// checklist. Publish ignores this sentence's own in-flight entry, and a
/// translated sentence must still be tracked.
enum TheaterBoardAdmission {
    enum Phase: Equatable {
        case propose
        case publish
    }

    enum Decision: Equatable {
        case admit
        case skip(Reason)
    }

    enum Reason: String, Equatable {
        case empty
        case junk
        case tooThin
        case inFlight
        case sameAsPrinted
        case revisesEarlier
        case revisesNewest
        case repeatsPrintedEnding
        case printedThisListen
        case rejoinsPrinted
        case untracked
    }

    struct Context: Equatable {
        var peelSources: [String] = []
        var inFlightSources: [String] = []
        var commitIdentities: Set<String> = []
        var latestHypothesis: String = ""
        var requiresTrackedIdentity: Bool = false
        /// Insert Stop may type one trailing fragment the clause cutter refused.
        var allowTrailingFragment: Bool = false
    }

    static func decide(
        _ source: String,
        languageID: String,
        phase: Phase,
        context: Context
    ) -> Decision {
        let cleaned = source.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.isEmpty { return .skip(.empty) }
        if CaptionJunkGate.shouldDrop(cleaned) { return .skip(.junk) }
        if !context.allowTrailingFragment,
           TranslationClauseSegmenter.isTooThinToCommit(cleaned, languageID: languageID)
        {
            return .skip(.tooThin)
        }

        var inFlight = context.inFlightSources
        if phase == .publish {
            inFlight.removeAll { TranslationClauseSegmenter.isSameClause($0, cleaned) }
        }
        if inFlight.contains(where: { TranslationClauseSegmenter.isSameClause($0, cleaned) }) {
            return .skip(.inFlight)
        }

        if context.peelSources.dropLast().contains(where: {
            Self.repeatsEarlierRow($0, incoming: cleaned, languageID: languageID)
        }) {
            return .skip(.revisesEarlier)
        }

        if let last = context.peelSources.last {
            if TranslationClauseSegmenter.isSameClause(last, cleaned) {
                return .skip(.sameAsPrinted)
            }
            if TranslationClauseSegmenter.isInPlaceGrowth(previous: last, incoming: cleaned) {
                return .skip(.revisesNewest)
            }
            if Self.revisesNewest(
                previous: last,
                incoming: cleaned,
                languageID: languageID,
                hypothesis: context.latestHypothesis
            ) {
                return .skip(.revisesNewest)
            }
        }
        if context.peelSources.contains(where: { TranslationClauseSegmenter.isSameClause($0, cleaned) }) {
            return .skip(.sameAsPrinted)
        }
        if Self.rejoinsPrintedRows(cleaned, rows: context.peelSources, languageID: languageID) {
            return .skip(.rejoinsPrinted)
        }
        if context.peelSources.suffix(2).contains(where: {
            Self.repeatsPrintedEnding(printed: $0, incoming: cleaned, hypothesis: context.latestHypothesis)
        }) {
            return .skip(.repeatsPrintedEnding)
        }
        // Lines older than the peel window are not in `peelSources`. A full
        // sentence heard again word for word is a replay of the talk, not new speech.
        if phase == .propose,
           TranslationClauseSegmenter.normalizedKey(cleaned).split(separator: " ").count
               >= Self.minimumWordsForListenRepeat,
           context.commitIdentities.contains(TranslationClauseSegmenter.clauseIdentity(cleaned))
        {
            return .skip(.printedThisListen)
        }

        if phase == .publish, context.requiresTrackedIdentity {
            let key = TranslationClauseSegmenter.clauseIdentity(cleaned)
            if key.isEmpty || !context.commitIdentities.contains(key) {
                return .skip(.untracked)
            }
        }
        return .admit
    }

    /// Short replies ("Okay.", "Yeah, sure.") really do repeat in a talk.
    static let minimumWordsForListenRepeat = 4

    /// An earlier row said again, or the same row with more words at its end.
    /// A close sentence ("model" → "modal") after a newer row is the next
    /// caption. Only the newest row takes a correction.
    private static func repeatsEarlierRow(
        _ printed: String,
        incoming: String,
        languageID _: String
    ) -> Bool {
        if TranslationClauseSegmenter.isSameClause(printed, incoming) { return true }
        guard TranslationClauseSegmenter.isInPlaceGrowth(previous: printed, incoming: incoming) else {
            return false
        }
        let printedKey = TranslationClauseSegmenter.normalizedKey(printed)
        let incomingKey = TranslationClauseSegmenter.normalizedKey(incoming)
        if TranslationClauseSegmenter.hasUnspacedScript(incomingKey) {
            return incomingKey.hasPrefix(printedKey)
        }
        // "line 1." is not the start of "line 10.".
        return incomingKey.hasPrefix(printedKey + " ")
    }

    /// Two neighbouring rows, said again as one sentence. "adjusts to new."
    /// plus "inputs, and perform…" is the sentence those rows already printed.
    private static func rejoinsPrintedRows(
        _ incoming: String,
        rows: [String],
        languageID: String
    ) -> Bool {
        guard rows.count >= 2 else { return false }
        for index in 0..<(rows.count - 1) {
            let joined = rows[index] + " " + rows[index + 1]
            if TranslationClauseSegmenter.isSameClause(joined, incoming)
                || TranslationClauseSegmenter.isInPlaceGrowth(previous: joined, incoming: incoming)
                || TranslationClauseSegmenter.shouldReviseCommitted(
                    previous: joined,
                    incoming: incoming,
                    languageID: languageID
                )
            {
                return true
            }
        }
        return false
    }

    /// A restitch re-punctuates a printed line ("come on, please work." →
    /// "come on. Please work.") and its ending looks like a new sentence.
    /// Speech that really says it twice still has two copies in the hypothesis.
    static func repeatsPrintedEnding(printed: String, incoming: String, hypothesis: String) -> Bool {
        let printedKey = TranslationClauseSegmenter.normalizedKey(printed)
        let incomingKey = TranslationClauseSegmenter.normalizedKey(incoming)
        guard !incomingKey.isEmpty, printedKey.count > incomingKey.count else { return false }
        let endsPrinted = TranslationClauseSegmenter.hasUnspacedScript(incomingKey)
            ? printedKey.hasSuffix(incomingKey)
            : printedKey.hasSuffix(" " + incomingKey)
        guard endsPrinted else { return false }
        let heard = TranslationClauseSegmenter.normalizedKey(hypothesis)
        return Self.occurrences(of: incomingKey, in: heard) < 2
    }

    private static func occurrences(of needle: String, in haystack: String) -> Int {
        guard !needle.isEmpty else { return 0 }
        var count = 0
        var searchRange = haystack.startIndex..<haystack.endIndex
        while let found = haystack.range(of: needle, range: searchRange) {
            count += 1
            searchRange = found.upperBound..<haystack.endIndex
        }
        return count
    }

    private static func revisesNewest(
        previous: String,
        incoming: String,
        languageID: String,
        hypothesis: String
    ) -> Bool {
        guard TranslationClauseSegmenter.shouldReviseCommitted(
            previous: previous,
            incoming: incoming,
            languageID: languageID
        ) else { return false }
        if TranslationClauseSegmenter.shouldReplaceLast(previous: previous, incoming: incoming) {
            return true
        }
        guard !hypothesis.isEmpty else { return true }
        return !TranslationClauseSegmenter.contains(hypothesis, clause: previous)
    }
}
