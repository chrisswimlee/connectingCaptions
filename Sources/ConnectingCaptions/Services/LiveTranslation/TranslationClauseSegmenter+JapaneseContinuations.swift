import Foundation

extension TranslationClauseSegmenter {
    /// English and, but, so — or a Japanese ので / けど leftover — stay on
    /// the newest line. Other listen languages are unchanged.
    static func rowContinuation(row: String, unit: String, languageID: String) -> String? {
        if let english = self.englishRowContinuation(row: row, unit: unit, languageID: languageID) {
            return english
        }
        return self.japaneseRowContinuation(row: row, unit: unit, languageID: languageID)
    }

    /// "今日は休みです" then "ので家にいます" is still that sentence.
    /// "そして次に適用しました" opens the next caption.
    static func japaneseRowContinuation(row: String, unit: String, languageID: String) -> String? {
        guard self.languageCode(from: languageID) == "ja" else { return nil }
        let row = row.trimmingCharacters(in: .whitespacesAndNewlines)
        let unit = unit.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !row.isEmpty, !unit.isEmpty else { return nil }
        guard self.japaneseRemainderContinuesClause(unit) else { return nil }
        guard self.looksComplete(row, languageID: languageID)
            || self.looksComplete(self.stripTerminalPunctuation(row), languageID: languageID)
        else { return nil }
        if self.wordsAlreadyPrinted(unit, in: row) { return nil }
        let stem = self.stripTerminalPunctuation(row)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !stem.isEmpty else { return nil }
        let merged = stem + unit
        guard !self.isSameClause(merged, row) else { return nil }
        return merged
    }

    /// Particles and connectives that finish the clause just peeled, not a
    /// new sentence. そして / それから / 次に / また / しかし start the next one.
    static func japaneseRemainderContinuesClause(_ rest: String) -> Bool {
        let rest = rest.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = rest.first else { return false }
        if Self.japaneseSentenceStarters.contains(where: { rest.hasPrefix($0) }) {
            return false
        }
        if rest.hasPrefix("しかし") { return false }
        switch first {
        case "の", "け", "が", "し", "て", "ば", "と", "か", "よ", "ね":
            return true
        default:
            return false
        }
    }
}
