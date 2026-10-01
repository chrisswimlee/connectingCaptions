import XCTest
@testable import ConnectingCaptions_Debug

final class TheaterInboxTests: XCTestCase {
    func testOpenSpeechStaysInTheInbox() {
        let inbox = TheaterInbox.snapshot(
            waiting: [],
            open: "Then we applied it to",
            printed: ["Today we trained the model."],
            languageID: "en"
        )
        XCTAssertEqual(inbox.lines, ["Then we applied it to"])
        XCTAssertTrue(inbox.openTail)
    }

    func testWaitingSentenceAndOpenTailBothShow() {
        let inbox = TheaterInbox.snapshot(
            waiting: ["Today we trained the model."],
            open: "Then we applied it to",
            printed: [],
            languageID: "en"
        )
        XCTAssertEqual(inbox.lines, [
            "Today we trained the model.",
            "Then we applied it to"
        ])
        XCTAssertTrue(inbox.openTail)
    }

    func testFinishedWaitingLineIsNotAnOpenTail() {
        let inbox = TheaterInbox.snapshot(
            waiting: ["Today we trained the model."],
            open: "",
            printed: [],
            languageID: "en"
        )
        XCTAssertEqual(inbox.lines, ["Today we trained the model."])
        XCTAssertFalse(inbox.openTail)
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
        XCTAssertTrue(
            TheaterInbox.snapshot(
                waiting: ["Today we trained the model."],
                open: "Today we trained the model. Then we applied it to",
                printed: ["Today we trained the model."],
                languageID: "en"
            ).openTail
        )
    }

    func testInboxKeepsOnlyTheLastFewLines() {
        let waiting = (1...6).map { "Sentence \($0)." }
        let inbox = TheaterInbox.snapshot(
            waiting: waiting,
            open: "still talking",
            printed: [],
            languageID: "en"
        )
        XCTAssertEqual(inbox.lines, [
            "Sentence 4.",
            "Sentence 5.",
            "Sentence 6.",
            "still talking"
        ])
        XCTAssertTrue(inbox.openTail)
    }

    func testEmptyInboxWhenNothingIsWaiting() {
        let inbox = TheaterInbox.snapshot(waiting: [], open: "   ", printed: [], languageID: "en")
        XCTAssertEqual(inbox.lines, [])
        XCTAssertFalse(inbox.openTail)
    }
}
