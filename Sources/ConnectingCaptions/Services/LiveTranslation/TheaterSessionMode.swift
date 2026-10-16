import Foundation

enum TheaterSessionMode: String, CaseIterable, Identifiable {
    case transcription
    case translation

    var id: String {
        self.rawValue
    }

    var displayName: String {
        switch self {
        case .transcription: return AppLanguage.text("Original language")
        case .translation: return AppLanguage.text("Translate")
        }
    }

    var help: String {
        switch self {
        case .transcription:
            return "Show what you say in the original language."
        case .translation:
            return "Translate after each sentence into a supported language. Translation Engine is Apple Translation."
        }
    }

    var showsTranslation: Bool {
        self == .translation
    }

    static func resolved(_ stored: String?) -> TheaterSessionMode {
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
