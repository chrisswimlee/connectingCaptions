import XCTest
@testable import ConnectingCaptions_Debug

@MainActor
final class LiveTranslationJapaneseClauseTests: XCTestCase {
    func testAFinishedJapaneseClauseStillPeelsWhenTheNextSentenceFollows() {
        let spoken = "モデルを学習しました それを適用すると"
        let split = TranslationClauseSegmenter.split(spoken, languageID: "ja")
        XCTAssertEqual(split.completed, ["モデルを学習しました"])
        XCTAssertEqual(split.tail, "それを適用すると")
        XCTAssertTrue(TranslationClauseSegmenter.looksComplete("学習しました", languageID: "ja"))
        XCTAssertTrue(TranslationClauseSegmenter.looksComplete("行きますか", languageID: "ja"))
        XCTAssertTrue(TranslationClauseSegmenter.looksComplete("行きますよ", languageID: "ja"))
    }

    func testBareKaDaYoAreNotFinishedClauses() {
        XCTAssertFalse(TranslationClauseSegmenter.looksComplete("何か", languageID: "ja"))
        XCTAssertFalse(TranslationClauseSegmenter.looksComplete("そうだ", languageID: "ja"))
        XCTAssertFalse(TranslationClauseSegmenter.looksComplete("面白いよ", languageID: "ja"))
        let question = TranslationClauseSegmenter.split("何かありますか", languageID: "ja")
        XCTAssertTrue(question.completed.isEmpty, question.completed.joined(separator: " | "))
        XCTAssertEqual(question.tail, "何かありますか")
        let think = TranslationClauseSegmenter.split("そうだと思います", languageID: "ja")
        XCTAssertTrue(think.completed.isEmpty, think.completed.joined(separator: " | "))
        XCTAssertEqual(think.tail, "そうだと思います")
    }

    func testKaraDoesNotCutTokyoKaraKimashita() {
        let spoken = "今日東京から来ました"
        let split = TranslationClauseSegmenter.split(spoken, languageID: "ja")
        XCTAssertTrue(split.completed.isEmpty, split.completed.joined(separator: " | "))
        XCTAssertEqual(split.tail, spoken)
        XCTAssertFalse(TranslationClauseSegmenter.isInternalBoundary("東京から", languageID: "ja"))
        XCTAssertTrue(
            TranslationClauseSegmenter.isCaptionReadyConnective(
                "今日の講義ではそのモデルを学習したので",
                languageID: "ja"
            )
        )
    }

    func testDesuPlusNodeStaysOneSentence() {
        let spoken = "今日は休みですので家にいます"
        let split = TranslationClauseSegmenter.split(spoken, languageID: "ja")
        XCTAssertTrue(split.completed.isEmpty, split.completed.joined(separator: " | "))
        XCTAssertEqual(split.tail, spoken)
        let next = TranslationClauseSegmenter.nextCompletedSentence(spoken, languageID: "ja")
        XCTAssertEqual(next?.unit, spoken)
        XCTAssertEqual(next?.rest, "")
        XCTAssertTrue(TranslationClauseSegmenter.japaneseRemainderContinuesClause("ので家にいます"))
        XCTAssertFalse(TranslationClauseSegmenter.continuesAsNewSentence("ので家にいます", languageID: "ja"))
        XCTAssertTrue(TranslationClauseSegmenter.continuesAsNewSentence("それから適用しました", languageID: "ja"))
    }

    func testMataDoesNotCutAnUnfinishedClause() {
        let spoken = "今日はまた来ます"
        XCTAssertNil(
            TranslationClauseSegmenter.unpunctuatedSentenceBreak(spoken, languageID: "ja")
        )
        let split = TranslationClauseSegmenter.split(spoken, languageID: "ja")
        XCTAssertTrue(split.completed.isEmpty, split.completed.joined(separator: " | "))
        XCTAssertEqual(split.tail, spoken)
        let next = TranslationClauseSegmenter.unpunctuatedSentenceBreak(
            "モデルを学習しましたそれから適用しました",
            languageID: "ja"
        )
        XCTAssertEqual(next?.unit, "モデルを学習しました")
        XCTAssertEqual(next?.rest, "それから適用しました")
    }

    func testNodeLeftoverGrowsTheNewestJapaneseRow() {
        XCTAssertEqual(
            TranslationClauseSegmenter.japaneseRowContinuation(
                row: "今日は休みです",
                unit: "ので家にいます",
                languageID: "ja"
            ),
            "今日は休みですので家にいます"
        )
        XCTAssertEqual(
            TranslationClauseSegmenter.rowContinuation(
                row: "今日は休みです。",
                unit: "ので家にいます",
                languageID: "ja"
            ),
            "今日は休みですので家にいます"
        )
        XCTAssertNil(
            TranslationClauseSegmenter.japaneseRowContinuation(
                row: "今日は休みです",
                unit: "そして次に適用しました",
                languageID: "ja"
            )
        )
        XCTAssertNil(
            TranslationClauseSegmenter.japaneseRowContinuation(
                row: "Today we trained the model.",
                unit: "ので家にいます",
                languageID: "en"
            )
        )
    }

    func testNodeLeftoverDoesNotPrintASecondCaption() async {
        let settings = SettingsStore.shared
        let originalSource = settings.translationSourceLanguageID
        let originalTarget = settings.translationTargetLanguageID
        let originalMode = settings.theaterSessionMode
        defer {
            settings.translationSourceLanguageID = originalSource
            settings.translationTargetLanguageID = originalTarget
            settings.theaterSessionMode = originalMode
        }
        settings.theaterSessionMode = .transcription
        settings.translationSourceLanguageID = "ja"
        settings.translationTargetLanguageID = "ja"

        let subscriber = LiveTranslationSubscriber(translator: FakeTranslationEngine())
        subscriber.beginListening()
        subscriber.seedCommittedForTesting(source: "今日は休みです", translated: "今日は休みです")
        subscriber.handlePartial("ので家にいます")
        subscriber.handlePartial("ので家にいます")
        await subscriber.waitForIdleForTesting()
        XCTAssertEqual(subscriber.committedSourceLines, ["今日は休みですので家にいます"])
        XCTAssertEqual(subscriber.committedLines, ["今日は休みですので家にいます"])
    }
}
