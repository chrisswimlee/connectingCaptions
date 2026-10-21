import Foundation

/// Platform-neutral logger. The macOS app wires this to `DebugLogger`.
public enum CoreLog {
    public static var debugHandler: (@Sendable (String, String) -> Void)?
    public static var infoHandler: (@Sendable (String, String) -> Void)?
    public static var warningHandler: (@Sendable (String, String) -> Void)?
    public static var errorHandler: (@Sendable (String, String) -> Void)?

    public static func debug(_ message: String, source: String = "Core") {
        debugHandler?(message, source)
    }

    public static func info(_ message: String, source: String = "Core") {
        infoHandler?(message, source)
    }

    public static func warning(_ message: String, source: String = "Core") {
        warningHandler?(message, source)
    }

    public static func error(_ message: String, source: String = "Core") {
        errorHandler?(message, source)
    }
}
