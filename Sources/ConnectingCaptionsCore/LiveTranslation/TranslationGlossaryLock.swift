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
        for (token, original) in tokens {
            result = result.replacingOccurrences(of: token, with: original)
        }
        return result
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
}
