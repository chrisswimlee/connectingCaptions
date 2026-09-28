import Foundation

/// Maps an accepted board onto presenter rows. Caption decisions live on
/// `LiveTranslationSubscriber.advance`. This type does not peel or admit.
enum TheaterCaptionFlow {
    /// One row per accepted Show-as line. The view decides whether `source` is drawn.
    /// `limit` keeps a short review, newest last. History and export still use the board.
    static func lines(board: TheaterBoardState, limit: Int? = nil) -> [TheaterFlowLine] {
        let history = board.rows.enumerated().filter {
            !$0.element.translated.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        let mapped = history.map { index, row in
            let text = row.translated.trimmingCharacters(in: .whitespacesAndNewlines)
            let failed = TheaterCaptionFailure.isLine(text)
            return TheaterFlowLine(
                id: "c-\(row.id)",
                text: text,
                source: failed ? "" : row.source.trimmingCharacters(in: .whitespacesAndNewlines),
                isCurrent: index == history.last?.offset,
                isDraft: false,
                failed: failed
            )
        }
        guard let limit, limit > 0, mapped.count > limit else { return mapped }
        return Array(mapped.suffix(limit))
    }
}
