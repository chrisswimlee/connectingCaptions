import Foundation

/// Speech this Listen has heard that is not on the Theater board yet.
/// The Pop-up task bar shows the last few of these lines. A line already
/// printed is left out, so the board receives it once.
enum TheaterInbox {
    static let maxLines = 4

    /// Heard lines for the task bar. `openTail` is true only when the last
    /// line is speech that has not finished. A finished sentence waiting its
    /// turn leaves it false.
    struct Snapshot: Equatable {
        var lines: [String]
        var openTail: Bool
    }

    static func lines(
        waiting: [String],
        open: String,
        printed: [String],
        languageID: String
    ) -> [String] {
        self.snapshot(
            waiting: waiting,
            open: open,
            printed: printed,
            languageID: languageID
        ).lines
    }

    static func snapshot(
        waiting: [String],
        open: String,
        printed: [String],
        languageID: String
    ) -> Snapshot {
        let printed = printed
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        var result: [String] = []
        for raw in waiting {
            let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            if self.alreadyShown(text, in: printed) || self.alreadyShown(text, in: result) {
                continue
            }
            result.append(text)
        }
        let tail = TranslationClauseSegmenter.leftoverTail(
            open,
            already: printed + result,
            languageID: languageID
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        var openTail = false
        if !tail.isEmpty,
           !self.alreadyShown(tail, in: printed),
           !self.alreadyShown(tail, in: result)
        {
            result.append(tail)
            openTail = true
        }
        if result.count > Self.maxLines {
            result = Array(result.suffix(Self.maxLines))
        }
        if result.isEmpty {
            openTail = false
        }
        return Snapshot(lines: result, openTail: openTail)
    }

    private static func alreadyShown(_ text: String, in lines: [String]) -> Bool {
        lines.contains { TranslationClauseSegmenter.isSameClause($0, text) }
    }
}
