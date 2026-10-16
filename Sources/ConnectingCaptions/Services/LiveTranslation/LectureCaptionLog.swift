import Foundation

/// One printed Theater line, the board log that holds the latest lines, and
/// the Korean / Japanese / Thai confirm rule. Clause cutting stays in
/// `TranslationClauseSegmenter`.

struct LectureCaptionEntry: Codable, Equatable, Identifiable {
    let id: UInt64
    var source: String
    var translated: String
    var wasPolished: Bool = false
    var committedAt: Date = Date()
    var speechTiming: CaptionSpeechTiming?
    var sourceLanguageID: String?
    var targetLanguageID: String?

    private enum CodingKeys: String, CodingKey {
        case id
        case source
        case translated
        case wasPolished
        case committedAt
        case speechTiming, sourceLanguageID, targetLanguageID
    }

    init(
        id: UInt64,
        source: String,
        translated: String,
        wasPolished: Bool = false,
        committedAt: Date = Date()
    ) {
        self.id = id
        self.source = source
        self.translated = translated
        self.wasPolished = wasPolished
        self.committedAt = committedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UInt64.self, forKey: .id)
        self.source = try container.decode(String.self, forKey: .source)
        self.translated = try container.decode(String.self, forKey: .translated)
        self.wasPolished = try container.decodeIfPresent(Bool.self, forKey: .wasPolished) ?? false
        self.committedAt = try container.decodeIfPresent(Date.self, forKey: .committedAt) ?? .distantPast
        self.speechTiming = try container.decodeIfPresent(CaptionSpeechTiming.self, forKey: .speechTiming)
        self.sourceLanguageID = try container.decodeIfPresent(String.self, forKey: .sourceLanguageID)
        self.targetLanguageID = try container.decodeIfPresent(String.self, forKey: .targetLanguageID)
    }
}

struct TheaterBoardSnapshot: Codable, Equatable {
    var entries: [LectureCaptionEntry]
    var nextID: UInt64
}

/// Lecture caption history: one translated line per source clause.
struct LectureCaptionLog: Equatable {
    var entries: [LectureCaptionEntry] = []
    var nextID: UInt64 = 1

    var sourceLines: [String] { self.entries.map(\.source) }
    var translatedLines: [String] { self.entries.map(\.translated) }
    var lineIDs: [UInt64] { self.entries.map(\.id) }

    var contextSourceLines: [String] {
        Array(self.sourceLines.suffix(LiveTranslationTiming.contextSentenceCount))
    }

    var captionPairs: [CaptionHistoryPair] {
        TheaterCaptionExport.pairs(from: self.entries)
    }

    var didPolishAnyLine: Bool {
        self.entries.contains(where: \.wasPolished)
    }

    /// Append a non-empty pair. Whether the sentence is a new row is
    /// `TheaterBoardAdmission`. In-place growth is `applyGrowth`.
    @discardableResult
    mutating func commit(
        source: String,
        translated: String,
        speechTiming: CaptionSpeechTiming? = nil,
        sourceLanguageID: String? = nil,
        targetLanguageID: String? = nil
    ) -> (id: UInt64, overflow: [LectureCaptionEntry])? {
        let cleanedSource = source.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedTranslation = translated.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedSource.isEmpty, !cleanedTranslation.isEmpty else { return nil }

        let id = self.nextID
        var entry = LectureCaptionEntry(id: id, source: cleanedSource, translated: cleanedTranslation)
        entry.speechTiming = speechTiming
        entry.sourceLanguageID = sourceLanguageID
        entry.targetLanguageID = targetLanguageID
        self.entries.append(entry)
        self.nextID += 1
        return (id, self.trimIfNeeded())
    }

    @discardableResult
    mutating func updateTranslated(id: UInt64, translated: String, wasPolished: Bool) -> Bool {
        let cleaned = translated.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty, let index = self.entries.firstIndex(where: { $0.id == id }) else {
            return false
        }
        self.entries[index].translated = cleaned
        self.entries[index].wasPolished = wasPolished
        return true
    }

    mutating func restore(_ snapshot: TheaterBoardSnapshot) {
        self.entries = snapshot.entries
        self.nextID = max(snapshot.nextID, (snapshot.entries.map(\.id).max() ?? 0) + 1)
    }

    /// In-place growth of one painted line ("the model." → "the model on new
    /// data."). Source and Show-as change together, and the id stays put even
    /// when a later sentence is already the last row.
    @discardableResult
    mutating func applyGrowth(id: UInt64, source: String, translated: String, speechTiming: CaptionSpeechTiming? = nil) -> Bool {
        let cleanedSource = source.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedTranslation = translated.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedSource.isEmpty,
              !cleanedTranslation.isEmpty,
              let index = self.entries.firstIndex(where: { $0.id == id })
        else { return false }
        let wordingChanged = self.entries[index].source != cleanedSource
        self.entries[index].source = cleanedSource
        self.entries[index].translated = cleanedTranslation
        self.entries[index].wasPolished = false
        // If a correction no longer aligns with timed recognizer segments, do
        // not attach the old sentence's timestamps to the new wording.
        if wordingChanged || speechTiming != nil { self.entries[index].speechTiming = speechTiming }
        return true
    }

    mutating func popLast() -> LectureCaptionEntry? {
        guard !self.entries.isEmpty else { return nil }
        return self.entries.removeLast()
    }

    @discardableResult
    mutating func trimIfNeeded() -> [LectureCaptionEntry] {
        guard self.entries.count > LiveTranslationTiming.maxCommittedLines else { return [] }
        let overflowCount = self.entries.count - LiveTranslationTiming.maxCommittedLines
        let overflow = Array(self.entries.prefix(overflowCount))
        self.entries.removeFirst(overflowCount)
        return overflow
    }
}

enum LiveTranslationConfirm {
    /// Live captions fall back to the preview promptly. Stop retains the
    /// recognizer's fuller budget for its final transcript.
    static let pauseReDecodeTimeoutNanoseconds: UInt64 = 1_000_000_000
    /// Korean, Japanese, and Thai preview ticks are weak. Pause and Stop still take the
    /// fuller 30-second decode for leftover speech. Mid-talk prints from the live stitch.
    static func requiresConfirmBeforePrint(languageID: String) -> Bool {
        switch TranslationClauseSegmenter.languageCode(from: languageID) {
        case "ko", "ja", "th":
            return true
        default:
            return false
        }
    }

    static func shouldReDecode(
        isFinal: Bool,
        isPause: Bool = false,
        languageID: String = ""
    ) -> Bool {
        guard isFinal || isPause else { return false }
        return self.requiresConfirmBeforePrint(languageID: languageID)
    }

    /// First print: keep a short greeting ("OK", "네", "ขอบคุณ") when confirm heard it.
    static func prefersFirstConfirmation(confirmed: String, heard: String) -> Bool {
        let next = confirmed.trimmingCharacters(in: .whitespacesAndNewlines)
        let current = heard.trimmingCharacters(in: .whitespacesAndNewlines)
        if next.isEmpty { return false }
        if current.isEmpty { return true }
        if next.count >= max(8, (current.count * 2) / 3) { return true }
        guard next.count <= max(current.count + 4, 8) else { return false }
        return next.compare(current, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
            || next.hasPrefix(current)
            || current.hasPrefix(next)
    }
}
