import CryptoKit
import Foundation

/// Theater caption policy for a fleet. Names, transcripts, API keys, and history stay out.
nonisolated struct FleetSettingsDocument: Equatable, Sendable {
    static let allowedKeys: Set<String> = [
        "appearance",
        "captionSize",
        "captionSpacing",
        "highContrast",
        "iSpeak",
        "presentation",
        "product",
        "showAs",
        "spokenLine",
        "typeface",
        "voiceEngine",
    ]

    var product: String
    var spokenLine: String?
    var captionSize: Int?
    var captionSpacing: Int?
    var typeface: String?
    var appearance: String?
    var highContrast: Bool?
    var presentation: String?
    var iSpeak: String?
    var showAs: String?
    var voiceEngine: String?

    enum Failure: Equatable, LocalizedError {
        case malformed
        case wrongProduct
        case retainedContent([String])
        case invalidValue(String)

        var errorDescription: String? {
            "This file is not a caption policy fluidSubtitles can use. Ask IT for a new file."
        }

        var logDetail: String {
            switch self {
            case .malformed:
                return "malformed"
            case .wrongProduct:
                return "wrong product"
            case let .retainedContent(keys):
                return "retained \(keys.joined(separator: ", "))"
            case let .invalidValue(key):
                return "invalid \(key)"
            }
        }
    }

    static func capture(from settings: SettingsStore) -> FleetSettingsDocument {
        FleetSettingsDocument(
            product: CommercialLicense.productID,
            spokenLine: settings.theaterSpokenLineMode.rawValue,
            captionSize: settings.presenterFontSize,
            captionSpacing: settings.theaterCaptionSpacing,
            typeface: settings.presenterFontFamily,
            appearance: settings.theaterAppearance,
            highContrast: settings.theaterHighContrast,
            presentation: settings.theaterPresentationStyle,
            iSpeak: settings.translationSourceLanguageID,
            showAs: settings.translationTargetLanguageID,
            voiceEngine: settings.selectedSpeechModel.rawValue
        )
    }

    static func decode(_ data: Data) throws -> FleetSettingsDocument {
        let object = try JSONSerialization.jsonObject(with: data)
        guard let fields = object as? [String: Any] else { throw Failure.malformed }
        let unknown = Set(fields.keys).subtracting(self.allowedKeys).sorted()
        guard unknown.isEmpty else { throw Failure.retainedContent(unknown) }
        let decoder = JSONDecoder()
        guard let document = try? decoder.decode(FleetSettingsDocument.self, from: data) else {
            throw Failure.malformed
        }
        guard document.product == CommercialLicense.productID else { throw Failure.wrongProduct }
        _ = try document.resolved()
        return document
    }

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }

    func apply(to settings: SettingsStore) throws {
        let resolved = try self.resolved()
        if let spokenLine = resolved.spokenLine {
            settings.theaterSpokenLineMode = spokenLine
        }
        if let captionSize = resolved.captionSize {
            settings.presenterFontSize = captionSize
        }
        if let captionSpacing = resolved.captionSpacing {
            settings.theaterCaptionSpacing = captionSpacing
        }
        if let typeface = resolved.typeface {
            settings.presenterFontFamily = typeface
        }
        if let appearance = resolved.appearance {
            settings.theaterAppearance = appearance
        }
        if let highContrast = resolved.highContrast {
            settings.theaterHighContrast = highContrast
        }
        if let presentation = resolved.presentation {
            settings.theaterPresentationStyle = presentation
        }
        if let iSpeak = resolved.iSpeak {
            settings.translationSourceLanguageID = iSpeak
        }
        if let showAs = resolved.showAs {
            settings.translationTargetLanguageID = showAs
        }
        if let voiceEngine = resolved.voiceEngine {
            settings.selectedSpeechModel = voiceEngine
        }
    }

    static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private struct Resolved {
        var spokenLine: TheaterSpokenLineMode?
        var captionSize: Int?
        var captionSpacing: Int?
        var typeface: String?
        var appearance: String?
        var highContrast: Bool?
        var presentation: String?
        var iSpeak: String?
        var showAs: String?
        var voiceEngine: SettingsStore.SpeechModel?
    }

    private func resolved() throws -> Resolved {
        var resolved = Resolved()
        if let spokenLine = self.spokenLine {
            guard ["off", "afterPause", "whileTalking"].contains(spokenLine) else {
                throw Failure.invalidValue("spokenLine")
            }
            resolved.spokenLine = TheaterSpokenLineMode.resolved(spokenLine)
        }
        if let captionSize = self.captionSize {
            guard SettingsStore.presenterFontSizeRange.contains(captionSize) else {
                throw Failure.invalidValue("captionSize")
            }
            resolved.captionSize = captionSize
        }
        if let captionSpacing = self.captionSpacing {
            guard TheaterCaptionSpacing.range.contains(captionSpacing) else {
                throw Failure.invalidValue("captionSpacing")
            }
            resolved.captionSpacing = captionSpacing
        }
        if let typeface = self.typeface {
            guard TheaterTypeface(rawValue: typeface) != nil else {
                throw Failure.invalidValue("typeface")
            }
            resolved.typeface = typeface
        }
        if let appearance = self.appearance {
            guard TheaterAppearance(rawValue: appearance) != nil else {
                throw Failure.invalidValue("appearance")
            }
            resolved.appearance = appearance
        }
        if let highContrast = self.highContrast {
            resolved.highContrast = highContrast
        }
        if let presentation = self.presentation {
            guard TheaterPresentationStyle(rawValue: presentation) != nil else {
                throw Failure.invalidValue("presentation")
            }
            resolved.presentation = presentation
        }
        if let iSpeak = self.iSpeak {
            guard let language = TranslationLanguageCatalog.language(id: iSpeak) else {
                throw Failure.invalidValue("iSpeak")
            }
            resolved.iSpeak = language.id
        }
        if let showAs = self.showAs {
            guard let language = TranslationLanguageCatalog.language(id: showAs) else {
                throw Failure.invalidValue("showAs")
            }
            resolved.showAs = language.id
        }
        if let voiceEngine = self.voiceEngine {
            guard let model = SettingsStore.SpeechModel(rawValue: voiceEngine) else {
                throw Failure.invalidValue("voiceEngine")
            }
            resolved.voiceEngine = model
        }
        return resolved
    }
}

extension FleetSettingsDocument: Codable {
    enum CodingKeys: String, CodingKey {
        case product
        case spokenLine
        case captionSize
        case captionSpacing
        case typeface
        case appearance
        case highContrast
        case presentation
        case iSpeak
        case showAs
        case voiceEngine
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.product = try container.decode(String.self, forKey: .product)
        self.spokenLine = try container.decodeIfPresent(String.self, forKey: .spokenLine)
        self.captionSize = try container.decodeIfPresent(Int.self, forKey: .captionSize)
        self.captionSpacing = try container.decodeIfPresent(Int.self, forKey: .captionSpacing)
        self.typeface = try container.decodeIfPresent(String.self, forKey: .typeface)
        self.appearance = try container.decodeIfPresent(String.self, forKey: .appearance)
        self.highContrast = try container.decodeIfPresent(Bool.self, forKey: .highContrast)
        self.presentation = try container.decodeIfPresent(String.self, forKey: .presentation)
        self.iSpeak = try container.decodeIfPresent(String.self, forKey: .iSpeak)
        self.showAs = try container.decodeIfPresent(String.self, forKey: .showAs)
        self.voiceEngine = try container.decodeIfPresent(String.self, forKey: .voiceEngine)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.product, forKey: .product)
        try container.encodeIfPresent(self.spokenLine, forKey: .spokenLine)
        try container.encodeIfPresent(self.captionSize, forKey: .captionSize)
        try container.encodeIfPresent(self.captionSpacing, forKey: .captionSpacing)
        try container.encodeIfPresent(self.typeface, forKey: .typeface)
        try container.encodeIfPresent(self.appearance, forKey: .appearance)
        try container.encodeIfPresent(self.highContrast, forKey: .highContrast)
        try container.encodeIfPresent(self.presentation, forKey: .presentation)
        try container.encodeIfPresent(self.iSpeak, forKey: .iSpeak)
        try container.encodeIfPresent(self.showAs, forKey: .showAs)
        try container.encodeIfPresent(self.voiceEngine, forKey: .voiceEngine)
    }
}
