import Foundation

struct TranslationPairKey: Equatable, Hashable {
    let sourceID: String
    let targetID: String
    let bidirectional: Bool
    let mode: String

    @MainActor
    static func current() -> Self {
        Self(
            sourceID: SpokenLanguageResolver.sourceLanguage().id,
            targetID: SpokenLanguageResolver.targetLanguage().id,
            bidirectional: SpokenLanguageResolver.isDynamicPairingEnabled(),
            mode: SettingsStore.shared.theaterSessionMode.rawValue
        )
    }
}

/// A pair can change A → B → A while the first request is still suspended.
/// Comparing languages alone would accept that old result; the revision rejects it.
struct TranslationPairCheck {
    struct Request: Equatable {
        let pair: TranslationPairKey
        let revision: UInt64
    }

    private var revision: UInt64 = 0

    mutating func begin(pair: TranslationPairKey) -> Request {
        self.revision &+= 1
        return Request(pair: pair, revision: self.revision)
    }

    mutating func invalidate() {
        self.revision &+= 1
    }

    func accepts(_ request: Request, currentPair: TranslationPairKey) -> Bool {
        request.revision == self.revision && request.pair == currentPair
    }
}
