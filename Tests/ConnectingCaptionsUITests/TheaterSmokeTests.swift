//
//  TheaterSmokeTests.swift
//  Fluid
//
//  Launch smoke: sidebar Theater shows languages, Voice / Translate, and Theater chrome.
//  Do not click Listen or start live audio. Pause exists only after Listen.
//

import XCTest
import CoreGraphics

final class TheaterSmokeTests: XCTestCase {
    func testVoiceEngineShowsSupportedAndReadyLanguagesWithoutRecording() {
        self.continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["CONNECTINGCAPTIONS_UI_TESTS"] = "1"
        app.launchArguments += [
            "-OnboardingCompleted", "YES", "-AppLanguageID", "en",
            "-TranslationSourceLanguageID", "th", "-TranslationTargetLanguageID", "en",
            "-SelectedSpeechModel", "apple-speech-analyzer",
        ]
        app.launch()
        let engines = app.descendants(matching: .any)["sidebar.voiceEngine"]
        XCTAssertTrue(engines.waitForExistence(timeout: 10))
        engines.click()
        XCTAssertTrue(app.descendants(matching: .any)["voiceEngine.languages.apple-speech-analyzer"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.descendants(matching: .any)["voiceEngine.readyLanguages.apple-speech-analyzer"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["voiceEngine.languageStatus.apple-speech-analyzer"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["voiceEngine.languages.apple-speech"].exists)
        // English-only Parakeet cannot be selected or downloaded for I speak Thai.
        XCTAssertFalse(app.descendants(matching: .any)["voiceEngine.use.parakeet-realtime"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["voiceEngine.download.parakeet-realtime"].exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Voice Engine language support"
        screenshot.lifetime = .keepAlways
        self.add(screenshot)
    }

    func testLaunchShowsTheaterLanguagesAndListen() {
        self.continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["CONNECTINGCAPTIONS_UI_TESTS"] = "1"
        app.launchArguments += [
            "-OnboardingCompleted", "YES",
            "-AppLanguageID", "en",
            "-TheaterHideChrome", "NO",
            "-TheaterMinimized", "NO",
        ]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))

        let sidebarTheater = app.descendants(matching: .any)["sidebar.theater"]
        XCTAssertTrue(sidebarTheater.waitForExistence(timeout: 8), "Theater sidebar item")
        sidebarTheater.click()

        let languages = app.descendants(matching: .any)["theater.languages"]
        XCTAssertTrue(languages.waitForExistence(timeout: 8), "Home language card")

        let mode = app.descendants(matching: .any)["theater.mode"]
        XCTAssertTrue(mode.waitForExistence(timeout: 4), "Voice / Translate")

        let voiceButton = app.segmentedControls["theater.mode"].buttons["Original language"]
        if voiceButton.waitForExistence(timeout: 2) {
            voiceButton.click()
        } else {
            app.buttons["Original language"].firstMatch.click()
        }
        let advanced = app.disclosureTriangles["theater.home.advanced"]
        XCTAssertTrue(advanced.waitForExistence(timeout: 4), "Advanced engine controls")
        let homeScroll = app.scrollViews.containing(.disclosureTriangle, identifier: "theater.home.advanced").firstMatch
        for _ in 0..<6 where !advanced.isHittable {
            homeScroll.scroll(byDeltaX: 0, deltaY: -300)
        }
        XCTAssertTrue(advanced.isHittable, "Advanced disclosure is visible before clicking")
        // The native AX frame includes the card's leading inset. Press the
        // visible triangle rather than the padding to its left.
        advanced.coordinate(withNormalizedOffset: CGVector(dx: 0.30, dy: 0.5)).click()
        XCTAssertTrue(
            app.descendants(matching: .any)["theater.voiceEngine"].waitForExistence(timeout: 4),
            "Voice Engine is speech to text"
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["theater.customizeVoiceEngine"].waitForExistence(timeout: 4),
            "Voice Engine in Voice mode"
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["theater.translationEngine"].waitForExistence(timeout: 4),
            "Translation Engine names Apple Translation"
        )

        let listen = app.descendants(matching: .any)["theater.listen"]
        XCTAssertTrue(listen.waitForExistence(timeout: 4), "Listen")

        let openTheater = app.descendants(matching: .any)["theater.open"]
        XCTAssertTrue(openTheater.waitForExistence(timeout: 4), "Open Theater")
        for _ in 0..<6 where !openTheater.isHittable {
            homeScroll.scroll(byDeltaX: 0, deltaY: 400)
        }
        XCTAssertTrue(openTheater.isHittable, "Open Theater is visible before clicking")
        openTheater.click()

        XCTAssertTrue(
            app.descendants(matching: .any)["theater.window.languages"].waitForExistence(timeout: 6),
            "Theater window languages"
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["theater.window.mode"].waitForExistence(timeout: 4),
            "Voice / Translate is on Theater chrome"
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["theater.window.listen"].waitForExistence(timeout: 4),
            "Listen is on Theater chrome"
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["theater.presentationStyle"].waitForExistence(timeout: 4),
            "Settings stays on Theater chrome"
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["theater.status"].waitForExistence(timeout: 4),
            "Status line after Open Theater"
        )
        XCTAssertFalse(
            app.descendants(matching: .any)["theater.pause"].exists,
            "Pause only appears after Listen; smoke must not start audio"
        )
    }
}
