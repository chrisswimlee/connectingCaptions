import XCTest
@testable import FluidSubtitles_Debug

final class TheaterInboxTests: XCTestCase {
    func testOpenSpeechStaysInTheInbox() {
        let lines = TheaterInbox.lines(
            waiting: [],
            open: "Then we applied it to",
            printed: ["Today we trained the model."],
            languageID: "en"
        )
        XCTAssertEqual(lines, ["Then we applied it to"])
    }

    func testWaitingSentenceAndOpenTailBothShow() {
        let lines = TheaterInbox.lines(
            waiting: ["Today we trained the model."],
            open: "Then we applied it to",
            printed: [],
            languageID: "en"
        )
        XCTAssertEqual(lines, [
            "Today we trained the model.",
            "Then we applied it to"
        ])
    }

    func testPrintedSentenceLeavesTheInbox() {
        let lines = TheaterInbox.lines(
            waiting: ["Today we trained the model."],
            open: "Today we trained the model. Then we applied it to",
            printed: ["Today we trained the model."],
            languageID: "en"
        )
        XCTAssertEqual(lines, ["Then we applied it to"])
        XCTAssertFalse(lines.contains("Today we trained the model."))
    }

    func testInboxKeepsOnlyTheLastFewLines() {
        let waiting = (1...6).map { "Sentence \($0)." }
        let lines = TheaterInbox.lines(
            waiting: waiting,
            open: "still talking",
            printed: [],
            languageID: "en"
        )
        XCTAssertEqual(lines, [
            "Sentence 4.",
            "Sentence 5.",
            "Sentence 6.",
            "still talking"
        ])
    }

    func testEmptyInboxWhenNothingIsWaiting() {
        XCTAssertEqual(
            TheaterInbox.lines(waiting: [], open: "   ", printed: [], languageID: "en"),
            []
        )
    }
}
