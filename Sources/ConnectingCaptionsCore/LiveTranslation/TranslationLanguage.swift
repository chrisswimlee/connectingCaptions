import Foundation

public struct TranslationLanguage: Identifiable, Hashable, Sendable {
    public let id: String
    public let displayName: String
    public let appleLanguageCode: String
    public let localeLanguage: Locale.Language

    public init(id: String, displayName: String, appleLanguageCode: String, localeLanguage: Locale.Language? = nil) {
        self.id = id
        self.displayName = displayName
        self.appleLanguageCode = appleLanguageCode
        self.localeLanguage = localeLanguage ?? Locale.Language(identifier: appleLanguageCode)
    }

    public init(apple language: Locale.Language) {
        let identifier = language.minimalIdentifier
        self.id = identifier
        self.displayName = TranslationLanguageCatalog.displayName(for: language)
        self.appleLanguageCode = identifier
        self.localeLanguage = language
    }
}

public enum TranslationLanguageCatalog {
    public static let english = TranslationLanguage(id: "en", displayName: "English", appleLanguageCode: "en")
    public static let korean = TranslationLanguage(id: "ko", displayName: "Korean", appleLanguageCode: "ko")
    public static let japanese = TranslationLanguage(id: "ja", displayName: "Japanese", appleLanguageCode: "ja")
    public static let thai = TranslationLanguage(id: "th", displayName: "Thai", appleLanguageCode: "th")
    public static let arabic = TranslationLanguage(id: "ar", displayName: "Arabic", appleLanguageCode: "ar")
    public static let chinese = TranslationLanguage(id: "zh", displayName: "Chinese", appleLanguageCode: "zh")
    public static let dutch = TranslationLanguage(id: "nl", displayName: "Dutch", appleLanguageCode: "nl")
    public static let french = TranslationLanguage(id: "fr", displayName: "French", appleLanguageCode: "fr")
    public static let german = TranslationLanguage(id: "de", displayName: "German", appleLanguageCode: "de")
    public static let hindi = TranslationLanguage(id: "hi", displayName: "Hindi", appleLanguageCode: "hi")
    public static let indonesian = TranslationLanguage(id: "id", displayName: "Indonesian", appleLanguageCode: "id")
    public static let italian = TranslationLanguage(id: "it", displayName: "Italian", appleLanguageCode: "it")
    public static let polish = TranslationLanguage(id: "pl", displayName: "Polish", appleLanguageCode: "pl")
    public static let portuguese = TranslationLanguage(id: "pt", displayName: "Portuguese", appleLanguageCode: "pt")
    public static let russian = TranslationLanguage(id: "ru", displayName: "Russian", appleLanguageCode: "ru")
    public static let spanish = TranslationLanguage(id: "es", displayName: "Spanish", appleLanguageCode: "es")
    public static let turkish = TranslationLanguage(id: "tr", displayName: "Turkish", appleLanguageCode: "tr")
    public static let ukrainian = TranslationLanguage(id: "uk", displayName: "Ukrainian", appleLanguageCode: "uk")
    public static let vietnamese = TranslationLanguage(id: "vi", displayName: "Vietnamese", appleLanguageCode: "vi")

    /// Languages both Apple Translation and a Voice Engine can use.
    /// Korean and Japanese work with Apple Speech, Cohere, or Whisper.
    /// Thai works best with Apple Speech or Whisper; Nemotron Thai is experimental.
    /// Chinese is Apple's Simplified `zh`. Traditional locales share that language.
    /// Danish, Finnish, Hebrew, Malay, Norwegian, and Swedish are deliberately absent:
    /// Apple's on-device Translation framework reports every pairing for these as
    /// unsupported (verified against `LanguageAvailability`), even though Apple Speech
    /// can transcribe them. Advertising them as caption/translation languages would be
    /// a lie the first time someone tried to use them.
    public static let all: [TranslationLanguage] = [
        Self.english,
        Self.korean,
        Self.japanese,
        Self.thai,
        Self.arabic,
        Self.chinese,
        Self.dutch,
        Self.french,
        Self.german,
        Self.hindi,
        Self.indonesian,
        Self.italian,
        Self.polish,
        Self.portuguese,
        Self.russian,
        Self.spanish,
        Self.turkish,
        Self.ukrainian,
        Self.vietnamese,
    ]

    public static var languageCodeList: String {
        self.all.map { $0.id.uppercased() }.sorted().joined(separator: ", ")
    }

    public static let supportedIDs: Set<String> = Set(Self.all.map(\.id))

    /// Alphabetical names for the language menus.
    public static var menuOrder: [TranslationLanguage] {
        self.all.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }

    /// Shown under Theater language pickers when I speak is Thai and no mismatch is visible.
    public static let thaiTheaterEngineHint = "Thai speech works best with Apple Speech or Whisper."

    /// Nemotron can list Thai, but Theater should not treat that as a production default.
    public static let thaiNemotronExperimentalWarning =
        "Thai is experimental on Nemotron. Apple Speech or Whisper is the better Theater default."

    public static func theaterEngineHint(forSource source: TranslationLanguage) -> String? {
        source.id == Self.thai.id ? Self.thaiTheaterEngineHint : nil
    }

    public static func displayName(for language: Locale.Language) -> String {
        let identifier = language.minimalIdentifier
        if let name = Locale.current.localizedString(forIdentifier: identifier), !name.isEmpty {
            return name.localizedCapitalized
        }
        if let code = language.languageCode?.identifier,
           let name = Locale.current.localizedString(forLanguageCode: code),
           !name.isEmpty
        {
            return name.localizedCapitalized
        }
        return identifier
    }

    public static func languages(from supported: [Locale.Language]) -> [TranslationLanguage] {
        self.all.map { language in
            TranslationLanguage(
                id: language.id,
                displayName: language.displayName,
                appleLanguageCode: language.appleLanguageCode,
                localeLanguage: self.appleLanguage(for: language, from: supported)
            )
        }
    }

    public static func language(id: String, in available: [TranslationLanguage] = []) -> TranslationLanguage? {
        let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let normalized = trimmed.lowercased().replacingOccurrences(of: "_", with: "-")
        let prefix = String(normalized.split(separator: "-").first ?? Substring(normalized))
        let pool = available.isEmpty ? self.all : available
        return pool.first {
            let candidateID = $0.id.lowercased()
            let candidateCode = $0.appleLanguageCode.lowercased()
            return candidateID == normalized
                || candidateCode == normalized
                || candidateID == prefix
                || candidateCode == prefix
        }
    }

    public static func language(matchingSpokenID spokenID: String, in available: [TranslationLanguage] = []) -> TranslationLanguage {
        self.language(id: spokenID, in: available) ?? Self.english
    }

    /// First run captions in the spoken language. A second language is a choice, not a default.
    public static func defaultTarget(forSource source: TranslationLanguage) -> TranslationLanguage {
        source
    }

    public static func targets(excluding _: TranslationLanguage) -> [TranslationLanguage] {
        self.all
    }

    /// Prefer Apple's already-listed language (especially regionless `en`) over a constructed locale.
    public static func appleLanguage(
        for language: TranslationLanguage,
        from supported: [Locale.Language]
    ) -> Locale.Language {
        if supported.contains(where: { $0.minimalIdentifier == language.localeLanguage.minimalIdentifier }) {
            return language.localeLanguage
        }
        let code = (language.localeLanguage.languageCode?.identifier ?? language.id).lowercased()
        let matches = supported.filter { $0.languageCode?.identifier.lowercased() == code }
        if code == "en" {
            return matches.first(where: { $0.minimalIdentifier == "en" })
                ?? matches.first
                ?? language.localeLanguage
        }
        return matches.first(where: { $0.minimalIdentifier == language.appleLanguageCode })
            ?? matches.first
            ?? language.localeLanguage
    }
}

public enum TranslationListenKind: String, Sendable {
    /// Fill the Theater window. Do not type into another app.
    case captions
    /// Type the translation into the app that was focused when listening started.
    case insert
}

/// Ordered ASR hints for Theater Q&A. Whisper can auto-detect when extras are on.
public enum SpokenLanguageHints {
    public static func orderedIDs(primaryID: String, alsoHearOthers: Bool) -> [String] {
        let primary = TranslationLanguageCatalog.language(id: primaryID)?.id
            ?? TranslationLanguageCatalog.english.id
        var ids = [primary]
        if alsoHearOthers {
            for language in TranslationLanguageCatalog.all where language.id != primary {
                ids.append(language.id)
            }
        }
        return ids
    }

    /// `nil` means Whisper auto-detect. Apple Speech stays on I speak.
    public static func whisperLanguageCode(stored: String?, alsoHearOthers: Bool) -> String? {
        alsoHearOthers ? nil : stored
    }
}
