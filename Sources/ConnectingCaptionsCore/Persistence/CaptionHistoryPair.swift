import Foundation

public struct CaptionHistoryPair: Codable, Equatable, Sendable {
    public let source: String
    public let translated: String
    public let wasPolished: Bool
    public let committedAt: Date?
    public var speechTiming: CaptionSpeechTiming?
    public var sourceLanguageID: String?
    public var targetLanguageID: String?

    public init(source: String, translated: String, wasPolished: Bool, committedAt: Date? = nil) {
        self.source = source
        self.translated = translated
        self.wasPolished = wasPolished
        self.committedAt = committedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.source = try container.decode(String.self, forKey: .source)
        self.translated = try container.decode(String.self, forKey: .translated)
        self.wasPolished = try container.decodeIfPresent(Bool.self, forKey: .wasPolished) ?? false
        self.committedAt = try container.decodeIfPresent(Date.self, forKey: .committedAt)
        self.speechTiming = try container.decodeIfPresent(CaptionSpeechTiming.self, forKey: .speechTiming)
        self.sourceLanguageID = try container.decodeIfPresent(String.self, forKey: .sourceLanguageID)
        self.targetLanguageID = try container.decodeIfPresent(String.self, forKey: .targetLanguageID)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.source, forKey: .source)
        try container.encode(self.translated, forKey: .translated)
        try container.encode(self.wasPolished, forKey: .wasPolished)
        try container.encodeIfPresent(self.committedAt, forKey: .committedAt)
        try container.encodeIfPresent(self.speechTiming, forKey: .speechTiming)
        try container.encodeIfPresent(self.sourceLanguageID, forKey: .sourceLanguageID)
        try container.encodeIfPresent(self.targetLanguageID, forKey: .targetLanguageID)
    }

    private enum CodingKeys: String, CodingKey {
        case source, translated, wasPolished, committedAt, speechTiming, sourceLanguageID, targetLanguageID
    }
}
