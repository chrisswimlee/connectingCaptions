import Foundation

nonisolated public enum LiveTranslationTiming {
    /// English confirm after a finished ending.
    public static let completeSettleNanoseconds: UInt64 = 500_000_000
    /// English open-thought silence before a forced cut. The room is already
    /// quiet for the 400 ms silence hold and the 400 ms end-of-utterance hold
    /// before this starts, so this is the extra wait the audience feels.
    public static let openSettleNanoseconds: UInt64 = 1_200_000_000
    /// Brief hold after end-of-utterance so the last ASR tick can land.
    public static let eouHoldNanoseconds: UInt64 = 400_000_000
    /// Quiet gap after the last wording of a lone finished sentence. A revision
    /// restarts it. The sentence prints when this gap passes, without waiting
    /// for the next sentence.
    public static let loneSentencePrintNanoseconds: UInt64 = 220_000_000
    /// Partials are de-duplicated, so a quiet gap only means the engine re-heard
    /// the same text once it outlasts that engine's own update cadence (0.2–1 s).
    public static let loneSentenceCadenceFactor = 1.5
    public static let loneSentenceMaxNanoseconds: UInt64 = 1_500_000_000
    /// A gap longer than this is a pause, not the engine's update cadence.
    public static let partialCadenceMaxSeconds: TimeInterval = 2.0

    public static func loneSentenceSettleNanoseconds(partialCadence: TimeInterval) -> UInt64 {
        guard partialCadence > 0 else { return self.loneSentencePrintNanoseconds }
        let scaled = UInt64(partialCadence * self.loneSentenceCadenceFactor * 1_000_000_000)
        return min(max(scaled, self.loneSentencePrintNanoseconds), self.loneSentenceMaxNanoseconds)
    }
    public static let minPauseFinalizeCharacters = 22
    public static let minPauseFinalizeWords = 4
    /// Thai needs a real clause, not a few syllables.
    public static let minPauseFinalizeCharactersThai = 22
    /// Korean/Japanese pause-cut. Same character floor as other languages,
    /// so a real leftover does not wait for a long run-on.
    public static let minPauseFinalizeCharactersVerbFinal = 22
    public static let maxDraftCharacters = 240
    /// Floor for a pause-cut so a leftover is a clause, not two words.
    public static let followAlongWords = 8
    /// Pause-finalize only this much so a long unpunctuated talk is not one dump.
    public static let maxLineWords = 12
    public static let maxLineCharacters = 80
    public static let contextSentenceCount = 4
    /// Recent lines the board can still show. A tall window fills from this
    /// list and the presenter can scroll back a few minutes. Older lines stay
    /// in the session record for History and export.
    public static let visibleTheaterLines = 48
    public static let maxCommittedLines = visibleTheaterLines
    /// Leftover peel runs on every speech update. It uses this recent
    /// suffix, not the whole board, so a full-screen talk stays inside one tick.
    public static let peelWindowLines = 12
    /// Leftover peel and last-4 MT priors. Older clauses drop as new ones commit.
    /// Sized off `peelWindowLines`, not the Theater board, since `listenHistory`
    /// never needs more than the largest suffix its consumers take.
    public static let maxListenHistory = contextSentenceCount + peelWindowLines
    /// After this much silence, skip ASR ticks and start a new e2e measurement.
    public static let silenceHoldNanoseconds: UInt64 = 400_000_000
    public static let silenceHoldSeconds: TimeInterval = 0.4
    /// A commit MT call must fail, not hang. Warmup runs before the first
    /// Listen, so the first caption uses the same mailbox timeout as the rest.
    /// A hung call must not hold later sentences.
    public static let translateClauseTimeoutNanoseconds: UInt64 = 7_000_000_000
    /// A hung commit fails here instead of blocking the board.
    public static let commitMailboxTimeoutNanoseconds: UInt64 = 7_000_000_000
    public static let liveMailboxTimeoutNanoseconds: UInt64 = 1_500_000_000
    /// Visually separates captions that finished behind one slow ordered slot.
    /// A normal next caption still publishes as soon as its translation lands.
    public static let orderedCatchUpGapNanoseconds: UInt64 = 180_000_000

    public static func mailboxTimeoutNanoseconds(for kind: TranslationRequestKind) -> UInt64 {
        switch kind {
        case .live:
            return Self.liveMailboxTimeoutNanoseconds
        case .firstCommit, .commit:
            return Self.commitMailboxTimeoutNanoseconds
        }
    }

    public static func completeSettleNanoseconds(languageID: String) -> UInt64 {
        switch TranslationClauseSegmenter.languageCode(from: languageID) {
        case "ko", "ja":
            return 1_000_000_000
        case "th":
            return 800_000_000
        default:
            return Self.completeSettleNanoseconds
        }
    }

    public static func openSettleNanoseconds(languageID: String) -> UInt64 {
        switch TranslationClauseSegmenter.languageCode(from: languageID) {
        case "ko", "ja":
            return 2_000_000_000
        case "th":
            return 1_500_000_000
        default:
            return Self.openSettleNanoseconds
        }
    }
}
