import Foundation

/// Printed-line quality for a stage Listen. Compact scripts use characters;
/// English uses words. This is a local score, not a published SLO.
enum TheaterQualityScore {
    /// Would I show this caption behind a speaker? 15% error or better.
    static let stageAcceptableError = 0.15

    struct Fixture: Equatable {
        let languageID: String
        let spoken: String
        let expectedUnit: String
    }

    static let english = Fixture(
        languageID: "en",
        spoken: "Today we trained the model.",
        expectedUnit: "Today we trained the model."
    )

    static let korean = Fixture(
        languageID: "ko",
        spoken: "오늘 모델을 학습했습니다",
        expectedUnit: "오늘 모델을 학습했습니다"
    )

    static let thai = Fixture(
        languageID: "th",
        spoken: "วันนี้เราฝึกโมเดลครับ",
        expectedUnit: "วันนี้เราฝึกโมเดลครับ"
    )

    static let japanese = Fixture(
        languageID: "ja",
        spoken: "今日はモデルを学習しました",
        expectedUnit: "今日はモデルを学習しました"
    )

    static let stageLanguages: [Fixture] = [Self.english, Self.korean, Self.thai, Self.japanese]

    struct PairFixture: Equatable {
        let sourceLanguageID: String
        let targetLanguageID: String
        let source: String
        let referenceCaption: String
    }

    static let englishToKorean = PairFixture(
        sourceLanguageID: "en",
        targetLanguageID: "ko",
        source: "Today we trained the model.",
        referenceCaption: "오늘 모델을 학습했습니다."
    )

    static let koreanToEnglish = PairFixture(
        sourceLanguageID: "ko",
        targetLanguageID: "en",
        source: "오늘 모델을 학습했습니다",
        referenceCaption: "Today we trained the model."
    )

    static let englishToThai = PairFixture(
        sourceLanguageID: "en",
        targetLanguageID: "th",
        source: "Today we trained the model.",
        referenceCaption: "วันนี้เราฝึกโมเดลครับ"
    )

    static let englishToJapanese = PairFixture(
        sourceLanguageID: "en",
        targetLanguageID: "ja",
        source: "Today we trained the model.",
        referenceCaption: "今日はモデルを学習しました。"
    )

    static let japaneseToEnglish = PairFixture(
        sourceLanguageID: "ja",
        targetLanguageID: "en",
        source: "今日はモデルを学習しました",
        referenceCaption: "Today we trained the model."
    )

    static let stagePairs: [PairFixture] = [
        Self.englishToKorean,
        Self.koreanToEnglish,
        Self.englishToThai,
        Self.englishToJapanese,
        Self.japaneseToEnglish,
    ]

    struct LineScore: Equatable {
        let languageID: String
        let reference: String
        let hypothesis: String
        let error: Double
        let wouldShow: Bool
    }

    struct TalkReport: Equatable, Codable {
        var asrError: Double?
        var translationError: Double?
        var wouldShowASR: Bool
        var wouldShowTranslation: Bool
        var lineCount: Int
        var endToEndMilliseconds: Int?
        var machineTranslationMilliseconds: Int?
    }

    static func scoreLine(reference: String, hypothesis: String, languageID: String) -> LineScore {
        let error: Double
        if Self.compactScripts.contains(TranslationClauseSegmenter.languageCode(from: languageID)) {
            error = self.characterErrorRate(reference: reference, hypothesis: hypothesis)
        } else {
            error = self.wordErrorRate(reference: reference, hypothesis: hypothesis)
        }
        return LineScore(
            languageID: languageID,
            reference: reference,
            hypothesis: hypothesis,
            error: error,
            wouldShow: error <= Self.stageAcceptableError
        )
    }

    static func meanError(_ scores: [LineScore]) -> Double? {
        guard !scores.isEmpty else { return nil }
        return scores.map(\.error).reduce(0, +) / Double(scores.count)
    }

    static func report(
        asr: [(reference: String, hypothesis: String, languageID: String)],
        translations: [(reference: String, hypothesis: String, languageID: String)],
        latency: LastListenLatencyStore.Record? = nil
    ) -> TalkReport {
        let asrScores = asr.map {
            self.scoreLine(reference: $0.reference, hypothesis: $0.hypothesis, languageID: $0.languageID)
        }
        let mtScores = translations.map {
            self.scoreLine(reference: $0.reference, hypothesis: $0.hypothesis, languageID: $0.languageID)
        }
        return TalkReport(
            asrError: self.meanError(asrScores),
            translationError: self.meanError(mtScores),
            wouldShowASR: asrScores.allSatisfy(\.wouldShow),
            wouldShowTranslation: mtScores.allSatisfy(\.wouldShow),
            lineCount: max(asrScores.count, mtScores.count),
            endToEndMilliseconds: latency?.endToEndMilliseconds,
            machineTranslationMilliseconds: latency?.machineTranslationMilliseconds
        )
    }

    static func wordErrorRate(reference: String, hypothesis: String) -> Double {
        self.errorRate(
            reference: Self.tokens(reference),
            hypothesis: Self.tokens(hypothesis)
        )
    }

    static func characterErrorRate(reference: String, hypothesis: String) -> Double {
        self.errorRate(
            reference: Self.compactUnits(reference),
            hypothesis: Self.compactUnits(hypothesis)
        )
    }

    /// Scripts scored by character rather than word. `scripts/score-theater-talk.py`
    /// keeps the same list as `COMPACT`; change one and you have to change both.
    static let compactScripts: Set<String> = ["ko", "th", "ja", "zh"]

    static func isStageAcceptable(
        reference: String,
        hypothesis: String,
        languageID: String
    ) -> Bool {
        let error: Double
        if Self.compactScripts.contains(TranslationClauseSegmenter.languageCode(from: languageID)) {
            error = self.characterErrorRate(reference: reference, hypothesis: hypothesis)
        } else {
            error = self.wordErrorRate(reference: reference, hypothesis: hypothesis)
        }
        return error <= Self.stageAcceptableError
    }

    private static func errorRate<T: Equatable>(reference: [T], hypothesis: [T]) -> Double {
        if reference.isEmpty {
            return hypothesis.isEmpty ? 0 : 1
        }
        return Double(self.editDistance(reference, hypothesis)) / Double(reference.count)
    }

    private static func tokens(_ text: String) -> [String] {
        text
            .lowercased()
            .split { $0.isWhitespace || $0.isPunctuation }
            .map(String.init)
            .filter { !$0.isEmpty }
    }

    /// General categories that carry a letter's identity: letters, numbers, and the
    /// combining marks Thai stacks on top of a base consonant.
    ///
    /// This used to be `Array(text).filter { $0.isLetter || $0.isNumber }`. Two things
    /// were wrong with that. `Array(text)` walks *grapheme clusters*, and
    /// `Character.isLetter` is only true when every scalar in the cluster is a letter,
    /// so a base consonant carrying a vowel sign failed the test and *both* vanished.
    /// `ครับ` and `ครัّบ` are different sentences; both folded to `ครบ` and
    /// scored 0.0. And reading by cluster while *counting* by code point — which is
    /// what `scripts/score-theater-talk.py` does — let the runtime scorer and the
    /// offline scorer disagree about the same Thai line.
    ///
    /// Iterating scalars and keeping the mark categories fixes both. No NFD
    /// decomposition: Thai marks are already separate scalars, and decomposing would
    /// also split every Korean syllable into three jamo, which changes a number that
    /// was not wrong. Keep this in step with the Python twin.
    private static let compareCategories: Set<Unicode.GeneralCategory> = [
        .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter,
        .decimalNumber, .letterNumber, .otherNumber,
        .nonspacingMark, .spacingMark, .enclosingMark,
    ]

    /// Units for a compact-script line: one entry per Unicode scalar, marks kept.
    private static func compactUnits(_ text: String) -> [Unicode.Scalar] {
        Array(text.lowercased().unicodeScalars)
            .filter { Self.compareCategories.contains($0.properties.generalCategory) }
    }

    private static func editDistance<T: Equatable>(_ left: [T], _ right: [T]) -> Int {
        if left.isEmpty { return right.count }
        if right.isEmpty { return left.count }
        var previous = Array(0...right.count)
        var current = Array(repeating: 0, count: right.count + 1)
        for (i, leftItem) in left.enumerated() {
            current[0] = i + 1
            for (j, rightItem) in right.enumerated() {
                let cost = leftItem == rightItem ? 0 : 1
                current[j + 1] = min(
                    previous[j + 1] + 1,
                    current[j] + 1,
                    previous[j] + cost
                )
            }
            swap(&previous, &current)
        }
        return previous[right.count]
    }
}
