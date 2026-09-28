import XCTest
@testable import FluidSubtitles_Debug

final class QuickTranslateInsertTests: XCTestCase {
    func testShortcutArmsTheBarUntilTheInsertSessionJoins() {
        var session = QuickTranslateInsertSession(armed: true)
        XCTAssertEqual(
            session.note(listenKind: nil, isSessionActive: false, isFinishing: false),
            .starting
        )
        XCTAssertEqual(
            session.note(listenKind: .insert, isSessionActive: true, isFinishing: false),
            .listening
        )
        XCTAssertEqual(
            session.note(listenKind: .insert, isSessionActive: false, isFinishing: true),
            .typing
        )
        XCTAssertEqual(
            session.note(listenKind: nil, isSessionActive: false, isFinishing: false),
            .hidden
        )
        XCTAssertFalse(session.armed)
    }

    func testEscapeBeforeListenHidesTheBar() {
        var session = QuickTranslateInsertSession(armed: true)
        _ = session.note(listenKind: nil, isSessionActive: false, isFinishing: false)
        session.disarm()
        XCTAssertEqual(
            session.note(listenKind: nil, isSessionActive: false, isFinishing: false),
            .hidden
        )
    }

    func testCaptionListenDoesNotShowTheInsertBar() {
        var session = QuickTranslateInsertSession(armed: true)
        XCTAssertEqual(
            session.note(listenKind: .captions, isSessionActive: true, isFinishing: false),
            .hidden
        )
        XCTAssertFalse(session.armed)
    }

    func testBarShowsHeardSpeechUntilShowAsIsReady() {
        let waiting = QuickTranslateInsert.chip(
            phase: .listening,
            activation: .hold,
            sourceName: "English",
            targetName: "Korean",
            sameLanguage: false,
            ready: "",
            showAs: "",
            spoken: "hello there"
        )
        XCTAssertEqual(waiting.title, "English → Korean")
        XCTAssertEqual(waiting.line, "hello there")
        XCTAssertFalse(waiting.lineIsReady)

        let ready = QuickTranslateInsert.chip(
            phase: .listening,
            activation: .hold,
            sourceName: "English",
            targetName: "Korean",
            sameLanguage: false,
            ready: "",
            showAs: "안녕하세요.",
            spoken: "hello there"
        )
        XCTAssertEqual(ready.line, "안녕하세요.")
        XCTAssertTrue(ready.lineIsReady)
    }

    func testEmptyHoldBarTellsYouToRelease() {
        let chip = QuickTranslateInsert.chip(
            phase: .listening,
            activation: .hold,
            sourceName: "English",
            targetName: "Japanese",
            sameLanguage: false,
            ready: "",
            showAs: "  ",
            spoken: ""
        )
        XCTAssertEqual(chip.line, "Speak. Release to type.")
        XCTAssertFalse(chip.lineIsReady)
    }

    func testSameLanguageBarTypesTheSpokenLine() {
        let chip = QuickTranslateInsert.chip(
            phase: .listening,
            activation: .toggle,
            sourceName: "English",
            targetName: "English",
            sameLanguage: true,
            ready: "",
            showAs: "",
            spoken: "good morning"
        )
        XCTAssertEqual(chip.title, "English")
        XCTAssertEqual(chip.line, "good morning")
        XCTAssertTrue(chip.lineIsReady)
    }

    func testBarKeepsSentencesAlreadyReadyToType() {
        let chip = QuickTranslateInsert.chip(
            phase: .listening,
            activation: .toggle,
            sourceName: "English",
            targetName: "Korean",
            sameLanguage: false,
            ready: "안녕하세요.",
            showAs: "잘 지내요.",
            spoken: "how are you"
        )
        XCTAssertEqual(chip.title, "English → Korean")
        XCTAssertEqual(chip.line, "안녕하세요.\n잘 지내요.")
        XCTAssertTrue(chip.lineIsReady)
    }

    func testAShortShowAsLineIsNotDroppedWhenItEndsLikeThePreviousOne() {
        let chip = QuickTranslateInsert.chip(
            phase: .listening,
            activation: .hold,
            sourceName: "English",
            targetName: "English",
            sameLanguage: true,
            ready: "It is good.",
            showAs: "good.",
            spoken: ""
        )
        XCTAssertEqual(chip.line, "It is good.\ngood.")
    }

    func testAStopBeforeTheSessionJoinsHidesTheBar() {
        var session = QuickTranslateInsertSession(armed: true)
        XCTAssertEqual(
            session.note(listenKind: nil, isSessionActive: false, isFinishing: true),
            .hidden
        )
        XCTAssertFalse(session.armed)
    }
}
