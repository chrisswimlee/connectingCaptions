import Foundation

public enum TheaterSessionMode: String, CaseIterable, Identifiable {
    case transcription
    case translation

    public var id: String {
        self.rawValue
    }

    public var displayName: String {
        switch self {
        case .transcription: return "Captions only"
        case .translation: return "Translate"
        }
    }

    public var help: String {
        switch self {
        case .transcription:
            return "What you say appears in the language you speak."
        case .translation:
            return "Each sentence you say appears in the Show as language."
        }
    }

    public var showsTranslation: Bool {
        self == .translation
    }

    public static func resolved(_ stored: String?) -> TheaterSessionMode {
        switch stored?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "" {
        case "transcription", "voice", "watch":
            return .transcription
        case "translation", "lectern", "":
            return .translation
        default:
            return Self(rawValue: stored ?? "") ?? .translation
        }
    }
}
