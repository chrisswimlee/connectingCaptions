import Foundation

extension TranslationClauseSegmenter {
    /// English-only joins for a newest line. Other listen languages are unchanged.
    static func englishRowContinuation(row: String, unit: String, languageID: String) -> String? {
        guard self.languageCode(from: languageID) == "en" else { return nil }
        if let appended = self.appendedContinuation(row: row, unit: unit) { return appended }
        if let joined = self.abbreviationContinuation(row: row, unit: unit) { return joined }
        if let joined = self.adverbialContinuation(row: row, unit: unit) { return joined }
        return self.subordinateContinuation(row: row, unit: unit)
    }

    /// "Epstein files." then "The Epstein Files." is the same line with an article.
    /// "The Epstein files are out." is a longer sentence and stays new.
    static func isLeadingArticleRevision(previous: String, incoming: String, languageID: String) -> Bool {
        guard self.languageCode(from: languageID) == "en" else { return false }
        let previousWords = self.englishWordKeys(previous)
        let incomingWords = self.englishWordKeys(incoming)
        guard previousWords.count >= 1, incomingWords.count == previousWords.count + 1 else { return false }
        guard let article = incomingWords.first, ["a", "an", "the"].contains(article) else { return false }
        return Array(incomingWords.dropFirst()) == previousWords
    }

    static func continuesSamePaintedLine(previous: String, incoming: String, languageID: String) -> Bool {
        if self.isInPlaceGrowth(previous: previous, incoming: incoming) { return true }
        return self.isLeadingArticleRevision(previous: previous, incoming: incoming, languageID: languageID)
    }

    /// "across U.S." then "politics in Hollywood." The abbreviation period was
    /// not the end of the sentence. A lowercase "on the other hand" after a
    /// real period still starts its own line.
    static func abbreviationContinuation(row: String, unit: String) -> String? {
        let row = row.trimmingCharacters(in: .whitespacesAndNewlines)
        let unit = unit.trimmingCharacters(in: .whitespacesAndNewlines)
        guard self.endsWithEnglishAbbreviation(row), self.startsContinuation(unit) else { return nil }
        if self.wordsAlreadyPrinted(unit, in: row) { return nil }
        let merged = row + " " + unit
        guard !self.isSameClause(merged, row) else { return nil }
        return merged
    }

    /// "The Epstein Files." then "Deeply shrouded…". A short verbless line
    /// plus an -ly adverb. "Investigators found more." stays the next line.
    static func adverbialContinuation(row: String, unit: String) -> String? {
        let row = row.trimmingCharacters(in: .whitespacesAndNewlines)
        let unit = unit.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = self.tokens(unit).first else { return nil }
        let key = self.tokenKey(first)
        guard key.count >= 4, key.hasSuffix("ly") else { return nil }
        guard !Self.englishSentenceStarters.contains(key),
              !Self.englishSoftSentenceStarters.contains(key)
        else { return nil }
        let rowWords = self.englishWordKeys(row)
        guard (2...4).contains(rowWords.count), self.isVerblessNounPhrase(rowWords) else { return nil }
        guard !CaptionJunkGate.isAcknowledgement(row) else { return nil }
        if self.wordsAlreadyPrinted(unit, in: row) { return nil }
        let stem = self.stripTerminalPunctuation(row).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !stem.isEmpty else { return nil }
        let continued = self.lowercasedContinuation(first) + unit.dropFirst(first.count)
        let merged = stem + " " + continued
        guard !self.isSameClause(merged, row) else { return nil }
        return merged
    }

    /// A long "Despite…" line painted before its main clause arrived.
    /// A short "Because I said so." does not swallow the next sentence.
    static func subordinateContinuation(row: String, unit: String) -> String? {
        let row = row.trimmingCharacters(in: .whitespacesAndNewlines)
        let unit = unit.trimmingCharacters(in: .whitespacesAndNewlines)
        guard self.englishWordKeys(row).count >= 8,
              self.clauseStartsWithDanglingSubordinator(row),
              !self.subordinateClauseHasMainClause(row)
        else { return nil }
        guard let first = self.tokens(unit).first else { return nil }
        let key = self.tokenKey(first)
        guard !Self.englishSentenceStarters.contains(key),
              !Self.englishSoftSentenceStarters.contains(key)
        else { return nil }
        let stem = self.stripTerminalPunctuation(row).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !stem.isEmpty else { return nil }
        let continued = self.lowercasedJoinedWord(first) + unit.dropFirst(first.count)
        let merged = stem + ", " + continued
        guard !self.isSameClause(merged, row) else { return nil }
        return merged
    }

    /// "Because it rained, we stayed home." already has its main clause, so the
    /// next sentence is not its ending. "Despite 250 victims, and clear evidence"
    /// is still waiting for one: a comma before a subject is the signal.
    static func subordinateClauseHasMainClause(_ clause: String) -> Bool {
        var index = clause.startIndex
        while let comma = clause[index...].firstIndex(of: ",") {
            let after = clause.index(after: comma)
            if let first = self.tokens(String(clause[after...])).first,
               Self.mainClauseSubjects.contains(self.tokenKey(first))
            {
                return true
            }
            index = after
        }
        return false
    }

    /// The first word after a joined period. A common word loses its capital;
    /// a name ("Biden", "Apple") keeps it.
    static func lowercasedJoinedWord(_ word: String) -> String {
        let key = self.tokenKey(word)
        guard Self.mainClauseSubjects.contains(key)
            || Self.thinEnglishStarters.contains(key)
            || Self.thinEnglishAuxiliaries.contains(key)
        else { return word }
        return self.lowercasedContinuation(word)
    }

    private static let mainClauseSubjects: Set<String> = [
        "a", "an", "he", "her", "his", "i", "it", "its", "my", "our", "she",
        "that", "the", "their", "there", "these", "they", "this", "those",
        "we", "you", "your",
    ]

    private static func englishWordKeys(_ text: String) -> [String] {
        self.tokens(text).map(self.tokenKey).filter { !$0.isEmpty }
    }

    private static func endsWithEnglishAbbreviation(_ text: String) -> Bool {
        guard let last = self.tokens(text).last else { return false }
        return self.isEnglishAbbreviationToken(last)
    }

    private static func isVerblessNounPhrase(_ words: [String]) -> Bool {
        let content = words.filter { !["a", "an", "the"].contains($0) }
        guard !content.isEmpty else { return false }
        for word in content {
            if Self.thinEnglishStarters.contains(word) { return false }
            if Self.thinEnglishAuxiliaries.contains(word) { return false }
            if Self.shortClauseVerbs.contains(word) { return false }
        }
        return true
    }

    private static let shortClauseVerbs: Set<String> = [
        "asked", "became", "began", "called", "came", "continued", "ended",
        "found", "gave", "got", "kept", "knew", "left", "made", "said", "saw",
        "says", "started", "told", "took", "went",
    ]
}
