import XCTest
@testable import ConnectingCaptions_Debug

/// The Minute Lessons "AI Explained in a Minute" Listen, replayed from the
/// ASR partials in `Fixtures/TheaterYouTubeAIMinute.txt`.
@MainActor
final class TheaterYouTubeReplayTests: XCTestCase {
    private var originalSource: String?
    private var originalTarget: String?

    override func setUp() async throws {
        try await super.setUp()
        let settings = SettingsStore.shared
        self.originalSource = settings.translationSourceLanguageID
        self.originalTarget = settings.translationTargetLanguageID
        settings.translationSourceLanguageID = "en"
        settings.translationTargetLanguageID = "ko"
    }

    override func tearDown() async throws {
        let settings = SettingsStore.shared
        if let source = self.originalSource {
            settings.translationSourceLanguageID = source
        }
        if let target = self.originalTarget {
            settings.translationTargetLanguageID = target
        }
        try await super.tearDown()
    }

    func testYouTubeMinuteDoesNotReprintOrSplitSentences() async throws {
        let ticks = try Self.fixtureTicks()
        let subscriber = Self.makeSubscriber()
        for tick in ticks {
            subscriber.handlePartial(tick.text)
            if tick.hold {
                subscriber.noteSilenceHold()
                await subscriber.waitForIdleForTesting()
            }
        }
        _ = await subscriber.translateFinal("")
        await subscriber.waitForIdleForTesting()

        let rows = subscriber.committedSourceLines
        XCTAssertFalse(rows.isEmpty)
        XCTAssertLessThanOrEqual(rows.count, 11, rows.joined(separator: "\n"))
        for row in rows {
            XCTAssertFalse(row.hasSuffix("...") || row.hasSuffix("…"), row)
            let first = row.split(whereSeparator: { $0.isWhitespace }).first.map(String.init) ?? ""
            XCTAssertFalse(first.first?.isLowercase == true, row)
        }
        for index in rows.indices {
            let row = rows[index]
            for earlier in rows[..<index] {
                XCTAssertFalse(
                    TranslationClauseSegmenter.isInPlaceGrowth(previous: earlier, incoming: row)
                        || TranslationClauseSegmenter.isTailRevisionGrowth(previous: earlier, incoming: row)
                        || TranslationClauseSegmenter.shouldReviseCommitted(
                            previous: earlier,
                            incoming: row,
                            languageID: "en"
                        ),
                    "reprinted \(earlier) as \(row)"
                )
            }
            if index >= 2 {
                for pair in 0..<(index - 1) {
                    let joined = rows[pair] + " " + rows[pair + 1]
                    XCTAssertFalse(
                        TranslationClauseSegmenter.isSameClause(joined, row)
                            || TranslationClauseSegmenter.isInPlaceGrowth(previous: joined, incoming: row)
                            || TranslationClauseSegmenter.shouldReviseCommitted(
                                previous: joined,
                                incoming: row,
                                languageID: "en"
                            ),
                        "rejoined \(joined) as \(row)"
                    )
                }
            }
        }
        for reference in Self.youtubeSentences {
            XCTAssertTrue(
                Self.board(rows, covers: reference),
                "missing \(reference)\n\(rows.joined(separator: "\n"))"
            )
        }
    }

    func testALaterPeriodSplitsThePrintedLine() async {
        let subscriber = Self.makeSubscriber()
        let joined = "Stephen Curry just gave the warriors something that could be more valuable than the extra $20 million he left on the table, time."
        subscriber.handlePartial(joined)
        subscriber.handlePartial(joined)
        await subscriber.waitForIdleForTesting()
        XCTAssertEqual(subscriber.committedSourceLines, [joined])

        let corrected = "Stephen Curry just gave the warriors something that could be more valuable than the extra $20 million he left on the table. Time. Curry agreed to a two year, $116 million extension."
        subscriber.handlePartial(corrected)
        subscriber.handlePartial(corrected)
        await subscriber.waitForIdleForTesting()
        let rows = subscriber.committedSourceLines
        XCTAssertTrue(
            rows.contains { TranslationClauseSegmenter.normalizedKey($0) == "time" },
            rows.joined(separator: "\n")
        )
        XCTAssertTrue(
            rows.contains {
                TranslationClauseSegmenter.normalizedKey($0).hasSuffix("left on the table")
            },
            rows.joined(separator: "\n")
        )
    }

    func testWindowResetAfterAnOpenEllipsisStaysOneSentence() async {
        let subscriber = Self.makeSubscriber()
        let open = "AI systems are fed fast amounts of data, which they..."
        subscriber.handlePartial(open)
        subscriber.handlePartial(open)
        subscriber.noteSilenceHold()
        await subscriber.waitForIdleForTesting()
        XCTAssertFalse(
            subscriber.committedSourceLines.contains { $0.localizedCaseInsensitiveContains("which they") },
            subscriber.committedSourceLines.joined(separator: "\n")
        )

        let continued = "AI systems are fed fast amounts of data, which they... Used to make decisions, recognize patterns, and perform tasks. There are several subsets of AI."
        subscriber.handlePartial(continued)
        subscriber.handlePartial(continued)
        await subscriber.waitForIdleForTesting()
        let rows = subscriber.committedSourceLines
        XCTAssertTrue(
            rows.contains {
                TranslationClauseSegmenter.normalizedKey($0).contains("which they used to make decisions")
            },
            rows.joined(separator: "\n")
        )
        XCTAssertFalse(
            rows.contains { row in
                row.split(whereSeparator: \.isWhitespace).first?.first?.isLowercase == true
            },
            rows.joined(separator: "\n")
        )
    }

    func testLowercaseUtteranceAfterALongQuietStaysItsOwnRow() async {
        let subscriber = Self.makeSubscriber()
        subscriber.handlePartial("Please take a seat near the door.")
        subscriber.handlePartial("Please take a seat near the door.")
        subscriber.noteSilenceHold()
        await subscriber.waitForIdleForTesting()
        XCTAssertEqual(subscriber.committedSourceLines, ["Please take a seat near the door."])

        try? await Task.sleep(nanoseconds: 8_200_000_000)

        subscriber.handlePartial("near the door before the lecture starts.")
        subscriber.handlePartial("near the door before the lecture starts.")
        subscriber.noteSilenceHold()
        await subscriber.waitForIdleForTesting()
        XCTAssertEqual(
            subscriber.committedSourceLines.count,
            2,
            subscriber.committedSourceLines.joined(separator: " | ")
        )
        XCTAssertEqual(subscriber.committedSourceLines[0], "Please take a seat near the door.")
        XCTAssertTrue(
            subscriber.committedSourceLines[1].localizedCaseInsensitiveContains("before the lecture")
        )
    }

    private static func makeSubscriber() -> LiveTranslationSubscriber {
        let engine = FakeTranslationEngine()
        engine.result = .success("번역")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        let subscriber = LiveTranslationSubscriber(translator: engine, archive: LectureCaptionArchive(url: url))
        subscriber.beginListening()
        return subscriber
    }

    private struct FixtureTick {
        var text: String
        var hold: Bool
    }

    private static func fixtureTicks() throws -> [FixtureTick] {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/TheaterYouTubeAIMinute.txt")
        let raw = try String(contentsOf: url, encoding: .utf8)
        var ticks: [FixtureTick] = []
        for line in raw.split(separator: "\n", omittingEmptySubsequences: false) {
            let text = String(line)
            if text.isEmpty || text.hasPrefix("#") { continue }
            if text == "HOLD" {
                guard let last = ticks.indices.last else { continue }
                ticks[last].hold = true
                continue
            }
            ticks.append(FixtureTick(text: text, hold: false))
        }
        return ticks
    }

    private static let youtubeSentences = [
        "AI is something that if you aren't paying attention it could easily take your job your spouse and your current way of life.",
        "In other words at some point coming sooner than we all thought it will change everything.",
        "Artificial intelligence makes it possible for machines to learn from experience adjust to new inputs and perform humanlike tasks.",
        "In other words if an AI program is taught the right information and given the same tools as humans the sky is the limit for what it can do.",
        "Many people don't realize AI already impacts us powering many tools we use daily from search engines that predict what we're looking for to voice assistants like Siri and Alexa and even recommendations on Netflix.",
        "Then there are new generative AI tools like chat GPT which expand the Horizon of a true computer assistant.",
        "AI systems are fed vast amounts of data which they use to make decisions recognize patterns and perform tasks.",
        "There are several subsets of AI like machine learning that uses algorithms to parse data learn from it and decide or predict.",
        "Another subset is deep learning which is similar to a neural network which both focus on modeling behaviors of the human brain.",
        "As AI evolves ethical considerations grow questions about privacy autonomy and job displacement challenge us to use AI responsibly.",
    ]

    /// In-order word overlap. ASR may say "they're" or "human like"; 72% still
    /// means the sentence landed somewhere on the board.
    private static func board(_ rows: [String], covers reference: String) -> Bool {
        let ref = TranslationClauseSegmenter.normalizedKey(reference).split(separator: " ").map(String.init)
        guard !ref.isEmpty else { return true }
        var candidates = rows
        if rows.count >= 2 {
            for index in 0..<(rows.count - 1) {
                candidates.append(rows[index] + " " + rows[index + 1])
            }
        }
        let best = candidates.map { row -> Double in
            let hay = TranslationClauseSegmenter.normalizedKey(row).split(separator: " ").map(String.init)
            var index = 0
            var hits = 0
            for word in ref {
                guard index < hay.count, let found = hay[index...].firstIndex(of: word) else { continue }
                hits += 1
                index = found + 1
            }
            return Double(hits) / Double(ref.count)
        }.max() ?? 0
        return best >= 0.72
    }
}
