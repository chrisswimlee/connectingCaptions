import CoreGraphics
@testable import ConnectingCaptions_Debug
import XCTest

final class TypingEventSourceTests: XCTestCase {
    func testSyntheticKeysLeaveTheHardwareKeyboardLive() {
        XCTAssertEqual(TypingEventSource.hardwareSuppressionSeconds, 0)
        guard let events = TypingEventSource.pair(virtualKey: 0) else {
            XCTFail("synthetic key pair should be created")
            return
        }
        XCTAssertEqual(events.down.flags, [])
        XCTAssertEqual(events.up.flags, [])
        XCTAssertEqual(
            events.down.getIntegerValueField(.eventSourceUserData),
            TypingService.synthesizedEventUserData
        )
        XCTAssertEqual(
            events.up.getIntegerValueField(.eventSourceUserData),
            TypingService.synthesizedEventUserData
        )
    }

    func testPasteChordKeepsCommandAndTheSyntheticMarker() {
        guard let events = TypingEventSource.pair(virtualKey: 9, flags: .maskCommand) else {
            XCTFail("paste chord should be created")
            return
        }
        XCTAssertEqual(events.down.flags, .maskCommand)
        XCTAssertEqual(events.up.flags, .maskCommand)
        XCTAssertEqual(
            events.down.getIntegerValueField(.eventSourceUserData),
            TypingService.synthesizedEventUserData
        )
    }
}
