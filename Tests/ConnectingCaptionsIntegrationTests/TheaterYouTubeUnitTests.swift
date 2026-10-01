import XCTest
@testable import ConnectingCaptions_Debug

final class TheaterYouTubeUnitTests: XCTestCase {
    func testTrailingEllipsisStaysAnOpenTail() {
        let partial = "adjusts to new..."
        XCTAssertFalse(TranslationClauseSegmenter.isCommitComplete(partial, languageID: "en"))
        XCTAssertFalse(TranslationClauseSegmenter.isCommitComplete("…adjusts to new...", languageID: "en"))
        let split = TranslationClauseSegmenter.split("…adjusts to new...", languageID: "en")
        XCTAssertTrue(split.completed.isEmpty, "\(split.completed)")
        XCTAssertEqual(split.tail, "…adjusts to new...")
        XCTAssertEqual(
            TranslationClauseSegmenter.finishOpenEllipsis("us to use AI responsibly..."),
            "us to use AI responsibly."
        )
    }

    func testOpenEllipsisBeforeAResetWindowStaysOneSentence() {
        let stalled = "AI systems are fed fast amounts of data, which they... Used to make decisions, recognize patterns, and perform tasks."
        let split = TranslationClauseSegmenter.split(stalled, languageID: "en")
        XCTAssertEqual(split.completed.count, 1, split.completed.joined(separator: " | "))
        XCTAssertEqual(
            TranslationClauseSegmenter.normalizedKey(split.completed[0]),
            TranslationClauseSegmenter.normalizedKey(
                "AI systems are fed fast amounts of data, which they used to make decisions, recognize patterns, and perform tasks."
            )
        )

        let finished = "It will change everything... In other words, it will change."
        let kept = TranslationClauseSegmenter.split(finished, languageID: "en")
        let lines = kept.completed.map { TranslationClauseSegmenter.normalizedKey($0) }
        XCTAssertTrue(lines.contains { $0.hasPrefix("it will change everything") }, lines.joined(separator: " | "))
        XCTAssertTrue(lines.contains { $0.contains("other words") }, lines.joined(separator: " | "))
    }

    func testTailRevisionGrowsAMisheardEnding() {
        let folks = "Another subset is deep learning, which is similar to a neural network, which both folks."
        let focus = "Another subset is deep learning, which is similar to a neural network, which both focus on modeling behaviors of the human brain."
        XCTAssertTrue(TranslationClauseSegmenter.isTailRevisionGrowth(previous: folks, incoming: focus))

        let challenges = "As AI evolves, ethical considerations grow, questions about privacy, autonomy, and job displacement, challenges."
        let challenge = "As AI evolves, ethical considerations grow, questions about privacy, autonomy, and job displacement, challenge us to use AI responsibly."
        XCTAssertTrue(TranslationClauseSegmenter.isTailRevisionGrowth(previous: challenges, incoming: challenge))

        XCTAssertFalse(
            TranslationClauseSegmenter.isTailRevisionGrowth(
                previous: "Today we trained the model on stage.",
                incoming: "The next lecture starts at noon tomorrow indeed."
            )
        )
    }

    func testOverlapMergeRebuildsTheCutSentence() {
        let row = "As AI evolves, ethical considerations grow, questions about privacy, autonomy, and job displacement, challenges."
        let hypothesis = "Questions about privacy, autonomy, and job displacement challenge us to use AI responsibly."
        let merged = TranslationClauseSegmenter.mergedContinuation(
            row: row,
            hypothesis: hypothesis,
            unit: "us to use AI responsibly.",
            languageID: "en"
        )
        let expected = "As AI evolves, ethical considerations grow, questions about privacy, autonomy, and job displacement challenge us to use AI responsibly."
        XCTAssertEqual(
            TranslationClauseSegmenter.normalizedKey(merged ?? ""),
            TranslationClauseSegmenter.normalizedKey(expected)
        )
    }

    func testALaterWindowOfAPrintedSentenceIsNotANewRow() {
        let full = "Artificial intelligence makes it possible for machines to learn from experience, adjust to new inputs, and perform human like tasks."
        let window = "adjusts to new inputs and perform human like tasks."
        XCTAssertTrue(TranslationClauseSegmenter.wordsAlreadyPrinted(window, in: full))
        let people = "Many people don't realize AI already impacts us, powering many tools we use daily from search engines that predict what we're looking at."
        let tail = "we're looking for to voice assistants like Siri and Alexa, and even recommendations on Netflix."
        XCTAssertFalse(TranslationClauseSegmenter.wordsAlreadyPrinted(tail, in: people))
        let merged = TranslationClauseSegmenter.mergedContinuation(
            row: people,
            hypothesis: tail,
            unit: tail,
            languageID: "en"
        )
        XCTAssertTrue(
            TranslationClauseSegmenter.normalizedKey(merged ?? "").contains("voice assistants like siri"),
            merged ?? "nil"
        )
    }

    func testALaterPeriodSplitsACommaJoinedLine() {
        let painted = "Stephen Curry just gave the warriors something that could be more valuable than the extra $20 million he left on the table, time."
        let hypothesis = "Stephen Curry just gave the warriors something that could be more valuable than the extra $20 million he left on the table. Time. Curry agreed to a two year extension."
        let split = TranslationClauseSegmenter.separatedSentences(
            painted: painted,
            hypothesis: hypothesis,
            languageID: "en"
        )
        XCTAssertEqual(
            TranslationClauseSegmenter.normalizedKey(split?.head ?? ""),
            TranslationClauseSegmenter.normalizedKey(
                "Stephen Curry just gave the warriors something that could be more valuable than the extra $20 million he left on the table."
            )
        )
        XCTAssertEqual(TranslationClauseSegmenter.normalizedKey(split?.next ?? ""), "time")

        let extensionLine = "Curry agreed to a two year, $116 million extension that keeps him in Golden State through at least the 2027, 28 season, with a player option for the 2028 29 season, the maximum extension he could have signed was worth roughly $136.7 million."
        let extensionHypothesis = "Curry agreed to a two year, $116 million extension that keeps him in Golden State through at least the 2027, 28 season, with a player option for the 2028 29 season. The maximum extension he could have signed was worth roughly $136.7 million. So, yes."
        let money = TranslationClauseSegmenter.separatedSentences(
            painted: extensionLine,
            hypothesis: extensionHypothesis,
            languageID: "en"
        )
        XCTAssertTrue(
            TranslationClauseSegmenter.normalizedKey(money?.next ?? "").contains("136"),
            money?.next ?? "nil"
        )
        XCTAssertFalse(
            TranslationClauseSegmenter.normalizedKey(money?.head ?? "").contains("maximum extension")
        )
    }

    func testAWordAddedAtTheEndGrowsTheLine() {
        let painted = "So the warriors can't simply assume the current group will eventually become good enough, they need another injection of talent, and that's where Curry's discount becomes a roster building."
        let hypothesis = "So the warriors can't simply assume the current group will eventually become good enough, they need another injection of talent, and that's where Curry's discount becomes a roster building tool. The warriors don't have to spend that future money immediately."
        let grown = TranslationClauseSegmenter.sentenceWithAppendedTail(
            painted: painted,
            hypothesis: hypothesis,
            languageID: "en"
        )
        XCTAssertTrue(
            TranslationClauseSegmenter.normalizedKey(grown ?? "").hasSuffix("roster building tool"),
            grown ?? "nil"
        )
        let window = "And that's where Curry's discount becomes a roster building tool."
        let fromWindow = TranslationClauseSegmenter.sentenceWithAppendedTail(
            painted: painted,
            hypothesis: window,
            languageID: "en"
        )
        XCTAssertTrue(
            TranslationClauseSegmenter.normalizedKey(fromWindow ?? "").hasSuffix("roster building tool"),
            fromWindow ?? "nil"
        )
    }

    func testAFalsePeriodInsideThatIfStaysOneSentence() {
        let heard = "AI is something that If you aren't paying attention. It could easily take your job. your spouse, and your current way of life."
        let split = TranslationClauseSegmenter.split(heard, languageID: "en")
        XCTAssertEqual(split.completed.count, 1, split.completed.joined(separator: " | "))
        XCTAssertTrue(
            TranslationClauseSegmenter.normalizedKey(split.completed[0]).contains(
                "attention it could easily take your job your spouse"
            ),
            split.completed[0]
        )

        let warning = TranslationClauseSegmenter.split(
            "If you leave now. They will notice.",
            languageID: "en"
        )
        XCTAssertEqual(warning.completed.count, 2, warning.completed.joined(separator: " | "))

        let model = TranslationClauseSegmenter.split(
            "We trained the model. on the other hand it failed.",
            languageID: "en"
        )
        XCTAssertEqual(model.completed.count, 2, model.completed.joined(separator: " | "))

        let next = TranslationClauseSegmenter.split(
            "AI is something that if you aren't paying attention. It could take your job. It will change everything.",
            languageID: "en"
        )
        XCTAssertEqual(next.completed.count, 2, next.completed.joined(separator: " | "))
        XCTAssertTrue(
            TranslationClauseSegmenter.normalizedKey(next.completed[1]).hasPrefix("it will change"),
            next.completed.joined(separator: " | ")
        )
    }

    func testACloseLastWordStillGrowsTheLine() {
        let painted = "Many people don't realize AI already impacts us, powering many tools we use daily from search engines that predict what we're looking for to voice assistance."
        let hypothesis = "Many people don't realize AI already impacts us, powering many tools we use daily from search engines that predict what we're looking for to voice assistants like Siri and Alexa, and even recommendations on Netflix."
        let grown = TranslationClauseSegmenter.sentenceWithAppendedTail(
            painted: painted,
            hypothesis: hypothesis,
            languageID: "en"
        )
        XCTAssertTrue(
            TranslationClauseSegmenter.normalizedKey(grown ?? "").contains("assistants like siri"),
            grown ?? "nil"
        )
        XCTAssertTrue(
            TranslationClauseSegmenter.normalizedKey(grown ?? "").contains("netflix"),
            grown ?? "nil"
        )

        let window = "we're looking for to voice assistants like Siri and Alexa, and even recommendations on Netflix."
        let fromWindow = TranslationClauseSegmenter.sentenceWithAppendedTail(
            painted: painted,
            hypothesis: window,
            languageID: "en"
        )
        XCTAssertTrue(
            TranslationClauseSegmenter.normalizedKey(fromWindow ?? "").hasPrefix("many people"),
            fromWindow ?? "nil"
        )
        XCTAssertTrue(
            TranslationClauseSegmenter.normalizedKey(fromWindow ?? "").contains("assistants like siri"),
            fromWindow ?? "nil"
        )
    }

    func testThreeWordsAddedAtTheEndGrowTheLine() {
        let painted = "AI systems are fed vast amounts of data, which they use to make decisions, recognize patterns."
        let hypothesis = "AI systems are fed vast amounts of data, which they use to make decisions, recognize patterns and perform tasks. There are several subsets of AI."
        let grown = TranslationClauseSegmenter.sentenceWithAppendedTail(
            painted: painted,
            hypothesis: hypothesis,
            languageID: "en"
        )
        let grownKey = TranslationClauseSegmenter.normalizedKey(grown ?? "")
        XCTAssertTrue(grownKey.contains("and perform tasks"), grown ?? "nil")
        XCTAssertFalse(grownKey.contains("several"), grown ?? "nil")

        let window = "which they use to make decisions, recognize patterns and perform tasks."
        let fromWindow = TranslationClauseSegmenter.sentenceWithAppendedTail(
            painted: painted,
            hypothesis: window,
            languageID: "en"
        )
        let windowKey = TranslationClauseSegmenter.normalizedKey(fromWindow ?? "")
        XCTAssertTrue(windowKey.hasPrefix("ai systems"), fromWindow ?? "nil")
        XCTAssertTrue(windowKey.contains("and perform tasks"), fromWindow ?? "nil")
    }

    func testJoinedRowsAreNotAdmittedAgain() {
        let row3 = "Artificial intelligence makes it possible for machines to learn from experience, adjusts to new."
        let row4 = "inputs, and perform human like tasks."
        let row7 = "Artificial intelligence makes it possible for machines to learn from experience, Adjust to new inputs and perform human like tasks."
        let decision = TheaterBoardAdmission.decide(
            row7,
            languageID: "en",
            phase: .propose,
            context: TheaterBoardAdmission.Context(peelSources: [row3, row4])
        )
        XCTAssertEqual(decision, .skip(.rejoinsPrinted))
    }

    func testAndAlexaJoinsTheSiriLine() {
        let row = "Many people don't realize AI already impacts us, powering many tools we use daily from search engines that predict what we're looking for to voice assistance like Siri."
        let tail = "and Alexa, and even recommendations on Netflix."
        let merged = TranslationClauseSegmenter.appendedContinuation(row: row, unit: tail)
        let key = TranslationClauseSegmenter.normalizedKey(merged ?? "")
        XCTAssertTrue(key.contains("like siri and alexa"), merged ?? "nil")
        XCTAssertTrue(key.hasSuffix("recommendations on netflix"), merged ?? "nil")
        XCTAssertNil(
            TranslationClauseSegmenter.appendedContinuation(
                row: row,
                unit: "Then they're a new generative AI tools like chat GPT."
            )
        )
    }

    func testAShorterCopyOfAPrintedSentenceDoesNotPrintAgain() {
        let printed = "Then they're a new generative AI tools like chat GPT, which expand the horizon of a true computer assistant, AI systems."
        let shorter = "Then they're a new generative AI tools like chat GPT, which expand the horizon of a true computer assistant."
        let onTheBoard = TheaterBoardAdmission.decide(
            shorter,
            languageID: "en",
            phase: .propose,
            context: TheaterBoardAdmission.Context(peelSources: [
                "Many people don't realize AI already impacts us.",
                printed,
            ])
        )
        XCTAssertEqual(onTheBoard, .skip(.printedThisListen))

        let scrolledOff = TheaterBoardAdmission.decide(
            shorter,
            languageID: "en",
            phase: .propose,
            context: TheaterBoardAdmission.Context(
                peelSources: ["As AI evolves, ethical considerations grow, questions about privacy, autonomy and job displacement challenge us to use AI responsibly."],
                commitIdentities: [TranslationClauseSegmenter.clauseIdentity(printed)]
            )
        )
        XCTAssertEqual(scrolledOff, .skip(.printedThisListen))

        let fresh = "Questions about privacy, autonomy and job displacement challenge us to use AI responsibly."
        XCTAssertEqual(
            TheaterBoardAdmission.decide(
                fresh,
                languageID: "en",
                phase: .propose,
                context: TheaterBoardAdmission.Context(commitIdentities: [TranslationClauseSegmenter.clauseIdentity(printed)])
            ),
            .admit
        )
    }

    func testTheArticleReplacesTheSameEnglishLine() {
        XCTAssertTrue(
            TranslationClauseSegmenter.isLeadingArticleRevision(
                previous: "Epstein files.",
                incoming: "The Epstein Files.",
                languageID: "en"
            )
        )
        XCTAssertFalse(
            TranslationClauseSegmenter.isLeadingArticleRevision(
                previous: "Epstein files.",
                incoming: "The Epstein files are out.",
                languageID: "en"
            )
        )
        XCTAssertFalse(
            TranslationClauseSegmenter.isLeadingArticleRevision(
                previous: "Epstein files.",
                incoming: "The Epstein Files.",
                languageID: "ko"
            )
        )
    }

    func testAnAbbreviationPeriodDoesNotEndTheEnglishSentence() {
        let joined = TranslationClauseSegmenter.split(
            "whose alleged crimes have implicated a web of high profile individuals across U.S. politics in Hollywood.",
            languageID: "en"
        )
        XCTAssertEqual(joined.completed.count, 1, joined.completed.joined(separator: " | "))
        XCTAssertTrue(
            TranslationClauseSegmenter.normalizedKey(joined.completed[0]).contains("us politics in hollywood"),
            joined.completed[0]
        )

        let tail = TranslationClauseSegmenter.abbreviationContinuation(
            row: "individuals across U.S.",
            unit: "politics in Hollywood."
        )
        XCTAssertTrue(
            TranslationClauseSegmenter.normalizedKey(tail ?? "").contains("us politics"),
            tail ?? "nil"
        )

        let otherHand = TranslationClauseSegmenter.split(
            "We trained the model. on the other hand it failed.",
            languageID: "en"
        )
        XCTAssertEqual(otherHand.completed.count, 2, otherHand.completed.joined(separator: " | "))
    }

    func testAShortNounPhraseTakesAnLyAdverb() {
        let merged = TranslationClauseSegmenter.adverbialContinuation(
            row: "The Epstein Files.",
            unit: "Deeply shrouded in controversy and secrecy."
        )
        let key = TranslationClauseSegmenter.normalizedKey(merged ?? "")
        XCTAssertTrue(key.contains("epstein files deeply shrouded"), merged ?? "nil")
        XCTAssertNil(
            TranslationClauseSegmenter.adverbialContinuation(
                row: "The Epstein Files.",
                unit: "Investigators found more documents."
            )
        )
        XCTAssertNil(
            TranslationClauseSegmenter.englishRowContinuation(
                row: "The Epstein Files.",
                unit: "Deeply shrouded in controversy and secrecy.",
                languageID: "ko"
            )
        )
    }

    func testDespiteKeepsItsMainClauseInEnglishOnly() {
        let joined = TranslationClauseSegmenter.split(
            "Despite over 250 victims, and clear evidence of a large scale sex trafficking ring. The full extent of the criminal network remains obscured.",
            languageID: "en"
        )
        XCTAssertEqual(joined.completed.count, 1, joined.completed.joined(separator: " | "))
        XCTAssertTrue(
            TranslationClauseSegmenter.normalizedKey(joined.completed[0]).contains("full extent"),
            joined.completed[0]
        )

        let because = TranslationClauseSegmenter.split("Because I said so.", languageID: "en")
        XCTAssertEqual(because.completed.count, 1, because.completed.joined(separator: " | "))

        let then = TranslationClauseSegmenter.split(
            "Because I said so. Then I came back.",
            languageID: "en"
        )
        XCTAssertEqual(then.completed.count, 2, then.completed.joined(separator: " | "))

        let korean = TranslationClauseSegmenter.split(
            "Despite the rain. The match continued.",
            languageID: "ko"
        )
        XCTAssertEqual(korean.completed.count, 2, korean.completed.joined(separator: " | "))

        let koreanTalk = TranslationClauseSegmenter.split(
            "모델을 학습했습니다. 그리고 적용했습니다.",
            languageID: "ko"
        )
        XCTAssertEqual(koreanTalk.completed.count, 2, koreanTalk.completed.joined(separator: " | "))
    }

    func testABecauseLineWithItsMainClauseDoesNotTakeTheNextSentence() {
        let split = TranslationClauseSegmenter.split(
            "Because it rained all day, we stayed home. We played cards.",
            languageID: "en"
        )
        XCTAssertEqual(split.completed.count, 2, split.completed.joined(separator: " | "))

        XCTAssertNil(
            TranslationClauseSegmenter.subordinateContinuation(
                row: "Because the model was trained on far too much data, it overfits.",
                unit: "We fixed that last week."
            )
        )
        XCTAssertNotNil(
            TranslationClauseSegmenter.subordinateContinuation(
                row: "Despite over 250 victims, and clear evidence of a large scale ring.",
                unit: "The full extent remains obscured."
            )
        )
    }

    func testAJoinedSentenceKeepsANameCapitalized() {
        let split = TranslationClauseSegmenter.split(
            "Despite the delay. Biden signed the bill.",
            languageID: "en"
        )
        XCTAssertEqual(split.completed.count, 1, split.completed.joined(separator: " | "))
        XCTAssertTrue(split.completed[0].contains("Biden"), split.completed[0])

        let common = TranslationClauseSegmenter.split(
            "Despite the delay. The files came out.",
            languageID: "en"
        )
        XCTAssertTrue(common.completed.first?.contains(", the files") == true, common.completed.first ?? "nil")

        let merged = TranslationClauseSegmenter.subordinateContinuation(
            row: "Although the team worked through the whole weekend again.",
            unit: "Apple still shipped it late."
        )
        XCTAssertTrue(merged?.contains(", Apple still") == true, merged ?? "nil")
    }
}
