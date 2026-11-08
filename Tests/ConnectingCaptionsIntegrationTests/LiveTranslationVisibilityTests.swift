@testable import ConnectingCaptions_Debug
import AppKit
import ConnectingCaptionsCore
import XCTest

final class LiveTranslationVisibilityTests: XCTestCase {
    func testTransparentLightDoesNotUseBlackCaptions() {
        let colors = TheaterCaptionVisibility.colors(
            appearance: .light,
            presentation: .transparent,
            highContrast: false
        )
        let translated = self.rgb(colors.translated)
        XCTAssertGreaterThan(translated.r, 0.9)
        XCTAssertGreaterThan(translated.g, 0.9)
        XCTAssertGreaterThan(translated.b, 0.9)
        XCTAssertNotNil(colors.shadowColor)
        XCTAssertGreaterThan(colors.shadowBlur, 2)
        let halo = self.rgb(colors.shadowColor ?? .white)
        XCTAssertLessThan(halo.r, 0.2)
    }

    func testLightPopupSpokenIsDarkEnoughForAWhiteBoard() {
        let colors = TheaterCaptionVisibility.colors(
            appearance: .light,
            presentation: .popup,
            highContrast: false
        )
        let spoken = self.rgb(colors.spoken)
        let brightness = (spoken.r + spoken.g + spoken.b) / 3
        XCTAssertLessThan(brightness, 0.5)
        XCTAssertEqual(colors.translated, .black)
        XCTAssertNil(colors.shadowColor)
    }

    func testDarkPopupUsesWhiteTitleAndDimSpokenUndertone() {
        let colors = TheaterCaptionVisibility.colors(
            appearance: .dark,
            presentation: .popup,
            highContrast: true
        )
        XCTAssertEqual(colors.translated, .white)
        XCTAssertGreaterThan(colors.spoken.alphaComponent, 0.7)
        XCTAssertLessThan(colors.spoken.alphaComponent, 0.85)
        let spoken = self.rgb(colors.spoken)
        XCTAssertGreaterThan(spoken.r, 0.9)
        XCTAssertNotNil(colors.shadowColor)
    }

    func testFinishedTranslationKeepsFullOpacity() {
        let applied = TheaterCaptionVisibility.appliedAlphas(
            spoken: NSColor.white.withAlphaComponent(0.58),
            translated: .white,
            isCurrent: false
        )
        XCTAssertEqual(applied.translated.alphaComponent, 1, accuracy: 0.01)
        XCTAssertGreaterThan(applied.spoken.alphaComponent, 0.88)
        XCTAssertLessThan(applied.spoken.alphaComponent, 1)
    }

    func testReversePairColorFlagsOtherSpeakerInEitherWay() {
        XCTAssertFalse(
            TheaterCaptionVisibility.usesReversePairColor(
                sourceLanguageID: "th",
                targetLanguageID: "en",
                configuredSourceID: "th"
            )
        )
        XCTAssertTrue(
            TheaterCaptionVisibility.usesReversePairColor(
                sourceLanguageID: "en",
                targetLanguageID: "th",
                configuredSourceID: "th"
            )
        )
        XCTAssertFalse(
            TheaterCaptionVisibility.usesReversePairColor(
                sourceLanguageID: "en",
                targetLanguageID: "en",
                configuredSourceID: "th"
            )
        )
        XCTAssertFalse(
            TheaterCaptionVisibility.usesReversePairColor(
                sourceLanguageID: nil,
                targetLanguageID: "th",
                configuredSourceID: "th"
            )
        )
    }

    func testReversePairColorsStayReadableInDarkAndLightBoards() {
        let darkColors = TheaterCaptionVisibility.colors(
            appearance: .dark,
            presentation: .popup,
            highContrast: false
        )
        let darkReverse = self.rgb(darkColors.lineColors(reversePair: true).translated)
        XCTAssertGreaterThan(darkReverse.b, darkReverse.r)
        XCTAssertGreaterThan(darkReverse.g, 0.8)

        let lightColors = TheaterCaptionVisibility.colors(
            appearance: .light,
            presentation: .popup,
            highContrast: false
        )
        let lightReverse = self.rgb(lightColors.lineColors(reversePair: true).translated)
        let lightBrightness = (lightReverse.r + lightReverse.g + lightReverse.b) / 3
        XCTAssertLessThan(lightBrightness, 0.5)
        XCTAssertGreaterThan(lightReverse.b, lightReverse.r)
    }

    func testTheaterCaptionFlowPreservesLineLanguagePair() {
        let board = TheaterBoardState(
            rows: [
                TheaterBoardRow(
                    id: 1,
                    source: "สวัสดีครับ",
                    translated: "Hello",
                    sourceLanguageID: "th",
                    targetLanguageID: "en"
                ),
                TheaterBoardRow(
                    id: 2,
                    source: "Welcome everyone",
                    translated: "ยินดีต้อนรับทุกคน",
                    sourceLanguageID: "en",
                    targetLanguageID: "th"
                ),
            ],
            nextID: 3
        )
        let lines = TheaterCaptionFlow.lines(board: board)
        XCTAssertEqual(lines.count, 2)
        XCTAssertEqual(lines[0].sourceLanguageID, "th")
        XCTAssertEqual(lines[0].targetLanguageID, "en")
        XCTAssertEqual(lines[1].sourceLanguageID, "en")
        XCTAssertEqual(lines[1].targetLanguageID, "th")
    }

    @MainActor
    func testPasteTranslateResolvesThaiAndEnglishEitherWay() {
        let model = TheaterPasteTranslate.shared
        let originalSource = model.sourceLanguageID
        let originalTarget = model.targetLanguageID
        let originalAuto = model.autoDetectPairDirection
        defer {
            model.sourceLanguageID = originalSource
            model.targetLanguageID = originalTarget
            model.autoDetectPairDirection = originalAuto
            model.clear()
        }

        model.sourceLanguageID = "th"
        model.targetLanguageID = "en"
        model.autoDetectPairDirection = true

        let thaiPair = model.resolvedPair(for: "สวัสดีครับทุกคน")
        XCTAssertEqual(thaiPair.source.id, "th")
        XCTAssertEqual(thaiPair.target.id, "en")

        let englishPair = model.resolvedPair(for: "Welcome to our bilingual session")
        XCTAssertEqual(englishPair.source.id, "en")
        XCTAssertEqual(englishPair.target.id, "th")
    }

    private func rgb(_ color: NSColor) -> (r: CGFloat, g: CGFloat, b: CGFloat) {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        let converted = color.usingColorSpace(.deviceRGB) ?? color
        converted.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return (red, green, blue)
    }
}
