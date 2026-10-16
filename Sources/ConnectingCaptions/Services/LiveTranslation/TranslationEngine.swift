import Foundation

enum TranslationRequestKind: Equatable {
    case live
    case commit
    /// First clause of a Listen. Same mailbox slot and timeout as a later commit.
    case firstCommit

    var occupiesCommitSlot: Bool { self != .live }
}

protocol TranslationEngine: AnyObject {
    var name: String { get }
    func translate(_ text: String, source: TranslationLanguage, target: TranslationLanguage) async throws -> String
    func translate(
        _ text: String,
        source: TranslationLanguage,
        target: TranslationLanguage,
        kind: TranslationRequestKind
    ) async throws -> String
}

extension TranslationEngine {
    func translate(
        _ text: String,
        source: TranslationLanguage,
        target: TranslationLanguage,
        kind: TranslationRequestKind
    ) async throws -> String {
        try await self.translate(text, source: source, target: target)
    }
}

struct TranslationEngineError: LocalizedError {
    let message: String
    var errorDescription: String? { self.message }
    var isSuperseded: Bool { self.message == Self.supersededMessage }
    var isCaptionRejected: Bool { self.message == Self.captionRejectedMessage }
    var isTimeout: Bool { self.message == Self.timeoutMessage }
    static let supersededMessage = "Superseded by a newer caption."
    static let captionRejectedMessage = "Caption text was not safe to print."
    static let timeoutMessage = "Apple Translation timed out."
    static var superseded: TranslationEngineError { TranslationEngineError(message: Self.supersededMessage) }
    static var timeout: TranslationEngineError { TranslationEngineError(message: Self.timeoutMessage) }
    /// A line that failed `LiveTranslationCaptionGate.captionSafeForBoard`.
    static var captionRejected: TranslationEngineError {
        TranslationEngineError(message: Self.captionRejectedMessage)
    }
}
