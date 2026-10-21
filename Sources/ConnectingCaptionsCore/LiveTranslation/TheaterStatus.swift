import Foundation

public enum TheaterStatusKind: Equatable, Sendable {
    case idle
    case listening
    case info
    case success
    case warning
    case failure

    public var usesWarningColor: Bool {
        self == .failure || self == .warning
    }
}

public struct TheaterStatus: Equatable, Sendable {
    public var text: String
    public var kind: TheaterStatusKind

    public init(text: String, kind: TheaterStatusKind) {
        self.text = text
        self.kind = kind
    }

    public static let empty = TheaterStatus(text: "", kind: .idle)

    public static func listening(_ text: String = "Listening…") -> TheaterStatus {
        TheaterStatus(text: text, kind: .listening)
    }

    public static func info(_ text: String) -> TheaterStatus {
        TheaterStatus(text: text, kind: .info)
    }

    public static func success(_ text: String) -> TheaterStatus {
        TheaterStatus(text: text, kind: .success)
    }

    public static func warning(_ text: String) -> TheaterStatus {
        TheaterStatus(text: text, kind: .warning)
    }

    public static func failure(_ text: String) -> TheaterStatus {
        TheaterStatus(text: text, kind: .failure)
    }
}

/// The line printed in a sentence's slot after its one automatic retry fails.
public enum TheaterCaptionFailure {
    public static let line = "Couldn't translate."

    public static func isLine(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines) == Self.line
    }
}
