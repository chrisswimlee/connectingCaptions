import Foundation

public enum TranslationRequestKind: Equatable {
    case live
    case commit
    /// First clause of a Listen. Same mailbox slot and timeout as a later commit.
    case firstCommit

    public var occupiesCommitSlot: Bool { self != .live }
}

public protocol TranslationEngine: AnyObject {
    var name: String { get }
    func translate(_ text: String, source: TranslationLanguage, target: TranslationLanguage) async throws -> String
    func translate(
        _ text: String,
        source: TranslationLanguage,
        target: TranslationLanguage,
        kind: TranslationRequestKind
    ) async throws -> String
}

public extension TranslationEngine {
    public func translate(
        _ text: String,
        source: TranslationLanguage,
        target: TranslationLanguage,
        kind: TranslationRequestKind
    ) async throws -> String {
        try await self.translate(text, source: source, target: target)
    }
}

public struct TranslationEngineError: LocalizedError {
    public let message: String

    public init(message: String) {
        self.message = message
    }
    public var errorDescription: String? { self.message }
    public var isSuperseded: Bool { self.message == Self.supersededMessage }
    public var isCaptionRejected: Bool { self.message == Self.captionRejectedMessage }
    public var isTimeout: Bool { self.message == Self.timeoutMessage }
    public static let supersededMessage = "Superseded by a newer caption."
    public static let captionRejectedMessage = "Caption text was not safe to print."
    public static let timeoutMessage = "Apple Translation timed out."
    public static var superseded: TranslationEngineError { TranslationEngineError(message: Self.supersededMessage) }
    public static var timeout: TranslationEngineError { TranslationEngineError(message: Self.timeoutMessage) }
    /// A line that failed `LiveTranslationCaptionGate.captionSafeForBoard`.
    public static var captionRejected: TranslationEngineError {
        TranslationEngineError(message: Self.captionRejectedMessage)
    }
}
