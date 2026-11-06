import AppKit
import Foundation

struct KeywordTerm: Equatable {
    var matchWords: [String]
    var matchText: String
    var replacement: String
    var explicit: Bool

    static let maxCount = 2_000

    static func parse(line: String) -> KeywordTerm? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { return nil }
        if let arrow = trimmed.range(of: "->") {
            let left = trimmed[..<arrow.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
            let right = trimmed[arrow.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
            let words = Self.words(in: left)
            guard !words.isEmpty, !right.isEmpty else { return nil }
            return KeywordTerm(matchWords: words, matchText: left, replacement: right, explicit: true)
        }
        let words = Self.words(in: trimmed)
        guard !words.isEmpty else { return nil }
        return KeywordTerm(matchWords: words, matchText: trimmed, replacement: trimmed, explicit: false)
    }

    static func load(from folder: URL, fileManager: FileManager = .default) -> [KeywordTerm] {
        guard let urls = try? fileManager.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return [] }
        let files = urls
            .filter { $0.pathExtension.lowercased() == "txt" }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        var terms: [KeywordTerm] = []
        for url in files {
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            for line in text.components(separatedBy: .newlines) {
                guard let term = Self.parse(line: line) else { continue }
                terms.append(term)
                if terms.count >= Self.maxCount { return terms }
            }
        }
        return terms
    }

    private static func words(in text: String) -> [String] {
        text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
    }
}

struct KeywordAnchor {
    typealias MisspellingCheck = (_ word: String, _ languageID: String) -> Bool

    private let terms: [KeywordTerm]
    private let phrasesByFirst: [String: [KeywordTerm]]
    private let fuzzyByLength: [Int: [FuzzyTarget]]
    private let isMisspelled: MisspellingCheck
    private let misspellCache = MisspellCache()

    init(terms: [KeywordTerm], isMisspelled: @escaping MisspellingCheck = KeywordAnchor.systemIsMisspelled) {
        self.terms = terms
        var phrases: [String: [KeywordTerm]] = [:]
        var fuzzy: [Int: [FuzzyTarget]] = [:]
        var seenFuzzy = Set<String>()
        for term in terms {
            let first = term.matchWords[0].lowercased()
            phrases[first, default: []].append(term)
            let fuzzyWords = term.explicit
                ? term.replacement.split(whereSeparator: { $0.isWhitespace }).map(String.init)
                : term.matchWords
            for word in fuzzyWords {
                let key = word.lowercased()
                guard word.count >= 4, seenFuzzy.insert(key).inserted else { continue }
                fuzzy[word.count, default: []].append(FuzzyTarget(display: word, folded: Array(key)))
            }
        }
        for key in phrases.keys {
            phrases[key]?.sort { $0.matchWords.count > $1.matchWords.count }
        }
        self.phrasesByFirst = phrases
        self.fuzzyByLength = fuzzy
        self.isMisspelled = isMisspelled
    }

    func apply(_ text: String, languageID: String) -> String {
        guard !self.terms.isEmpty, !text.isEmpty else { return text }
        if Self.usesSubstring(languageID) {
            return self.applySubstrings(text)
        }
        return self.applyWords(text, languageID: languageID)
    }

    func matchedTerms(in text: String) -> [String] {
        guard !self.terms.isEmpty, !text.isEmpty else { return [] }
        var found: [String] = []
        var seen = Set<String>()
        for term in self.terms {
            let needle = term.replacement.trimmingCharacters(in: .whitespacesAndNewlines)
            guard needle.count >= 2 else { continue }
            let key = needle.lowercased()
            guard seen.insert(key).inserted else { continue }
            if Self.contains(needle, in: text) {
                found.append(needle)
            }
        }
        return found
    }

    static func systemIsMisspelled(_ word: String, languageID: String) -> Bool {
        let language = Self.spellLanguage(for: languageID)
        guard Self.hasSpellingDictionary(language) else { return false }
        let range = NSSpellChecker.shared.checkSpelling(
            of: word,
            startingAt: 0,
            language: language,
            wrap: false,
            inSpellDocumentWithTag: 0,
            wordCount: nil
        )
        return range.location != NSNotFound
    }

    private func applyWords(_ text: String, languageID: String) -> String {
        let pieces = Self.pieces(in: text)
        var cursor = 0
        var output = ""
        output.reserveCapacity(text.count)
        while cursor < pieces.count {
            if let hit = self.bestPhrase(in: pieces, startingAt: cursor) {
                output += hit.replacementText(pieces)
                cursor = hit.nextIndex
                continue
            }
            let piece = pieces[cursor]
            if piece.isWord, let corrected = self.fuzzyReplacement(for: piece.text, languageID: languageID) {
                output += corrected
            } else {
                output += piece.text
            }
            cursor += 1
        }
        return output
    }

    private func applySubstrings(_ text: String) -> String {
        let ordered = self.terms.sorted { $0.matchText.count > $1.matchText.count }
        var result = ""
        result.reserveCapacity(text.count)
        var index = text.startIndex
        while index < text.endIndex {
            var matched: (replacement: String, end: String.Index)?
            for term in ordered {
                guard let range = text.range(
                    of: term.matchText,
                    options: [.caseInsensitive, .anchored],
                    range: index ..< text.endIndex
                ) else { continue }
                matched = (term.explicit ? term.replacement : term.matchText, range.upperBound)
                break
            }
            if let matched {
                result += matched.replacement
                index = matched.end
            } else {
                result.append(text[index])
                index = text.index(after: index)
            }
        }
        return result
    }

    private func bestPhrase(in pieces: [Piece], startingAt: Int) -> PhraseHit? {
        guard pieces[startingAt].isWord else { return nil }
        let first = pieces[startingAt].text.lowercased()
        guard let candidates = self.phrasesByFirst[first] else { return nil }
        var best: PhraseHit?
        for term in candidates {
            guard let hit = Self.match(term, pieces: pieces, startingAt: startingAt) else { continue }
            if let best, hit.wordCount <= best.wordCount { continue }
            best = hit
        }
        return best
    }

    private func fuzzyReplacement(for word: String, languageID: String) -> String? {
        let limit = word.count >= 8 ? 2 : 1
        guard word.count >= 4 else { return nil }
        guard self.cachedMisspelling(word, languageID: languageID) else { return nil }
        let folded = Array(word.lowercased())
        var best: (display: String, distance: Int)?
        var tie = false
        let lower = folded.count - limit
        let upper = folded.count + limit
        guard lower <= upper else { return nil }
        for length in lower ... upper {
            for candidate in self.fuzzyByLength[length] ?? [] {
                guard let distance = Self.editDistance(folded, candidate.folded, limit: limit), distance > 0 else { continue }
                if let current = best {
                    if distance < current.distance {
                        best = (candidate.display, distance)
                        tie = false
                    } else if distance == current.distance, candidate.display.lowercased() != current.display.lowercased() {
                        tie = true
                    }
                } else {
                    best = (candidate.display, distance)
                }
            }
        }
        guard let best, !tie else { return nil }
        return best.display
    }

    private func cachedMisspelling(_ word: String, languageID: String) -> Bool {
        let key = languageID + "\n" + word
        if let cached = self.misspellCache.values[key] { return cached }
        let value = self.isMisspelled(word, languageID)
        self.misspellCache.values[key] = value
        return value
    }

    private static func match(_ term: KeywordTerm, pieces: [Piece], startingAt: Int) -> PhraseHit? {
        var pieceIndex = startingAt
        var wordIndexes: [Int] = []
        for (offset, expected) in term.matchWords.enumerated() {
            if offset > 0 {
                guard pieceIndex < pieces.count, !pieces[pieceIndex].isWord else { return nil }
                guard pieces[pieceIndex].text.allSatisfy(\.isWhitespace) else { return nil }
                pieceIndex += 1
            }
            guard pieceIndex < pieces.count, pieces[pieceIndex].isWord else { return nil }
            guard pieces[pieceIndex].text.lowercased() == expected.lowercased() else { return nil }
            wordIndexes.append(pieceIndex)
            pieceIndex += 1
        }
        return PhraseHit(term: term, wordIndexes: wordIndexes, nextIndex: pieceIndex)
    }

    private static func pieces(in text: String) -> [Piece] {
        var pieces: [Piece] = []
        var current = ""
        var currentIsWord = false
        func flush() {
            guard !current.isEmpty else { return }
            pieces.append(Piece(text: current, isWord: currentIsWord))
            current = ""
        }
        for character in text {
            let isWord = Self.isWordCharacter(character)
            if current.isEmpty {
                currentIsWord = isWord
                current.append(character)
            } else if isWord == currentIsWord {
                current.append(character)
            } else {
                flush()
                currentIsWord = isWord
                current.append(character)
            }
        }
        flush()
        return pieces
    }

    private static func isWordCharacter(_ character: Character) -> Bool {
        if TranslationClauseSegmenter.keepsWordCharacter(character) { return true }
        return character == "'" || character == "-" || character == "’"
    }

    private static func usesSubstring(_ languageID: String) -> Bool {
        let id = languageID.lowercased()
        return id.hasPrefix("zh") || id.hasPrefix("ja") || id.hasPrefix("th")
    }

    private static func contains(_ needle: String, in text: String) -> Bool {
        if needle.contains(where: Self.isUnspacedCharacter) {
            return text.range(of: needle, options: .caseInsensitive) != nil
        }
        let pattern = "\\b\(NSRegularExpression.escapedPattern(for: needle))\\b"
        return text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    private static func isUnspacedCharacter(_ character: Character) -> Bool {
        character.unicodeScalars.contains { scalar in
            (0x4E00 ... 0x9FFF).contains(scalar.value)
                || (0x3040 ... 0x30FF).contains(scalar.value)
                || (0x0E00 ... 0x0E7F).contains(scalar.value)
                || (0xAC00 ... 0xD7AF).contains(scalar.value)
        }
    }

    static func editDistance(_ left: [Character], _ right: [Character], limit: Int) -> Int? {
        if abs(left.count - right.count) > limit { return nil }
        var previous = Array(0 ... right.count)
        for (index, leftChar) in left.enumerated() {
            var current = [index + 1]
            var rowMin = current[0]
            for (column, rightChar) in right.enumerated() {
                let cost = leftChar == rightChar ? 0 : 1
                let value = min(current[column] + 1, previous[column + 1] + 1, previous[column] + cost)
                current.append(value)
                rowMin = min(rowMin, value)
            }
            if rowMin > limit { return nil }
            previous = current
        }
        let distance = previous[right.count]
        return distance <= limit ? distance : nil
    }

    private static func spellLanguage(for languageID: String) -> String {
        let trimmed = languageID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "en" }
        return trimmed.replacingOccurrences(of: "_", with: "-")
    }

    private static func hasSpellingDictionary(_ language: String) -> Bool {
        let prefix = language.split(separator: "-").first.map(String.init)?.lowercased() ?? language.lowercased()
        return NSSpellChecker.shared.availableLanguages.contains { code in
            code.lowercased() == language.lowercased() || code.lowercased().hasPrefix(prefix)
        }
    }
}

private final class MisspellCache {
    var values: [String: Bool] = [:]
}

private struct FuzzyTarget {
    var display: String
    var folded: [Character]
}

private struct Piece {
    var text: String
    var isWord: Bool
}

private struct PhraseHit {
    var term: KeywordTerm
    var wordIndexes: [Int]
    var nextIndex: Int

    var wordCount: Int { self.wordIndexes.count }

    func replacementText(_ pieces: [Piece]) -> String {
        if self.term.explicit { return self.term.replacement }
        var text = ""
        var wordOffset = 0
        for index in pieces.indices where index >= (self.wordIndexes.first ?? 0) && index < self.nextIndex {
            if pieces[index].isWord, wordOffset < self.term.matchWords.count {
                text += self.term.matchWords[wordOffset]
                wordOffset += 1
            } else {
                text += pieces[index].text
            }
        }
        return text
    }
}

enum KeywordAnchorFolder {
    static func url() -> URL {
        AppSupportDirectory.url().appendingPathComponent("Keywords", isDirectory: true)
    }

    static func reveal() {
        let folder = self.url()
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        NSWorkspace.shared.open(folder)
    }
}

@MainActor
final class KeywordAnchorSession {
    static let shared = KeywordAnchorSession()

    private var anchor = KeywordAnchor(terms: [])

    private init() {}

    func capture(from folder: URL = KeywordAnchorFolder.url()) {
        self.anchor = KeywordAnchor(terms: KeywordTerm.load(from: folder))
    }

    func apply(_ text: String, languageID: String) -> String {
        self.anchor.apply(text, languageID: languageID)
    }

    func matchedTerms(in text: String) -> [String] {
        self.anchor.matchedTerms(in: text)
    }
}
