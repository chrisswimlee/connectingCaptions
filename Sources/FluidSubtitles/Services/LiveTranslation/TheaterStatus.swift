import Foundation

enum TheaterStatusKind: Equatable, Sendable {
    case idle
    case listening
    case info
    case success
    case warning
    case failure

    var usesWarningColor: Bool {
        self == .failure || self == .warning
    }
}

struct TheaterStatus: Equatable, Sendable {
    var text: String
    var kind: TheaterStatusKind

    static let empty = TheaterStatus(text: "", kind: .idle)

    static func listening(_ text: String = "Listening…") -> TheaterStatus {
        TheaterStatus(text: text, kind: .listening)
    }

    static func info(_ text: String) -> TheaterStatus {
        TheaterStatus(text: text, kind: .info)
    }

    static func success(_ text: String) -> TheaterStatus {
        TheaterStatus(text: text, kind: .success)
    }

    static func warning(_ text: String) -> TheaterStatus {
        TheaterStatus(text: text, kind: .warning)
    }

    static func failure(_ text: String) -> TheaterStatus {
        TheaterStatus(text: text, kind: .failure)
    }
}

/// The line printed in a sentence's slot after its one automatic retry fails.
enum TheaterCaptionFailure {
    static let line = "Couldn't translate."

    static func isLine(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines) == Self.line
    }
}
