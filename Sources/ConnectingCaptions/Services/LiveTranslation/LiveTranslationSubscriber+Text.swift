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
        guard TranslationClauseSegmenter.canCommitMidTalk(unit, rest: rest, languageID: languageID) else {
            return false
        }
        // A run-on cut has no sentence ending, so the next words cannot
        // confirm it. The cut itself is the confirmation.
        if !TranslationClauseSegmenter.looksComplete(unit, languageID: languageID),
           unit.count + rest.count >= LiveTranslationTiming.maxDraftCharacters
        {
            return true
        }
        return TranslationClauseSegmenter.continuesAsNewSentence(
            rest,
            languageID: languageID,
            prefix: unit
        )
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
        guard TranslationClauseSegmenter.canCommitMidTalk(unit, languageID: languageID) else { return false }
        if confirmed == unit || confirmed.hasPrefix(unit) || confirmed.hasPrefix(unit + " ") {
            return true
        }
        let marks = TranslationClauseSegmenter.terminalPunctuationCharacters
        let stripped = unit.trimmingCharacters(in: CharacterSet(charactersIn: marks))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !stripped.isEmpty, stripped != unit, confirmed.hasPrefix(stripped) else { return false }
        let after = confirmed.dropFirst(stripped.count)
        guard let first = after.first else { return false }
        return marks.contains(first)
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

    func rememberDetectedLanguage(_ text: String, languageID: String) {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty, !languageID.isEmpty else { return }
        self.detectedLanguageByClause[cleaned] = languageID
    }

    func languageIDForClause(_ text: String) -> String {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let recorded = self.detectedLanguageByClause[cleaned] { return recorded }
        if let entry = self.listenContextEntries.last(where: {
            $0.source.trimmingCharacters(in: .whitespacesAndNewlines) == cleaned
        }), let recorded = entry.sourceLanguageID, !recorded.isEmpty {
            return recorded
        }
        return SpokenLanguageResolver.listenLanguageID(for: cleaned)
    }

    func pairForClause(
        _ text: String,
        settings: SettingsStore = .shared
    ) -> (source: TranslationLanguage, target: TranslationLanguage) {
        let configuredSource = SpokenLanguageResolver.sourceLanguage(settings: settings)
        let configuredTarget = SpokenLanguageResolver.targetLanguage(settings: settings)
        guard SpokenLanguageResolver.isDynamicPairingEnabled(settings: settings),
              configuredSource.id != configuredTarget.id
        else {
            return (configuredSource, configuredTarget)
        }
        let heard = self.languageIDForClause(text)
        if heard == configuredTarget.id, let heardLanguage = TranslationLanguageCatalog.language(id: heard) {
            return (heardLanguage, configuredSource)
        }
        if heard == configuredSource.id {
            return (configuredSource, configuredTarget)
        }
        return (configuredSource, configuredTarget)
    }

    static func prefixCompatible(_ shown: String, next: String) -> Bool {
        if next.isEmpty { return shown.isEmpty }
        return next.hasPrefix(shown) || shown.hasPrefix(next)
    }

    func livePrefetchContext(incoming: String) -> (
        prior: (sources: [String], translations: [String]),
        priorIDs: [UInt64]
    ) {
        (
            self.priorClausesForContextualTranslation(incoming: incoming),
            self.priorIDsForPrefetch(incoming: incoming)
        )
    }

    /// The leftover moved to another sentence. Drop the previous Show-as
    /// instead of pairing the new source with that caption: a commit reads
    /// the pair as a cache hit and prints the previous line twice.
    func dropStaleLiveDraftIfNewClause(_ leftover: String) {
        let source = self.translatedDraftSource.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty else { return }
        let incoming = leftover.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !incoming.isEmpty else { return }
        if self.liveDraftStillMatches(source, leftover: incoming) { return }
        self.suppressLiveTranslationDraft()
    }

    func liveDraftStillMatches(_ source: String, leftover: String) -> Bool {
        if TranslationClauseSegmenter.isSameClause(source, leftover) { return true }
        if TranslationClauseSegmenter.isGrowingClause(source, toward: leftover) { return true }
        if TranslationClauseSegmenter.isGrowingClause(leftover, toward: source) { return true }
        let languageID = SpokenLanguageResolver.listenLanguageID(for: leftover)
        return TranslationClauseSegmenter.isLivePrefetchMatch(
            unit: source,
            leftover: leftover,
            languageID: languageID
        )
    }

    func suppressLiveTranslationDraft() {
        guard !self.translatedDraft.isEmpty || !self.translatedDraftSource.isEmpty else { return }
        self.translatedDraft = ""
        self.translatedDraftSource = ""
        self.prefetchCache.invalidate()
    }

    func priorIDsForPrefetch(incoming: String) -> [UInt64] {
        let prior = self.priorClausesForContextualTranslation(incoming: incoming)
        let sources = Set(prior.sources.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) })
        return self.listenContextEntries.compactMap { entry in
            sources.contains(entry.source.trimmingCharacters(in: .whitespacesAndNewlines))
                ? entry.id
                : nil
        }
    }

    func adjustIndexes(trimmedCount: Int) {
        guard trimmedCount > 0 else { return }
        self.listenBatchStart = max(0, self.listenBatchStart - trimmedCount)
        self.postedLineCount = max(0, self.postedLineCount - trimmedCount)
    }

    static func isSameCaption(_ left: String, _ right: String) -> Bool {
        let a = left.trimmingCharacters(in: .whitespacesAndNewlines)
        let b = right.trimmingCharacters(in: .whitespacesAndNewlines)
        if a.isEmpty || b.isEmpty { return false }
        if a == b { return true }
        return TranslationClauseSegmenter.isSameClause(a, b)
    }
}
