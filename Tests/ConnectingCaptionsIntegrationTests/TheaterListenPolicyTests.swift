@testable import ConnectingCaptions_Debug
import XCTest

final class TheaterListenPolicyTests: XCTestCase {
    func testMissingModelDoesNotPrescribeMatchingAnAlreadyMatchingLanguage() {
        let advice = TheaterReadyGate.voiceEngineAdvice(
            model: .whisperBase,
            source: TranslationLanguageCatalog.english,
            heard: TranslationLanguageCatalog.english,
            modelInstalled: false
        )
        XCTAssertTrue(advice.contains("Download Whisper Base"), advice)
        XCTAssertFalse(advice.contains("Match I speak"), advice)
        XCTAssertFalse(advice.contains("not English"), advice)

        let snapshot = TheaterReadyGate.snapshot(
            engineSupportsSource: true,
            modelInstalled: false,
            sameLanguagePair: true,
            pack: .installed,
            microphone: .authorized,
            firstCaptionPrinted: true,
            voiceEngineAdvice: advice
        )
        XCTAssertFalse(snapshot.canListen)
        XCTAssertFalse(snapshot.voiceEngineNeedsRealign)
        XCTAssertEqual(snapshot.nextAction, advice)
    }

    func testPackChecksRejectOutOfOrderResultsAndReturningToAnEarlierPair() {
        let englishKorean = TranslationPairKey(sourceID: "en", targetID: "ko", bidirectional: false, mode: "translation")
        let englishThai = TranslationPairKey(sourceID: "en", targetID: "th", bidirectional: false, mode: "translation")
        var checks = TranslationPairCheck()
        let old = checks.begin(pair: englishKorean)
        let newer = checks.begin(pair: englishThai)
        XCTAssertFalse(checks.accepts(old, currentPair: englishThai))
        XCTAssertTrue(checks.accepts(newer, currentPair: englishThai))

        let returned = checks.begin(pair: englishKorean)
        XCTAssertFalse(checks.accepts(old, currentPair: englishKorean))
        XCTAssertFalse(checks.accepts(newer, currentPair: englishKorean))
        XCTAssertTrue(checks.accepts(returned, currentPair: englishKorean))
        checks.invalidate()
        XCTAssertFalse(checks.accepts(returned, currentPair: englishKorean))
    }

    func testPackChecksIncludeDirectionAndMode() {
        let original = TranslationPairKey(sourceID: "en", targetID: "ko", bidirectional: false, mode: "translation")
        var checks = TranslationPairCheck()
        let request = checks.begin(pair: original)
        XCTAssertFalse(checks.accepts(request, currentPair: TranslationPairKey(
            sourceID: "en", targetID: "ko", bidirectional: true, mode: "translation"
        )))
        XCTAssertFalse(checks.accepts(request, currentPair: TranslationPairKey(
            sourceID: "en", targetID: "ko", bidirectional: false, mode: "transcription"
        )))
    }

    func testVoiceEngineAdviceMatchesWhyTheEngineIsNotReady() throws {
        // Before macOS 26 Analyzer is not an available model, so it has no static routes.
        guard #available(macOS 26.0, *) else { throw XCTSkip("Apple Speech Analyzer needs macOS 26.") }
        let mismatch = TheaterReadyGate.voiceEngineAdvice(
            model: .appleSpeechAnalyzer,
            source: TranslationLanguageCatalog.english,
            heard: TranslationLanguageCatalog.korean
        )
        XCTAssertTrue(mismatch.contains("set to hear Korean"), mismatch)
        XCTAssertFalse(mismatch.contains("older Apple Speech"), mismatch)

        let candidates = [
            TranslationLanguageCatalog.arabic, TranslationLanguageCatalog.chinese,
            TranslationLanguageCatalog.indonesian, TranslationLanguageCatalog.dutch,
            TranslationLanguageCatalog.polish, TranslationLanguageCatalog.french,
        ]
        for language in candidates {
            let analyzer = VoiceEngineLanguageCatalog.supports(.appleSpeechAnalyzer, languageID: language.id)
            let older = VoiceEngineLanguageCatalog.supports(.appleSpeech, languageID: language.id)
            guard !analyzer else { continue }
            let onAnalyzer = TheaterReadyGate.voiceEngineAdvice(model: .appleSpeechAnalyzer, source: language, heard: nil)
            XCTAssertEqual(onAnalyzer.contains("older Apple Speech"), older, onAnalyzer)
            if !older {
                // Already on the older engine: never tell them to pick it.
                let onOlder = TheaterReadyGate.voiceEngineAdvice(model: .appleSpeech, source: language, heard: nil)
                XCTAssertFalse(onOlder.contains("older Apple Speech"), onOlder)
            }
        }

        let blocked = TheaterReadyGate.snapshot(
            engineSupportsSource: false,
            modelInstalled: true,
            sameLanguagePair: true,
            pack: .installed,
            microphone: .authorized,
            firstCaptionPrinted: false,
            voiceEngineAdvice: mismatch
        )
        XCTAssertEqual(blocked.nextAction, mismatch)
    }

    func testReadyGateVoiceAndTranslateUseTheMicrophone() {
        let voiceDenied = TheaterReadyGate.snapshot(
            engineSupportsSource: true,
            modelInstalled: true,
            sameLanguagePair: true,
            pack: .unknown,
            microphone: .denied,
            firstCaptionPrinted: false,
            mode: .transcription
        )
        XCTAssertFalse(voiceDenied.canListen)
        XCTAssertTrue(voiceDenied.nextAction.contains("microphone"))
        XCTAssertTrue(TheaterReadiness.gettingStartedOpenDetail.contains("Voice"))
        XCTAssertTrue(TheaterReadiness.gettingStartedMicrophone.contains("microphone"))

        let voiceReady = TheaterReadyGate.snapshot(
            engineSupportsSource: true,
            modelInstalled: true,
            sameLanguagePair: true,
            pack: .unknown,
            microphone: .authorized,
            firstCaptionPrinted: true,
            mode: .transcription
        )
        XCTAssertTrue(voiceReady.canListen)
        XCTAssertTrue(voiceReady.isFullyReady)

        let osBlocked = TheaterReadyGate.snapshot(
            engineSupportsSource: true,
            modelInstalled: true,
            sameLanguagePair: true,
            pack: .installed,
            microphone: .authorized,
            firstCaptionPrinted: true,
            mode: .translation,
            osSupported: false
        )
        XCTAssertFalse(osBlocked.canListen)
        XCTAssertEqual(osBlocked.nextAction, TheaterAvailability.unsupportedCopy)

        let lecternUndetermined = TheaterReadyGate.snapshot(
            engineSupportsSource: true,
            modelInstalled: true,
            sameLanguagePair: true,
            pack: .installed,
            microphone: .notDetermined,
            firstCaptionPrinted: false
        )
        XCTAssertTrue(lecternUndetermined.canListen)
        XCTAssertFalse(lecternUndetermined.microphoneAllowed)
        XCTAssertEqual(lecternUndetermined.nextAction, TheaterReadiness.allowMicrophone)
        XCTAssertFalse(MicrophoneAccess.isAuthorized(.notDetermined))
        XCTAssertFalse(MicrophoneAccess.isDenied(.notDetermined))
        XCTAssertTrue(MicrophoneAccess.isDenied(.denied))
        XCTAssertTrue(MicrophoneAccess.isDenied(.restricted))
        XCTAssertEqual(MicrophoneAccess.deniedCopy, "Allow the microphone in System Settings.")
    }

    func testMicrophoneReadTimeoutKeepsTheLastRealAnswer() {
        let unanswered = MicrophoneAccess.resolvedDetail(
            read: nil,
            keeping: "",
            currentStatus: .notDetermined
        )
        XCTAssertEqual(unanswered.status, .notDetermined)
        XCTAssertEqual(unanswered.detail, "")

        let staleUndetermined = MicrophoneAccess.resolvedDetail(
            read: .notDetermined,
            keeping: "",
            currentStatus: .authorized
        )
        XCTAssertEqual(staleUndetermined.status, .authorized)
        XCTAssertEqual(staleUndetermined.detail, "")

        let stillAllowed = MicrophoneAccess.resolvedDetail(
            read: nil,
            keeping: "",
            currentStatus: .authorized
        )
        XCTAssertEqual(stillAllowed.status, .authorized)
        XCTAssertEqual(stillAllowed.detail, "")

        let stillDenied = MicrophoneAccess.resolvedDetail(
            read: nil,
            keeping: "",
            currentStatus: .denied
        )
        XCTAssertEqual(stillDenied.status, .denied)
        XCTAssertEqual(stillDenied.detail, MicrophoneAccess.deniedSettingsCopy)

        let refused = MicrophoneAccess.resolvedDetail(
            read: .denied,
            keeping: MicrophoneAccess.promptTimedOutCopy,
            currentStatus: .notDetermined
        )
        XCTAssertEqual(refused.status, .denied)
        XCTAssertEqual(refused.detail, MicrophoneAccess.deniedSettingsCopy)

        let allowedAgain = MicrophoneAccess.resolvedDetail(
            read: .authorized,
            keeping: MicrophoneAccess.deniedSettingsCopy,
            currentStatus: .denied
        )
        XCTAssertEqual(allowedAgain.status, .authorized)
        XCTAssertEqual(allowedAgain.detail, "")
        XCTAssertEqual(
            MicrophoneAccess.failureCopy(detail: MicrophoneAccess.promptTimedOutCopy),
            MicrophoneAccess.promptTimedOutCopy
        )
        XCTAssertTrue(MicrophoneAccess.isMicrophoneFailure(MicrophoneAccess.deniedSettingsCopy))
    }

    func testJunkGateDropsBoilerplateAndPhraseLoops() {
        XCTAssertTrue(CaptionJunkGate.shouldDrop("Thanks for watching.", audioContainsSpeech: false))
        XCTAssertTrue(CaptionJunkGate.shouldDrop("ご視聴ありがとうございました", audioContainsSpeech: false))
        XCTAssertTrue(CaptionJunkGate.shouldDrop("시청해 주셔서 감사합니다.", audioContainsSpeech: false))
        XCTAssertTrue(CaptionJunkGate.shouldDrop("字幕由 Amara.org", audioContainsSpeech: false))
        XCTAssertTrue(CaptionJunkGate.shouldDrop("Subtítulos realizados por Amara", audioContainsSpeech: false))
        XCTAssertTrue(CaptionJunkGate.shouldDrop("Please subscribe.", audioContainsSpeech: false))
        XCTAssertTrue(CaptionJunkGate.shouldDrop("チャンネル登録", audioContainsSpeech: false))
        XCTAssertTrue(CaptionJunkGate.shouldDrop("구독과 좋아요", audioContainsSpeech: false))
        XCTAssertTrue(CaptionJunkGate.shouldDrop("订阅", audioContainsSpeech: false))
        XCTAssertFalse(CaptionJunkGate.shouldDrop("How do I 订阅 this channel?", audioContainsSpeech: false))
        XCTAssertFalse(CaptionJunkGate.shouldDrop("チャンネル登録の方法を説明します。", audioContainsSpeech: false))
        XCTAssertFalse(CaptionJunkGate.shouldDrop("Thank you.", audioContainsSpeech: false))
        XCTAssertFalse(CaptionJunkGate.shouldDrop("감사합니다.", audioContainsSpeech: false))
        XCTAssertTrue(CaptionJunkGate.shouldDrop("감사합니다 감사합니다 감사합니다", audioContainsSpeech: false))
        XCTAssertTrue(CaptionJunkGate.hasPhraseRepeat("hello hello hello"))
        XCTAssertFalse(CaptionJunkGate.shouldDrop("ㅋㅋㅋㅋ", audioContainsSpeech: false))
        XCTAssertFalse(CaptionJunkGate.shouldDrop("ㅎㅎㅎ", audioContainsSpeech: false))
        XCTAssertFalse(CaptionJunkGate.shouldDrop("진짜진짜", audioContainsSpeech: false))
        XCTAssertFalse(CaptionJunkGate.shouldDrop("มากๆ", audioContainsSpeech: false))
        XCTAssertFalse(CaptionJunkGate.shouldDrop("네.", audioContainsSpeech: false))
        XCTAssertFalse(CaptionJunkGate.shouldDrop("ครับ", audioContainsSpeech: false))
        XCTAssertFalse(CaptionJunkGate.shouldDrop("Yes.", audioContainsSpeech: false))
        XCTAssertFalse(CaptionJunkGate.shouldDrop("오늘 모델을 학습했습니다.", audioContainsSpeech: false))
    }

    func testPauseDropsPacketsAndResumeResetsSampleClock() {
        let accepted = SampleBatchSink()
        let pipeline = AudioCapturePipeline(
            audioBuffer: ThreadSafeAudioBuffer(),
            onAcceptedSamples: { accepted.batches.append($0) },
            onFirstAudio: { _, _, _, _, _, _, _ in },
            onLevel: { _ in },
            onSpeechEnergy: { _, _ in },
            onCaptureHealth: { _, _, _, _, _, _ in }
        )
        let samples: [Float] = [0.2, 0.2, 0.2, 0.2]
        let host = mach_absolute_time()
        pipeline.setRecordingEnabled(true, sessionID: 1, attemptID: 1, startHostTime: host)
        samples.withUnsafeBufferPointer { pointer in
            pipeline.handle(
                samples: pointer.baseAddress!,
                frameCount: samples.count,
                sampleRate: 16_000,
                inputHostTime: host,
                inputSampleTime: 0
            )
        }
        XCTAssertEqual(pipeline.lastInputSampleEndForTesting, 4)
        let beforePause = pipeline.audioBuffer.getRetained()
        XCTAssertEqual(beforePause, samples)

        pipeline.setCapturePaused(true)
        samples.withUnsafeBufferPointer { pointer in
            pipeline.handle(
                samples: pointer.baseAddress!,
                frameCount: samples.count,
                sampleRate: 16_000,
                inputHostTime: mach_absolute_time(),
                inputSampleTime: 4000
            )
        }
        XCTAssertEqual(pipeline.lastInputSampleEndForTesting, 4)
        XCTAssertEqual(pipeline.audioBuffer.getRetained(), beforePause)

        pipeline.setCapturePaused(false)
        XCTAssertNil(pipeline.lastInputSampleEndForTesting)
        XCTAssertEqual(pipeline.audioBuffer.getRetained(), beforePause)
        samples.withUnsafeBufferPointer { pointer in
            pipeline.handle(
                samples: pointer.baseAddress!,
                frameCount: samples.count,
                sampleRate: 16_000,
                inputHostTime: mach_absolute_time(),
                inputSampleTime: 0
            )
        }
        XCTAssertEqual(pipeline.lastInputSampleEndForTesting, 4)
        let wallCount = LiveAudioRetention.resumeSilenceWallSamples
        let retained = pipeline.audioBuffer.getRetained()
        XCTAssertEqual(retained.count, beforePause.count + wallCount + samples.count)
        XCTAssertEqual(Array(retained.prefix(beforePause.count)), beforePause)
        XCTAssertEqual(
            Array(retained.dropFirst(beforePause.count).prefix(wallCount)),
            Array(repeating: Float(0), count: wallCount)
        )
        XCTAssertEqual(Array(retained.suffix(samples.count)), samples)
        XCTAssertEqual(accepted.batches, [samples, samples])
    }

    func testStoredWatchModeResolvesToVoice() {
        XCTAssertEqual(TheaterSessionMode.resolved("watch"), .transcription)
        XCTAssertEqual(TheaterSessionMode.resolved("lectern"), .translation)
    }

    func testTheaterStatusColors() {
        XCTAssertFalse(TheaterStatusKind.success.usesWarningColor)
        XCTAssertTrue(TheaterStatusKind.failure.usesWarningColor)
        XCTAssertTrue(TheaterStatusKind.warning.usesWarningColor)
        XCTAssertEqual(TheaterStatus.success("Heard").kind, .success)
        XCTAssertEqual(TheaterStatus.failure("Denied").kind, .failure)
        XCTAssertEqual(
            LiveTranslationCommitContext.peeledNewTranslation(
                "Hello world. Next sentence.",
                priorTranslations: ["Hello world."],
                targetID: "en"
            ),
            "Next sentence."
        )
    }

    @MainActor
    func testTheaterListenKeepsTheWordPeriod() {
        let settings = SettingsStore.shared
        let punctuation = settings.autoConvertPunctuationEnabled
        let fillers = settings.removeFillerWordsEnabled
        settings.autoConvertPunctuationEnabled = true
        settings.removeFillerWordsEnabled = true
        defer {
            settings.autoConvertPunctuationEnabled = punctuation
            settings.removeFillerWordsEnabled = fillers
        }

        let spoken = "We finished the period um"
        let theater = ASRService.textForTheaterListen(spoken)
        XCTAssertEqual(theater, ASRService.applyCustomDictionary(spoken))
        XCTAssertTrue(theater.contains("period"))
        XCTAssertTrue(theater.contains("um"))
    }

    @MainActor
    func testTheaterListenDoesNotPauseMediaOrChime() {
        XCTAssertFalse(
            TheaterListenCapture.shouldPauseMedia(policyPausesMedia: false, settingEnabled: true)
        )
        XCTAssertFalse(
            TheaterListenCapture.shouldPauseMedia(policyPausesMedia: nil, settingEnabled: true)
        )
        XCTAssertFalse(
            TheaterListenCapture.shouldPauseMedia(policyPausesMedia: nil, settingEnabled: false)
        )
        XCTAssertFalse(TheaterListenCapture.shouldPlayListenChime(policyPlaysChime: false))
        XCTAssertFalse(TheaterListenCapture.shouldPlayListenChime(policyPlaysChime: nil))
        XCTAssertFalse(TheaterSpeechSession.shared.playsListenChime)
        XCTAssertFalse(TheaterSpeechSession.shared.pausesMedia)
    }

    @MainActor
    func testParakeetCaptionWindowIgnoresFasterLongDictationToggle() {
        let settings = SettingsStore.shared
        let original = settings.experimentalParakeetUnifiedFinalEnabled
        defer { settings.experimentalParakeetUnifiedFinalEnabled = original }

        settings.experimentalParakeetUnifiedFinalEnabled = true
        XCTAssertEqual(FluidAudioProvider().streamingPreviewMode, .trailingWindow)
        settings.experimentalParakeetUnifiedFinalEnabled = false
        XCTAssertEqual(FluidAudioProvider().streamingPreviewMode, .trailingWindow)
    }

    func testSettingsSearchDropsDictationListenCleanup() {
        XCTAssertFalse(
            SettingsSearchIndex.results(for: "Faster Long Dictation")
                .contains { $0.target == .fasterLongDictation }
        )
        XCTAssertFalse(
            SettingsSearchIndex.results(for: "Transcription Sounds")
                .contains { $0.target == .transcriptionSounds }
        )
        XCTAssertFalse(
            SettingsSearchIndex.results(for: "Pause Media During Transcription")
                .contains { $0.target == .pauseMedia }
        )
    }
}

private final class SampleBatchSink {
    var batches: [[Float]] = []
}


final class FaithfulCaptionContentTests: XCTestCase {
    func testQuotedCreditsAndSpokenOutrosAreNotDroppedWithoutSilenceEvidence() {
        let lines = ["The phrase thank you for watching appears at the end of our training video.",
                     "Thank you for watching.", "ご視聴ありがとうございました", "시청해 주셔서 감사합니다.",
                     "hello hello hello"]
        for line in lines {
            XCTAssertFalse(CaptionJunkGate.shouldDrop(line))
            XCTAssertFalse(CaptionJunkGate.shouldDrop(line, audioContainsSpeech: true))
        }
        let quoted = lines[0]
        XCTAssertEqual(TheaterBoardAdmission.decide(quoted, languageID: "en", phase: .propose,
                                                    context: .init(audioContainsSpeech: true)), .admit)
        XCTAssertTrue(CaptionJunkGate.shouldDrop("Thank you for watching.", audioContainsSpeech: false))
    }

    func testSuccessfulInvariantTranslationsPreserveNamesNumbersAndAcronyms() {
        for text in ["Barack Obama.", "NASA", "12345", "OpenAI", "Bangkok 2026"] {
            XCTAssertEqual(LiveTranslationCaptionGate.captionSafeForBoard(text, sourceText: text), text)
        }
        XCTAssertNil(LiveTranslationCaptionGate.captionSafeForBoard("Error: quota exceeded", sourceText: "Barack Obama."))
    }
}
