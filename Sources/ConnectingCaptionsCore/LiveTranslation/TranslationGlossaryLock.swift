import Foundation

/// Locks custom-dictionary terms so Apple Translation does not rewrite names.
public enum TranslationGlossaryLock {
    public struct ProtectedText: Equatable, Sendable {
        public let text: String
        public let tokens: [String: String]

        public init(text: String, tokens: [String: String]) {
            self.text = text
            self.tokens = tokens
        }
    }

    public static func protect(_ text: String, terms: [String]) -> ProtectedText {
        guard !text.isEmpty, !terms.isEmpty else {
            return ProtectedText(text: text, tokens: [:])
        }

        var result = text
        var tokens: [String: String] = [:]
        var index = 0
        for term in self.orderedTerms(terms) {
            guard self.containsTerm(term, in: result) else { continue }
            let token = Self.lockToken(index)
            index += 1
            tokens[token] = term
            result = self.replaceTerm(term, with: token, in: result)
        }
        return ProtectedText(text: result, tokens: tokens)
    }

    public static func restore(_ text: String, tokens: [String: String]) -> String {
        var result = text
        let ordered = tokens.keys.sorted { lhs, rhs in
            let left = self.tokenDigits(lhs)
            let right = self.tokenDigits(rhs)
            if left.count != right.count { return left.count > right.count }
            return left > right
        }
        for token in ordered {
            guard let original = tokens[token] else { continue }
            result = result.replacingOccurrences(of: token, with: original)
            let index = NSRegularExpression.escapedPattern(for: self.tokenDigits(token))
            guard !index.isEmpty else { continue }
            let literal = NSRegularExpression.escapedTemplate(for: original)
            let patterns = [
                "\u{FFF9}\\s*\(index)(?!\\d)\\s*\u{FFFA}",
                "\u{FFF9}\\s*\(index)(?!\\d)",
                "(?<!\\d)\(index)\\s*\u{FFFA}",
            ]
            for pattern in patterns {
                result = result.replacingOccurrences(
                    of: pattern,
                    with: literal,
                    options: .regularExpression
                )
            }
        }
        return result
    }

    /// Format characters left after a glossary token was only partly restored.
    /// Contextual MT marks are removed first so `\u{FFF9}▸\u{FFFA}` is not a lock token.
    public static func containsLockArtifact(_ text: String) -> Bool {
        var stripped = text
        stripped = stripped.replacingOccurrences(
            of: LiveTranslationCommitContext.contextClauseStart,
            with: ""
        )
        stripped = stripped.replacingOccurrences(
            of: LiveTranslationCommitContext.contextClauseEnd,
            with: ""
        )
        return stripped.unicodeScalars.contains { scalar in
            scalar.value == 0xFFF9 || scalar.value == 0xFFFA || scalar.value == 0xFFFB
        }
    }

    /// A dropped or localized lock token must not print as a digit. The caller
    /// translates the same text again with no tokens.
    public static func needsUnlockedFallback(
        source: String,
        rawTranslated _: String,
        restored: String,
        tokens: [String: String]
    ) -> Bool {
        guard !tokens.isEmpty else { return false }
        if self.containsLockArtifact(restored) { return true }
        // A padded token (`\u{FFF9} 0 \u{FFFA}`) is already restored to the name.
        // Falling back only because the exact token string is absent would
        // translate that name again with the lock removed.
        return !self.lostProtectedTerms(
            source: source,
            polished: restored,
            terms: Array(tokens.values)
        ).isEmpty
    }

    /// Terms that appear in the source but vanished from a polished caption.
    public static func lostProtectedTerms(source: String, polished: String, terms: [String]) -> [String] {
        self.orderedTerms(terms).filter { term in
            self.containsTerm(term, in: source) && !self.containsTerm(term, in: polished)
        }
    }

    public static func containsTerm(_ term: String, in text: String) -> Bool {
        let needle = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard needle.count >= 2, !text.isEmpty else { return false }
        return text.range(of: self.termPattern(needle), options: self.termOptions(for: needle)) != nil
    }

    private static func termOptions(for term: String) -> String.CompareOptions {
        if self.requiresExactCase(term) {
            return [.regularExpression]
        }
        return [.regularExpression, .caseInsensitive, .diacriticInsensitive]
    }

    private static func requiresExactCase(_ term: String) -> Bool {
        let letters = term.filter(\.isLetter)
        return letters.count >= 2 && letters.count <= 3 && letters.allSatisfy(\.isUppercase)
    }

    private static func orderedTerms(_ terms: [String]) -> [String] {
        var seen = Set<String>()
        var unique: [String] = []
        for term in terms
            .map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) })
            .filter({ $0.count >= 2 })
            .sorted(by: { $0.count > $1.count })
        {
            if seen.insert(term.lowercased()).inserted {
                unique.append(term)
            }
        }
        return unique
    }

    private static func replaceTerm(_ term: String, with token: String, in text: String) -> String {
        text.replacingOccurrences(of: self.termPattern(term), with: token, options: self.termOptions(for: term))
    }

    private static func termPattern(_ term: String) -> String {
        let escaped = NSRegularExpression.escapedPattern(for: term)
        if self.usesWordBoundary(term) {
            return "\\b\(escaped)\\b"
        }
        return escaped
    }

    private static func usesWordBoundary(_ term: String) -> Bool {
        !term.unicodeScalars.contains { scalar in
            (0xAC00...0xD7AF).contains(scalar.value)
                || (0x3040...0x30FF).contains(scalar.value)
                || (0x4E00...0x9FFF).contains(scalar.value)
                || (0x0E00...0x0E7F).contains(scalar.value)
        }
    }

    private static func lockToken(_ index: Int) -> String {
        "\u{FFF9}\(index)\u{FFFA}"
    }

    private static func tokenDigits(_ token: String) -> String {
        String(token.filter(\.isNumber))
    }
}
