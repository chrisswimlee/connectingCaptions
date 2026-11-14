import Foundation

/// Joins recognizer segments into one caption. Every recognizer, Mac and iOS,
/// uses this so a line reads the same on each screen.
///
/// Thai, Japanese, and Chinese put no space between words, so two segments in
/// those scripts join with nothing between them. Korean is written with spaces
/// and joins with one, like English.
///
/// `absorb` is the live path. A later result that repeats or corrects text
/// already held replaces that span. It is not written out a second time.
nonisolated public enum RecognizedSegmentJoin {
    public static func join(_ left: String, _ right: String) -> String {
        if right.isEmpty { return left }
        if left.isEmpty { return right }
        if self.isUnspaced(left.last), self.isUnspaced(right.first) {
            return left + right
        }
        return left + " " + right
    }

    /// Fold one recognizer update into the caption held so far.
    public static func absorb(existing: String, next: String) -> String {
        let existing = existing.trimmingCharacters(in: .whitespacesAndNewlines)
        let next = next.trimmingCharacters(in: .whitespacesAndNewlines)
        if next.isEmpty { return existing }
        if existing.isEmpty { return next }
        let languageID = self.revisionLanguage(for: existing + next)
        let nextGrows = self.startsWith(next, prefix: existing)
        let existingHolds = self.startsWith(existing, prefix: next)
        if nextGrows, !existingHolds { return next }
        if nextGrows, existingHolds {
            return next.count >= existing.count ? next : existing
        }
        if self.rewrites(previous: existing, incoming: next, languageID: languageID) {
            return next
        }
        if let replaced = self.replacingLastSentence(existing: existing, next: next, languageID: languageID) {
            return replaced
        }
        if existingHolds || TranslationClauseSegmenter.shouldIgnoreAsStalePrefix(previous: existing, incoming: next) {
            return existing
        }
        if let overlapped = self.overlappingTail(existing: existing, next: next) {
            return overlapped
        }
        return TranslationClauseSegmenter.collapseRepeatedSpeech(
            self.join(existing, next),
            languageID: languageID
        )
    }

    public static func isUnspaced(_ character: Character?) -> Bool {
        guard let character else { return false }
        return character.unicodeScalars.contains { scalar in
            (0x0E00...0x0E7F).contains(scalar.value) // Thai
                || (0x3000...0x303F).contains(scalar.value) // CJK punctuation (。、)
                || (0x3040...0x30FF).contains(scalar.value) // Hiragana, Katakana
                || (0x31F0...0x31FF).contains(scalar.value)
                || (0x3400...0x4DBF).contains(scalar.value) // Han
                || (0x4E00...0x9FFF).contains(scalar.value)
                || (0xFF01...0xFF0F).contains(scalar.value) // Fullwidth ！？
                || (0xFF1A...0xFF1F).contains(scalar.value)
                || (0xFF66...0xFF9D).contains(scalar.value) // Halfwidth Katakana
        }
    }

    /// Same words, or a close correction ("modal" → "model"), including of the
    /// last sentence only. A new sentence after the held text is not this.
    private static func rewrites(previous: String, incoming: String, languageID: String) -> Bool {
        if TranslationClauseSegmenter.shouldReplaceLast(previous: previous, incoming: incoming) { return true }
        if TranslationClauseSegmenter.isInPlaceGrowth(previous: previous, incoming: incoming) { return true }
        return TranslationClauseSegmenter.shouldReviseCommitted(
            previous: previous,
            incoming: incoming,
            languageID: languageID
        )
    }

    private static func replacingLastSentence(existing: String, next: String, languageID: String) -> String? {
        let split = TranslationClauseSegmenter.split(existing, languageID: languageID)
        guard let last = split.completed.last, existing.hasSuffix(last), last != existing else { return nil }
        guard self.rewrites(previous: last, incoming: next, languageID: languageID) else { return nil }
        let head = String(existing.dropLast(last.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        return head.isEmpty ? next : self.join(head, next)
    }

    /// "Hello there" starts with "Hello." The next character has to be a
    /// boundary, so "catalog" does not start with "cat".
    private static func startsWith(_ text: String, prefix: String) -> Bool {
        let core = self.withoutTrailingPunctuation(prefix)
        guard !core.isEmpty, text.hasPrefix(core) else { return false }
        if text.count == core.count { return true }
        let next = text[text.index(text.startIndex, offsetBy: core.count)]
        return next.isWhitespace || next.isPunctuation
    }

    private static func withoutTrailingPunctuation(_ text: String) -> String {
        var end = text.endIndex
        while end > text.startIndex {
            let previous = text.index(before: end)
            if !text[previous].isPunctuation { break }
            end = previous
        }
        return String(text[..<end])
    }

    /// The new result repeats the end of the caption and then continues.
    /// Keep one copy of the repeated words.
    private static func overlappingTail(existing: String, next: String) -> String? {
        if TranslationClauseSegmenter.hasUnspacedScript(existing) || TranslationClauseSegmenter.hasUnspacedScript(next) {
            return self.overlappingCharacters(existing: existing, next: next)
        }
        let left = existing.split(whereSeparator: \.isWhitespace).map(String.init)
        let right = next.split(whereSeparator: \.isWhitespace).map(String.init)
        guard left.count >= 3, right.count >= 3 else { return nil }
        let limit = min(left.count, right.count)
        var matched = 0
        for count in 1...limit {
            let suffix = left.suffix(count).map(self.wordKey)
            let prefix = right.prefix(count).map(self.wordKey)
            if suffix == Array(prefix) { matched = count }
        }
        guard matched >= 3 else { return nil }
        if matched == right.count { return existing }
        return self.join(existing, right.dropFirst(matched).joined(separator: " "))
    }

    private static func overlappingCharacters(existing: String, next: String) -> String? {
        let left = Array(existing)
        let right = Array(next)
        let limit = min(left.count, right.count)
        guard limit >= 4 else { return nil }
        var matched = 0
        for count in 4...limit {
            if Array(left.suffix(count)) == Array(right.prefix(count)) { matched = count }
        }
        guard matched >= 4 else { return nil }
        if matched == right.count { return existing }
        return self.join(existing, String(right.dropFirst(matched)))
    }

    private static func wordKey(_ word: String) -> String {
        word.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    private static func revisionLanguage(for text: String) -> String {
        let scalars = text.unicodeScalars
        if scalars.contains(where: { (0x0E00...0x0E7F).contains($0.value) }) { return "th" }
        if scalars.contains(where: { (0xAC00...0xD7AF).contains($0.value) || (0x1100...0x11FF).contains($0.value) }) {
            return "ko"
        }
        if scalars.contains(where: {
            (0x3040...0x30FF).contains($0.value) || (0x4E00...0x9FFF).contains($0.value)
        }) {
            return "ja"
        }
        return "en"
    }
}
