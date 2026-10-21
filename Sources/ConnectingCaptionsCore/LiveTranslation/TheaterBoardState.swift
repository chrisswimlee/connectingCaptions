import Foundation

/// One accepted caption on the Theater board.
public struct TheaterBoardRow: Equatable, Identifiable {
    public var id: UInt64
    public var source: String
    public var translated: String

    public init(id: UInt64, source: String, translated: String) {
        self.id = id
        self.source = source
        self.translated = translated
    }
}

/// The only snapshot the presenter draws. Drafts, leftovers, and pending
/// translations are not rows.
public struct TheaterBoardState: Equatable {
    public var rows: [TheaterBoardRow] = []
    public var nextID: UInt64 = 1
    public var inFlightCount: Int = 0
    public var oldestInFlightWaitMs: Int?

    public init(
        rows: [TheaterBoardRow] = [],
        nextID: UInt64 = 1,
        inFlightCount: Int = 0,
        oldestInFlightWaitMs: Int? = nil
    ) {
        self.rows = rows
        self.nextID = nextID
        self.inFlightCount = inFlightCount
        self.oldestInFlightWaitMs = oldestInFlightWaitMs
    }

    public var translatedLines: [String] { self.rows.map(\.translated) }
    public var sourceLines: [String] { self.rows.map(\.source) }
    public var lineIDs: [UInt64] { self.rows.map(\.id) }
    public var isEmpty: Bool {
        !self.rows.contains {
            !$0.translated.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    public static func make(
        translated: [String],
        sources: [String] = [],
        ids: [UInt64] = []
    ) -> TheaterBoardState {
        let rows = translated.enumerated().map { index, text in
            TheaterBoardRow(
                id: index < ids.count ? ids[index] : UInt64(index + 1),
                source: index < sources.count ? sources[index] : "",
                translated: text
            )
        }
        let next = (rows.map(\.id).max() ?? 0) + 1
        return TheaterBoardState(rows: rows, nextID: next)
    }
}
