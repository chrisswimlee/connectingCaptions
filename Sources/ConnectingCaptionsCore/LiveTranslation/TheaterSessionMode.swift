import Foundation

public enum TheaterSessionMode: String, CaseIterable, Identifiable {
    case transcription
    case translation

    public var id: String {
        self.rawValue
    }

    public var displayName: String {
        switch self {
        case .transcription: return "Original language"
        case .translation: return "Translate"
        }
    }

    public var help: String {
        switch self {
        case .transcription:
            return "Show what you say in the original language."
        case .translation:
            return "Translate after each sentence into a supported language. Translation Engine is Apple Translation."
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
