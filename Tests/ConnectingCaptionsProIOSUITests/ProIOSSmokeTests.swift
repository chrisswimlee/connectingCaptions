import XCTest

/// Launch smoke for the direct iPhone and iPad app. Do not tap Listen.
/// Listen downloads a voice model and opens the microphone.
final class ProIOSSmokeTests: XCTestCase {
    func testLaunchShowsListenAndAFreeDownload() {
        self.continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.buttons["Listen"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["I speak"].exists)
        XCTAssertTrue(app.staticTexts["Show as"].exists)

        app.buttons["License"].tap()
        XCTAssertTrue(app.staticTexts["Free download"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Listen does not ask for a key. A Connecting Captions Pro key can still be pasted."].exists)
    }
}
