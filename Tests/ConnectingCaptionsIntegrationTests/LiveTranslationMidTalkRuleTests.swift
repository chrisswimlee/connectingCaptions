import XCTest
@testable import ConnectingCaptions_Debug

/// One answer to "when does this line print?" for every screen. Mac Theater,
/// Pro iOS, and the App Store app all call `nextMidTalkUnit` mid-talk and
/// `nextCommitUnit` at a pause. The App Store repo runs the same cases.
@MainActor
final class LiveTranslationMidTalkRuleTests: XCTestCase {
    private let s = TranslationClauseSegmenter.self

    func testAShortThaiParticleClauseIsRefusedAloneAndWhenMoreSpeechFollows() {
        XCTAssertNil(self.s.nextCommitUnit("ดีนะ", languageID: "th", allowPauseFinalize: true))
        let spoken = "ดีนะ วันนี้เราจะเรียนเรื่องใหม่ครับ"
        let split = self.s.split(spoken, languageID: "th")
        XCTAssertFalse(split.completed.contains("ดีนะ"), "ดีนะ must not peel as its own clause")
        XCTAssertEqual(self.s.midTalkUnits(spoken, languageID: "th").units, [spoken])
    }

    func testALongThaiParticleClausePrintsMidTalkAndAtAPause() {
        let first = "วันนี้เราจะเรียนเรื่องการฝึกโมเดลใหม่แล้ว"
        let spoken = first + " จากนั้นเราจะทดสอบครับ"
        XCTAssertEqual(self.s.nextMidTalkUnit(spoken, languageID: "th")?.unit, first)
        XCTAssertEqual(self.s.nextCommitUnit(first, languageID: "th", allowPauseFinalize: true)?.unit, first)
    }

    func testARunOnPrintsMidTalkAtTheDraftLimitEvenWhenTheCutBacksUpToASpace() {
        let runOn = Array(repeating: "we keep talking about the model", count: 10).joined(separator: " ")
        guard let next = self.s.nextMidTalkUnit(runOn, languageID: "en") else {
            return XCTFail("A run-on past maxDraftCharacters must print mid-talk")
        }
        XCTAssertLessThan(next.unit.count, LiveTranslationTiming.maxDraftCharacters)
        XCTAssertTrue(self.s.canCommitMidTalk(next.unit, rest: next.rest, languageID: "en"))
    }

    func testMidTalkDoesNotUseThePauseFollowAlongCut() {
        let thai = String(repeating: "การเรียนรู้ของเครื่อง", count: 5)
        XCTAssertGreaterThanOrEqual(thai.count, LiveTranslationTiming.maxLineCharacters)
        XCTAssertLessThan(thai.count, LiveTranslationTiming.maxDraftCharacters)
        XCTAssertNil(self.s.nextMidTalkUnit(thai, languageID: "th"))
        XCTAssertNotNil(self.s.nextCommitUnit(thai, languageID: "th", allowPauseFinalize: true))
    }

    func testAThinStarterIsNotItsOwnMidTalkLine() {
        let drained = self.s.midTalkUnits("It. Then we trained the model. And", languageID: "en")
        XCTAssertEqual(drained.units, ["It. Then we trained the model."])
        XCTAssertEqual(drained.open, "And")
    }

    func testRecognizerSegmentsJoinTheSameWayOnEveryScreen() {
        XCTAssertEqual(RecognizedSegmentJoin.join("วันนี้", "เรา"), "วันนี้เรา")
        XCTAssertEqual(RecognizedSegmentJoin.join("今日は。", "晴れ"), "今日は。晴れ")
        XCTAssertEqual(RecognizedSegmentJoin.join("오늘은", "날씨가"), "오늘은 날씨가")
        XCTAssertEqual(RecognizedSegmentJoin.join("Hello,", "and welcome."), "Hello, and welcome.")
        XCTAssertEqual(RecognizedSegmentJoin.join("วันนี้", "AI"), "วันนี้ AI")
    }

    func testACompactLineWithAnEnglishTokenStaysThatLanguage() {
        XCTAssertFalse(self.s.isTooThinToCommit("วันนี้ AI ครับ", languageID: "th"))
        XCTAssertFalse(self.s.isTooThinToCommit("今天的AI模型", languageID: "zh"))
        XCTAssertTrue(self.s.isTooThinToCommit("ก", languageID: "th"))
        XCTAssertTrue(self.s.isTooThinToCommit("It.", languageID: "th"))
        XCTAssertTrue(self.s.isTooThinToCommit("It.", languageID: "ja"))
        XCTAssertTrue(self.s.isTooThinToCommit("It.", languageID: "en"))
    }

    func testChineseRunOnBreaksAtASentenceStarter() {
        let first = "我们今天把这个语音模型训练完成了"
        XCTAssertGreaterThanOrEqual(first.count, 16)
        let spoken = first + "所以接下来会测试"
        XCTAssertEqual(self.s.unpunctuatedSentenceBreak(spoken, languageID: "zh")?.unit, first)
        XCTAssertEqual(self.s.unpunctuatedSentenceBreak(spoken, languageID: "zh")?.rest, "所以接下来会测试")
        XCTAssertNil(self.s.unpunctuatedSentenceBreak("模型所以", languageID: "zh"))
        XCTAssertEqual(
            self.s.nextMidTalkUnit(spoken, languageID: "zh")?.unit,
            first
        )
    }

    /// Every menu language prints a finished line while talking, and uses the
    /// 80-character / 12-word cut only at a pause. Languages Apple Translation
    /// cannot pair stay off the menu.
    func testEveryOfferedLanguageUsesOnePrintRule() {
        let offered = Set(TranslationLanguageCatalog.all.map(\.id))
        XCTAssertEqual(
            offered,
            [
                "ar", "de", "en", "es", "fr", "hi", "id", "it", "ja", "ko",
                "nl", "pl", "pt", "ru", "th", "tr", "uk", "vi", "zh",
            ]
        )
        for cut in ["da", "fi", "he", "ms", "nb", "sv", "yue"] {
            XCTAssertNil(TranslationLanguageCatalog.language(id: cut), cut)
        }
        let finished = [
            "en": "We trained the model today.",
            "ko": "모델을 학습했습니다.",
            "ja": "モデルを学習しました。",
            "th": "เราฝึกโมเดลครับ",
            "ar": "هذا النموذج جاهز؟",
            "zh": "我们训练了这个模型。",
            "nl": "We hebben het model getraind.",
            "fr": "Nous avons formé le modèle.",
            "de": "Wir haben das Modell trainiert.",
            "hi": "मॉडल तैयार है।",
            "id": "Kami melatih modelnya.",
            "it": "Abbiamo addestrato il modello.",
            "pl": "Wytrenowaliśmy model.",
            "pt": "Treinámos o modelo.",
            "ru": "Мы обучили модель.",
            "es": "Entrenamos el modelo.",
            "tr": "Modeli eğittik.",
            "uk": "Ми навчили модель.",
            "vi": "Chúng tôi đã huấn luyện mô hình.",
        ]
        XCTAssertEqual(Set(finished.keys), offered)
        for (id, line) in finished {
            XCTAssertTrue(self.s.looksComplete(line, languageID: id), id)
            XCTAssertEqual(self.s.nextMidTalkUnit(line, languageID: id)?.unit, line, id)
        }
        let openWords = "one two three four five six"
        for id in offered where !self.s.isCompactScript(id) {
            XCTAssertNil(self.s.nextMidTalkUnit(openWords, languageID: id), id)
            XCTAssertNil(
                self.s.nextCommitUnit(openWords, languageID: id, allowPauseFinalize: false),
                id
            )
            XCTAssertNotNil(
                self.s.nextCommitUnit(openWords, languageID: id, allowPauseFinalize: true),
                id
            )
        }
        let openCompact = String(repeating: "学", count: LiveTranslationTiming.maxLineCharacters)
        for id in offered where self.s.isCompactScript(id) {
            XCTAssertNil(self.s.nextMidTalkUnit(openCompact, languageID: id), id)
            XCTAssertNil(
                self.s.nextCommitUnit(openCompact, languageID: id, allowPauseFinalize: false),
                id
            )
            XCTAssertNotNil(
                self.s.nextCommitUnit(openCompact, languageID: id, allowPauseFinalize: true),
                id
            )
        }
    }

    /// One row per offered language. `splits` must break before `head` ends.
    /// `holds` must stay one line. A failure names the language.
    func testEachOfferedLanguageCutsAndHolds() {
        let hindi = "हमने आज सुबह कक्षा में इस नए मॉडल को बहुत ध्यान से तैयार किया है"
        let chinese = "我们今天把这个语音模型训练完成了"
        let plain = "今日のポイントはモデルの再学習だ"
        let rows: [(id: String, splits: String, head: String, holds: String, pause: Bool)] = [
            ("en", "We trained the model. Then we applied it today.", "We trained the model.", "We meet at 9 a.m. we start the class today", false),
            ("ko", "지금 갈까요 다음으로 갑니다", "지금 갈까요", "오늘 모델을 학습하고", false),
            ("ja", "見てください それから行きます", "見てください", "そうだ", false),
            ("th", "เราฝึกโมเดลครับ จากนั้นเราทดสอบ", "เราฝึกโมเดลครับ", "ดีนะ", false),
            ("zh", chinese + "然後接下來會測試", chinese, "模型然後", false),
            ("de", "Wir treffen uns am 3. Oktober. Dann kam der Test.", "Wir treffen uns am 3. Oktober.", "Das gilt z.B. für das Modell heute", false),
            ("hi", hindi + " और फिर हम आगे बढ़ेंगे", hindi, "यह है", false),
            ("tr", "Modeli eğittik. Sonra test ettik bugün.", "Modeli eğittik.", "Modeli eğittik sonra bugün", false),
            ("ar", "هذا النموذج جاهز؟ ثم نبدأ اليوم.", "هذا النموذج جاهز؟", "هذا النموذج جاهز اليوم", false),
            ("nl", "We hebben het model getraind. Daarna testen we het.", "We hebben het model getraind.", "We hebben het model getraind vandaag", false),
            ("fr", "Nous avons formé le modèle. Puis nous l'avons appliqué.", "Nous avons formé le modèle.", "Nous avons formé le modèle et nous continuons", false),
            ("id", "Kami melatih modelnya hari ini. Lalu kami mengujinya.", "Kami melatih modelnya hari ini.", "Kami melatih modelnya hari ini juga", false),
            ("it", "Abbiamo addestrato il modello. Poi lo abbiamo provato.", "Abbiamo addestrato il modello.", "Abbiamo addestrato il modello oggi", false),
            ("pl", "Wytrenowaliśmy model dzisiaj. Potem go sprawdziliśmy.", "Wytrenowaliśmy model dzisiaj.", "Wytrenowaliśmy model dzisiaj rano", false),
            ("pt", "Treinámos o modelo hoje. Depois testámos o resultado.", "Treinámos o modelo hoje.", "Treinámos o modelo hoje de manhã", false),
            ("ru", "Мы обучили модель сегодня. Потом мы проверили её.", "Мы обучили модель сегодня.", "Мы обучили модель сегодня утром", false),
            ("es", "Hoy entrenamos el modelo ¿lo aplicamos ahora?", "Hoy entrenamos el modelo", "Hoy entrenamos el modelo lo aplicamos ahora", false),
            ("uk", "Ми навчили модель сьогодні. Потім ми перевірили її.", "Ми навчили модель сьогодні.", "Ми навчили модель сьогодні вранці", false),
            (
                "vi",
                Array(repeating: "từ", count: 20).joined(separator: " "),
                Array(repeating: "từ", count: 18).joined(separator: " "),
                Array(repeating: "từ", count: 13).joined(separator: " "),
                true
            ),
        ]
        XCTAssertEqual(Set(rows.map(\.id)), Set(TranslationLanguageCatalog.all.map(\.id)))
        for row in rows {
            let cut = self.s.nextCommitUnit(row.splits, languageID: row.id, allowPauseFinalize: row.pause)
            XCTAssertEqual(cut?.unit, row.head, row.id)
            XCTAssertFalse(cut?.rest.isEmpty ?? true, row.id)
            let held = self.s.nextCommitUnit(row.holds, languageID: row.id, allowPauseFinalize: row.pause)
            if row.pause {
                XCTAssertEqual(held?.unit, row.holds, row.id)
                XCTAssertEqual(held?.rest, "", row.id)
            } else if let held {
                XCTAssertEqual(held.unit, row.holds, row.id)
                XCTAssertTrue(held.rest.isEmpty, row.id)
            }
        }

        for sample in [
            "Das gilt z.B. für das neue Modell.",
            "Das ist bzw. ein gutes Modell.",
            "Lesen Sie das Modell usw. heute noch.",
            "Dr. Schmidt kam heute an.",
            "We meet at 9 a.m. we start the class.",
            "We meet at 9 a.m. We start the class.",
            "We meet at 9 p.m. we start the class.",
            "Read the note, e.g. the model works.",
            "Read the note, e.g. The model works.",
            "Read the note, i.e. the model works.",
            "Compare this vs. the other model.",
            "Ask Prof. Smith before the class.",
        ] {
            let language = sample.contains("Das") || sample.contains("Lesen") || sample.contains("Dr.") ? "de" : "en"
            XCTAssertEqual(self.s.split(sample, languageID: language).completed, [sample], sample)
        }
        XCTAssertEqual(self.s.split("He lives in the U.S. We left the next day.", languageID: "en").completed, [
            "He lives in the U.S.",
            "We left the next day.",
        ])
        XCTAssertGreaterThanOrEqual(plain.filter { !$0.isWhitespace }.count, 16)
        XCTAssertTrue(self.s.looksComplete(plain, languageID: "ja"))
        XCTAssertEqual(
            self.s.nextCommitUnit(plain + " それから適用します", languageID: "ja", allowPauseFinalize: false)?.unit,
            plain
        )
        XCTAssertTrue(self.s.looksComplete("지금 가나요", languageID: "ko"))
        XCTAssertTrue(self.s.looksComplete("지금 가지요", languageID: "ko"))
        XCTAssertTrue(self.s.looksComplete("지금 간대요", languageID: "ko"))
        XCTAssertTrue(self.s.looksComplete(hindi, languageID: "hi"))
        XCTAssertFalse(self.s.continuesAsNewSentence("und dann kamen wir heute", languageID: "de"))
        XCTAssertFalse(self.s.continuesAsNewSentence("et nous l'avons appliqué aujourd'hui", languageID: "fr"))
        XCTAssertFalse(self.s.continuesAsNewSentence("y lo aplicamos hoy mismo", languageID: "es"))
        XCTAssertTrue(self.s.continuesAsNewSentence("and we applied it today", languageID: "fr"))
        XCTAssertEqual(
            self.s.nextCommitUnit(
                "Hoy entrenamos el modelo ¡mira el resultado ahora!",
                languageID: "es",
                allowPauseFinalize: false
            )?.unit,
            "Hoy entrenamos el modelo"
        )
        XCTAssertTrue(
            self.s.unpunctuatedSentenceBreak(chinese + "接下來會測試", languageID: "zh")?.rest.hasPrefix("接下來") ?? false
        )
        let syllables = String(repeating: "ừ", count: 81)
        XCTAssertEqual(
            self.s.nextCommitUnit(syllables, languageID: "vi", allowPauseFinalize: true)?.unit.count,
            LiveTranslationTiming.maxLineCharacters
        )
    }
}
