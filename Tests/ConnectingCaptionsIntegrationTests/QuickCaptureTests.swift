import CoreGraphics
import XCTest
@testable import ConnectingCaptions_Debug

final class QuickCaptureTests: XCTestCase {
    func testCaptionListenOpensDefaultsToTheater() {
        let settings = SettingsStore.shared
        let saved = settings.captionListenOpens
        settings.captionListenOpens = .theater
        defer { settings.captionListenOpens = saved }
        settings.defaults.removeObject(forKey: "CaptionListenOpens")
        XCTAssertEqual(settings.captionListenOpens, .theater)
        settings.captionListenOpens = saved
    }

    func testHomeAndMenuRoutesOpenTheaterEvenWhenQuickCaptureIsSelected() {
        let presentation = CaptionListenRoute.presentation(
            invokedFromShortcut: false,
            setting: .quickCapture
        )
        XCTAssertEqual(presentation, .theater)
        XCTAssertTrue(CaptionListenRoute.showsTheaterWindow(presentation))
        XCTAssertTrue(
            CaptionListenRoute.shouldOpenTheaterOnBegin(
                kind: .captions,
                presentation: presentation,
                windowEnabled: false,
                minimized: false
            )
        )
    }

    func testShortcutRouteKeepsTheaterHidden() {
        let presentation = CaptionListenRoute.presentation(
            invokedFromShortcut: true,
            setting: .quickCapture
        )
        XCTAssertEqual(presentation, .quickCapture)
        XCTAssertFalse(CaptionListenRoute.showsTheaterWindow(presentation))
        XCTAssertFalse(
            CaptionListenRoute.shouldOpenTheaterOnBegin(
                kind: .captions,
                presentation: presentation,
                windowEnabled: false,
                minimized: true
            )
        )
    }

    func testShortcutStillOpensTheaterWhenThatIsTheSetting() {
        let presentation = CaptionListenRoute.presentation(
            invokedFromShortcut: true,
            setting: .theater
        )
        XCTAssertEqual(presentation, .theater)
        XCTAssertTrue(CaptionListenRoute.showsTheaterWindow(presentation))
    }

    func testFailedShortcutStartDoesNotHideTheaterOnTheNextHomeStart() {
        let afterFailure = CaptionPresentation.quickCapture
        let home = CaptionListenRoute.presentation(
            invokedFromShortcut: false,
            setting: afterFailure
        )
        XCTAssertEqual(home, .theater)
        XCTAssertTrue(CaptionListenRoute.showsTheaterWindow(home))
        XCTAssertTrue(
            CaptionListenRoute.shouldOpenTheaterOnBegin(
                kind: .captions,
                presentation: home,
                windowEnabled: false,
                minimized: false
            )
        )
    }

    func testFailureTextReachesTheChip() {
        let content = QuickCaptureChipContent.make(
            committedLast: "Earlier line",
            overlay: "live words",
            statusText: "Download the language pack before Listen.",
            statusKind: .failure
        )
        XCTAssertEqual(content.failure, "Download the language pack before Listen.")
        XCTAssertTrue(content.finished.isEmpty)
        XCTAssertTrue(content.live.isEmpty)
        XCTAssertTrue(
            QuickCaptureVisibility.isShown(
                presentation: .quickCapture,
                listenKind: nil,
                isSessionActive: false,
                isFinishing: false,
                hasFailure: content.isFailure
            )
        )
        XCTAssertFalse(
            QuickCaptureVisibility.isShown(
                presentation: .theater,
                listenKind: nil,
                isSessionActive: false,
                isFinishing: false,
                hasFailure: content.isFailure
            )
        )
    }

    func testChipKeepsTheLastFinishedLineAboveTheLiveLine() {
        let content = QuickCaptureChipContent.make(
            committedLast: "We closed the round.",
            overlay: "The next clause",
            statusText: "",
            statusKind: .idle
        )
        XCTAssertEqual(content.finished, "We closed the round.")
        XCTAssertEqual(content.live, "The next clause")
        XCTAssertFalse(content.isFailure)
    }

    func testSavedOriginIsReusedWhenItsScreenStillExists() {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let saved = CGPoint(x: 40, y: 80)
        let origin = QuickCapturePlacement.origin(
            saved: saved,
            mouse: CGPoint(x: 1200, y: 700),
            panelSize: CGSize(width: 496, height: 120),
            screenFrames: [screen]
        )
        XCTAssertEqual(origin, saved)
    }

    func testFirstShowSitsUnderThePointer() {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let origin = QuickCapturePlacement.origin(
            saved: nil,
            mouse: CGPoint(x: 700, y: 500),
            panelSize: CGSize(width: 496, height: 120),
            screenFrames: [screen]
        )
        XCTAssertEqual(origin.x, 700 - 248, accuracy: 0.1)
        XCTAssertEqual(origin.y, 500 - 120 - 12, accuracy: 0.1)
    }
}
