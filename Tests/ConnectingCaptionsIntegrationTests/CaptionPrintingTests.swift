import AppKit
import XCTest
@testable import ConnectingCaptions_Debug

@MainActor
final class CaptionPrintingTests: XCTestCase {
    private var originalStyle = TheaterLinePrint.atOnce
    private var originalGap = TheaterPrintGap.close
    private let start: TimeInterval = 100

    override func setUp() async throws {
        try await super.setUp()
        self.originalStyle = SettingsStore.shared.theaterLinePrint
        self.originalGap = SettingsStore.shared.theaterPrintGap
        SettingsStore.shared.theaterPrintGap = .tight
    }

    override func tearDown() async throws {
        SettingsStore.shared.theaterLinePrint = self.originalStyle
        SettingsStore.shared.theaterPrintGap = self.originalGap
        try await super.tearDown()
    }

    func testUnchangedViewUpdatePreservesAnActiveFade() {
        SettingsStore.shared.theaterLinePrint = .fade
        let view = self.makeView()
        self.caption(view, text: "Hello world")
        view.stepReveal(at: self.start + 0.05)
        let opacity = view.alphaValue
        XCTAssertGreaterThan(opacity, 0)
        XCTAssertLessThan(opacity, 1)
        self.caption(view, text: "Hello world", now: self.start + 0.06)
        XCTAssertEqual(view.alphaValue, opacity, accuracy: 0.001)
    }

    func testRevisionOfAFadedLineDoesNotBlankTheExistingCaption() {
        SettingsStore.shared.theaterLinePrint = .fade
        let view = self.makeView()
        self.caption(view, text: "Hello world")
        view.stepReveal(at: self.start + 1)
        self.caption(view, text: "Hello world today", now: self.start + 1)
        view.stepReveal(at: self.start + 1.02)
        XCTAssertEqual(view.alphaValue, 1)
        XCTAssertEqual(self.ink(view), ["Hello world today"])
    }

    func testWordPrintingRevealsTheEntireLastWord() {
        SettingsStore.shared.theaterLinePrint = .word
        let view = self.makeView()
        self.caption(view, text: "Hello")
        view.stepReveal(at: self.start + 0.02)
        XCTAssertEqual(self.ink(view), ["Hello"])
    }

    func testWrappedWhitespaceDoesNotRevealTheNextRowEarly() {
        SettingsStore.shared.theaterLinePrint = .letter
        let view = self.makeView()
        self.caption(view, text: "Hello world", rows: [
            .init(text: "Hello ", isSpoken: false), .init(text: "world", isSpoken: false)
        ])
        for tick in 1...6 { view.stepReveal(at: self.start + Double(tick) * 0.02) }
        XCTAssertEqual(self.ink(view), ["Hello", ""])
    }

    func testLateTimerTickCatchesUpToElapsedTime() {
        SettingsStore.shared.theaterLinePrint = .letter
        let view = self.makeView()
        self.caption(view, text: "Hello world")
        view.stepReveal(at: self.start + 0.12)
        XCTAssertEqual(self.ink(view), ["Hello"])
        view.stepReveal(at: self.start + 1)
        XCTAssertEqual(self.ink(view), ["Hello world"])
    }

    func testNewCaptionIdentityRestartsTheVisiblePrint() {
        SettingsStore.shared.theaterLinePrint = .letter
        let view = self.makeView()
        self.caption(view, text: "Hello world")
        view.stepReveal(at: self.start + 0.02)
        self.caption(view, text: "Goodbye world", id: "c-2")
        XCTAssertEqual(self.ink(view), [""])
    }

    func testAtOnceShowsEveryCharacterInBothLanguages() {
        SettingsStore.shared.theaterLinePrint = .atOnce
        let view = self.makeView()
        self.caption(view, text: "안녕하세요.", spoken: "Hello.")
        XCTAssertEqual(self.ink(view), ["안녕하세요.", "Hello."])
        XCTAssertEqual(view.alphaValue, 1)
    }

    func testChangingPrintStyleFinishesTheExistingLineWithoutReplayingIt() {
        SettingsStore.shared.theaterLinePrint = .letter
        let view = self.makeView()
        self.caption(view, text: "Hello world")
        view.stepReveal(at: self.start + 0.02)
        SettingsStore.shared.theaterLinePrint = .fade
        self.caption(view, text: "Hello world", now: self.start + 0.04)
        view.stepReveal(at: self.start + 0.06)
        XCTAssertEqual(self.ink(view), ["Hello world"])
        XCTAssertEqual(view.alphaValue, 1)
    }

    func testReduceMotionFinishesAnActivePrintImmediately() {
        SettingsStore.shared.theaterLinePrint = .letter
        let view = self.makeView()
        self.caption(view, text: "Hello world")
        view.stepReveal(at: self.start + 0.02)
        self.caption(view, text: "Hello world", now: self.start + 0.04, reduceMotion: true)
        XCTAssertEqual(self.ink(view), ["Hello world"])
        XCTAssertEqual(view.alphaValue, 1)
    }

    func testLetterPrintingKeepsEmojiAndCombiningCharactersWhole() {
        SettingsStore.shared.theaterLinePrint = .letter
        let view = self.makeView()
        self.caption(view, text: "👨‍👩‍👧‍👦é🇹🇭")
        view.stepReveal(at: self.start + 0.02)
        XCTAssertEqual(self.ink(view), ["👨‍👩‍👧‍👦"])
        view.stepReveal(at: self.start + 0.04)
        XCTAssertEqual(self.ink(view), ["👨‍👩‍👧‍👦é"])
        view.stepReveal(at: self.start + 0.06)
        XCTAssertEqual(self.ink(view), ["👨‍👩‍👧‍👦é🇹🇭"])
    }

    func testWordPrintingKeepsJapaneseAndThaiWordsTogether() {
        SettingsStore.shared.theaterLinePrint = .word
        let view = self.makeView()
        self.caption(view, text: "今日は晴れです。")
        view.stepReveal(at: self.start + 0.02)
        XCTAssertEqual(self.ink(view), ["今日"])
        self.caption(view, text: "สวัสดีครับทุกคน", id: "c-2")
        view.stepReveal(at: self.start + 0.02)
        let firstWord = self.ink(view).joined()
        XCTAssertGreaterThan(firstWord.count, 2)
        XCTAssertTrue("สวัสดีครับทุกคน".hasPrefix(firstWord))
        view.stepReveal(at: self.start + 1)
        XCTAssertEqual(self.ink(view), ["สวัสดีครับทุกคน"])
    }

    func testGrowthKeepsTheAlreadyPrintedPrefix() {
        SettingsStore.shared.theaterLinePrint = .letter
        let view = self.makeView()
        self.caption(view, text: "Hello")
        view.stepReveal(at: self.start + 1)
        self.caption(view, text: "Hello world", now: self.start + 1)
        XCTAssertEqual(self.ink(view), ["Hello"])
        view.stepReveal(at: self.start + 1.02)
        XCTAssertEqual(self.ink(view), ["Hello"])
        view.stepReveal(at: self.start + 1.04)
        XCTAssertEqual(self.ink(view), ["Hello w"])
    }

    private func makeView() -> TheaterCaptionLineNSView {
        TheaterCaptionLineNSView(frame: NSRect(x: 0, y: 0, width: 900, height: 300))
    }

    private func ink(_ view: TheaterCaptionLineNSView) -> [String] {
        view.subviews.compactMap { ($0 as? NSTextField)?.stringValue }
    }

    private func caption(
        _ view: TheaterCaptionLineNSView, text: String, spoken: String = "", id: String = "c-1",
        rows: [TheaterBilingualWrap.Row]? = nil, now: TimeInterval = 100, reduceMotion: Bool = false
    ) {
        var layout = rows ?? [.init(text: text, isSpoken: false)]
        if !spoken.isEmpty { layout.append(.init(text: spoken, isSpoken: true)) }
        view.adoptStageWrapWidth(900)
        view.adoptLaidOutRows(layout, width: 900)
        view.setCaption(lineID: id, spoken: spoken, translated: text, isCurrent: true,
                        paint: TheaterCaptionLinePaint(typeface: .system, spokenFontSize: 28,
                            translatedFontSize: 40, spokenColor: .white, translatedColor: .white,
                            shadowColor: nil, shadowBlur: 0, reduceMotion: reduceMotion), now: now)
    }
}

@MainActor
final class CaptionPublicationIsolationTests: XCTestCase {
    func testAnOldListenCannotCancelTheNewListensTranslation() async {
        let settings = SettingsStore.shared
        let source = settings.translationSourceLanguageID
        let target = settings.translationTargetLanguageID
        let mode = settings.theaterSessionMode
        defer {
            settings.translationSourceLanguageID = source
            settings.translationTargetLanguageID = target
            settings.theaterSessionMode = mode
        }
        settings.translationSourceLanguageID = "en"
        settings.translationTargetLanguageID = "ko"
        settings.theaterSessionMode = .translation
        var translationCounts: [Int] = []
        for restart in [false, true] {
            let engine = FakeTranslationEngine()
            engine.result = .success("오늘 시스템을 테스트합니다.")
            engine.delayNanoseconds = 30_000_000
            let subscriber = LiveTranslationSubscriber(translator: engine)
            let text = "Today we test the caption system."
            subscriber.beginListening()
            if restart {
                subscriber.handlePartial(text)
                subscriber.handlePartial(text)
                // Stop/restart before queued work gets a turn on the main actor.
                subscriber.endListening()
                subscriber.beginListening()
            }
            subscriber.handlePartial(text)
            subscriber.handlePartial(text)
            await subscriber.waitForIdleForTesting()
            XCTAssertEqual(subscriber.committedLines, ["오늘 시스템을 테스트합니다."])
            XCTAssertTrue(engine.calls.allSatisfy { $0 == text })
            translationCounts.append(engine.calls.count)
            subscriber.endListening()
        }
        // A normal Listen may prefetch as well as commit. Restarting must
        // not cancel that work and trigger an additional replacement request.
        XCTAssertGreaterThan(translationCounts[0], 0)
        XCTAssertEqual(translationCounts[1], translationCounts[0])
    }
}
