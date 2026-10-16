@testable import ConnectingCaptions_Debug
import XCTest
import AppKit

final class AppleSpeechLocaleTests: XCTestCase {
    func testAnalyzerLocalesAreKoreanEnglishThaiJapanese() {
        XCTAssertEqual(VoiceEngineLanguageCatalog.preferredAppleSpeechAnalyzerLocale(forLanguageID: "en"), "en-US")
        XCTAssertEqual(VoiceEngineLanguageCatalog.preferredAppleSpeechAnalyzerLocale(forLanguageID: "ko"), "ko-KR")
        XCTAssertEqual(VoiceEngineLanguageCatalog.preferredAppleSpeechAnalyzerLocale(forLanguageID: "th"), "th-TH")
        XCTAssertEqual(VoiceEngineLanguageCatalog.preferredAppleSpeechAnalyzerLocale(forLanguageID: "ja"), "ja-JP")
        XCTAssertEqual(VoiceEngineLanguageCatalog.appleSpeechAnalyzerLocaleIdentifier(for: "fr"), "fr-FR")
        XCTAssertEqual(VoiceEngineLanguageCatalog.appleSpeechAnalyzerLocaleIdentifier(for: "zh"), "zh-CN")
        // Danish is not a product language: Apple Translation has no supported pairing for it.
        XCTAssertNil(VoiceEngineLanguageCatalog.appleSpeechAnalyzerLocaleIdentifier(for: "da"))
        XCTAssertEqual(VoiceEngineLanguageCatalog.preferredAppleSpeechAnalyzerLocale(forLanguageID: "fr"), "fr-FR")
        XCTAssertEqual(VoiceEngineLanguageCatalog.preferredAppleSpeechAnalyzerLocale(forLanguageID: "da"), "en-US")
    }

    func testAnalyzerDropsAPreparedLocaleThatIsNotISpeak() {
        guard #available(macOS 26.0, *) else { return }
        let settings = SettingsStore.shared
        let original = settings.translationSourceLanguageID
        defer { settings.translationSourceLanguageID = original }
        settings.translationSourceLanguageID = "ko"

        let provider = AppleSpeechAnalyzerProvider()
        provider.markPreparedLocaleForTesting("en-US")
        XCTAssertTrue(provider.isReady)
        provider.invalidateIfListeningLanguageChanged()
        XCTAssertFalse(provider.isReady)

        provider.markPreparedLocaleForTesting("ko-KR")
        provider.invalidateIfListeningLanguageChanged()
        XCTAssertTrue(provider.isReady)
    }

    func testAnalyzerMatchesLanguagePrefixNotExactMacLocale() {
        let supported = ["en-US", "ko-KR", "th-TH"]
        XCTAssertEqual(
            VoiceEngineLanguageCatalog.resolveAppleSpeechAnalyzerLocale(
                preferredIdentifier: "en",
                languageID: "en",
                supportedIdentifiers: supported
            ),
            "en-US"
        )
        XCTAssertEqual(
            VoiceEngineLanguageCatalog.resolveAppleSpeechAnalyzerLocale(
                preferredIdentifier: "en-GB",
                languageID: "en",
                supportedIdentifiers: supported
            ),
            "en-US"
        )
        XCTAssertEqual(
            VoiceEngineLanguageCatalog.resolveAppleSpeechAnalyzerLocale(
                preferredIdentifier: "ko",
                languageID: "ko",
                supportedIdentifiers: supported
            ),
            "ko-KR"
        )
    }

    func testAnalyzerIgnoresMacLocaleWhenISpeakIsDifferent() {
        let supported = ["en-US", "ko-KR", "ja-JP", "sv-SE"]
        XCTAssertEqual(
            VoiceEngineLanguageCatalog.resolveAppleSpeechAnalyzerLocale(
                preferredIdentifier: "sv-SE",
                languageID: "en",
                supportedIdentifiers: supported
            ),
            "en-US"
        )
        XCTAssertEqual(
            VoiceEngineLanguageCatalog.resolveAppleSpeechAnalyzerLocale(
                preferredIdentifier: "ja-JP",
                languageID: "ko",
                supportedIdentifiers: supported
            ),
            "ko-KR"
        )
    }

    func testAnalyzerReturnsNilWhenLanguageIsMissing() {
        XCTAssertNil(
            VoiceEngineLanguageCatalog.resolveAppleSpeechAnalyzerLocale(
                preferredIdentifier: "th-TH",
                languageID: "th",
                supportedIdentifiers: ["en-US", "ko-KR"]
            )
        )
    }

    func testPinAppleSpeechFollowsISpeak() {
        let settings = SettingsStore.shared
        let originalModel = settings.selectedSpeechModel
        let originalSource = settings.translationSourceLanguageID
        let originalLocale = settings.selectedAppleSpeechLocaleIdentifier
        defer {
            settings.selectedSpeechModel = originalModel
            settings.translationSourceLanguageID = originalSource
            settings.selectedAppleSpeechLocaleIdentifier = originalLocale
        }

        settings.selectedSpeechModel = .appleSpeechAnalyzer
        settings.translationSourceLanguageID = "ko"
        settings.selectedAppleSpeechLocaleIdentifier = "sv-SE"
        SpokenLanguageResolver.pinAppleSpeechToSpokenSource(settings: settings)
        XCTAssertEqual(settings.selectedAppleSpeechLocaleIdentifier, "ko-KR")

        settings.translationSourceLanguageID = "ja"
        settings.selectedAppleSpeechLocaleIdentifier = "en-US"
        SpokenLanguageResolver.pinAppleSpeechToSpokenSource(settings: settings)
        XCTAssertEqual(settings.selectedAppleSpeechLocaleIdentifier, "ja-JP")

        settings.selectedSpeechModel = .whisperSmall
        settings.translationSourceLanguageID = "th"
        settings.selectedAppleSpeechLocaleIdentifier = "en-US"
        SpokenLanguageResolver.pinAppleSpeechToSpokenSource(settings: settings)
        XCTAssertEqual(settings.selectedAppleSpeechLocaleIdentifier, "th-TH")
    }

    /// A Whisper user moved onto Apple Speech must not keep a stale Apple locale.
    func testPinningToAppleAlsoMatchesTheLocaleToISpeak() throws {
        try XCTSkipUnless(SettingsStore.SpeechModel.appleSpeechOnly)
        let settings = SettingsStore.shared
        let originalModel = settings.selectedSpeechModel
        let originalSource = settings.translationSourceLanguageID
        let originalLocale = settings.selectedAppleSpeechLocaleIdentifier
        defer {
            settings.selectedSpeechModel = originalModel
            settings.translationSourceLanguageID = originalSource
            settings.selectedAppleSpeechLocaleIdentifier = originalLocale
        }

        settings.translationSourceLanguageID = "ko"
        settings.selectedAppleSpeechLocaleIdentifier = "en-US"
        settings.selectedSpeechModel = .whisperTiny
        settings.pinSpeechModelToAppleIfNeeded()
        XCTAssertEqual(settings.selectedSpeechModel, SettingsStore.SpeechModel.defaultModel)
        XCTAssertEqual(settings.selectedAppleSpeechLocaleIdentifier, "ko-KR")
        XCTAssertTrue(SpokenLanguageResolver.voiceEngineSupportsSource(settings: settings))
    }

    func testEitherWayWhisperAddOnIsNotPinnedToApple() throws {
        try XCTSkipUnless(SettingsStore.SpeechModel.appleSpeechOnly)
        let settings = SettingsStore.shared
        let originalModel = settings.selectedSpeechModel
        defer { settings.selectedSpeechModel = originalModel }

        settings.selectedSpeechModel = .whisperSmall
        settings.pinSpeechModelToAppleIfNeeded()
        XCTAssertEqual(settings.selectedSpeechModel, .whisperSmall)
        XCTAssertTrue(SettingsStore.SpeechModel.availableModels.contains(.whisperSmall))
        XCTAssertFalse(SettingsStore.SpeechModel.availableModels.contains(.whisperTiny))
        XCTAssertFalse(SettingsStore.SpeechModel.availableModels.contains(.parakeetTDTv2))
    }

    func testVoiceEngineDefaultsToAnalyzerOtherwiseAppleSpeech() throws {
        try XCTSkipUnless(SettingsStore.SpeechModel.appleSpeechOnly)
        let expected = SettingsStore.SpeechModel.defaultModel
        XCTAssertTrue(expected == .appleSpeechAnalyzer || expected == .appleSpeech)
        if SettingsStore.SpeechModel.availableModels.contains(.appleSpeechAnalyzer) {
            XCTAssertEqual(expected, .appleSpeechAnalyzer)
        } else {
            XCTAssertEqual(expected, .appleSpeech)
        }

        let settings = SettingsStore.shared
        let originalModel = settings.selectedSpeechModel
        let originalSource = settings.translationSourceLanguageID
        defer {
            settings.selectedSpeechModel = originalModel
            settings.translationSourceLanguageID = originalSource
        }

        settings.selectedSpeechModel = .appleSpeech
        SpokenLanguageResolver.setSourceLanguage(try XCTUnwrap(TranslationLanguageCatalog.language(id: "ko")), settings: settings)
        SpokenLanguageResolver.setSourceLanguage(try XCTUnwrap(TranslationLanguageCatalog.language(id: "da")), settings: settings)
        XCTAssertEqual(settings.selectedSpeechModel, .appleSpeech)

        settings.selectedSpeechModel = .parakeetTDTv2
        settings.pinSpeechModelToAppleIfNeeded()
        XCTAssertEqual(settings.selectedSpeechModel, expected)
        XCTAssertFalse(
            SettingsStore.SpeechModel.availableModels.contains {
                $0.provider != .apple && $0 != SettingsStore.SpeechModel.eitherWayAddOn
            }
        )

        settings.selectedSpeechModel = .appleSpeech
        settings.pinSpeechModelToAppleIfNeeded()
        XCTAssertEqual(settings.selectedSpeechModel, .appleSpeech)
        XCTAssertTrue(VoiceEngineLanguageCatalog.supports(.appleSpeech, languageID: "da"))
    }

    func testAppleSpeechEnUSIsTheSameLanguageAsISpeakEnglish() {
        let settings = SettingsStore.shared
        let originalModel = settings.selectedSpeechModel
        let originalSource = settings.translationSourceLanguageID
        let originalLocale = settings.selectedAppleSpeechLocaleIdentifier
        defer {
            settings.selectedSpeechModel = originalModel
            settings.translationSourceLanguageID = originalSource
            settings.selectedAppleSpeechLocaleIdentifier = originalLocale
        }

        settings.selectedSpeechModel = .appleSpeech
        settings.translationSourceLanguageID = "en"
        settings.selectedAppleSpeechLocaleIdentifier = "en-US"

        XCTAssertEqual(SpokenLanguageResolver.spokenLanguageID(settings: settings), "en")
        XCTAssertEqual(SpokenLanguageResolver.heardLanguage(settings: settings)?.id, "en")
        XCTAssertTrue(SpokenLanguageResolver.voiceEngineSupportsSource(settings: settings))
        XCTAssertNil(SpokenLanguageResolver.voiceEngineMismatchMessage(settings: settings))
    }
}


@MainActor
final class VoiceEngineLanguageReadinessTests: XCTestCase {
    func testCapabilityLabelsAndGuidanceAreInTheInterfaceCatalog() {
        for text in [
            "Supported languages", "Ready on this Mac", "Download speech language",
            "Download {0} for {1} in Voice Engine before Listen.",
            "{0} cannot hear {1} offline on this Mac. Choose a supported language or another Voice Engine.",
        ] {
            XCTAssertTrue(AppInterfaceCatalog.strings.contains(text), text)
        }
    }

    func testBuiltInDoesNotMeanLanguageAssetsInstalled() {
        XCTAssertEqual(VoiceEngineLanguageReadiness.evaluate(supported: true, installed: false), .needsDownload)
        XCTAssertEqual(VoiceEngineLanguageReadiness.evaluate(supported: true, installed: true), .ready)
    }

    func testUnsupportedLanguageCannotBeMadeReadyByDownloadedAssets() {
        XCTAssertEqual(VoiceEngineLanguageReadiness.evaluate(supported: false, installed: true), .unsupported)
        XCTAssertEqual(VoiceEngineLanguageReadiness.evaluate(supported: false, installed: false), .unsupported)
    }

    func testUnverifiedCapabilitiesDoNotEnableListen() {
        XCTAssertEqual(VoiceEngineLanguageReadiness.evaluate(supported: nil, installed: true), .checking)
        XCTAssertEqual(VoiceEngineLanguageReadiness.evaluate(supported: true, installed: nil), .checking)
        XCTAssertEqual(
            VoiceEngineLanguageReadiness.evaluate(supported: nil, installed: true, permissionRequired: true),
            .permissionRequired
        )
    }

    func testThaiIsExcludedWhenLegacyRecognizerCannotHearItOffline() {
        let original = AppleSpeechLiveCapability.legacyLanguagePrefixes
        defer { AppleSpeechLiveCapability.setLegacyLanguagePrefixesForTesting(original) }
        AppleSpeechLiveCapability.setLegacyLanguagePrefixesForTesting(["en", "ko"])
        XCTAssertFalse(VoiceEngineLanguageCatalog.supports(.appleSpeech, languageID: "th"))
        XCTAssertFalse(VoiceEngineLanguageCatalog.supportedProductLanguages(for: .appleSpeech).contains { $0.id == "th" })
        XCTAssertTrue(VoiceEngineLanguageCatalog.supports(.appleSpeech, languageID: "ko"))
        XCTAssertTrue(VoiceEngineLanguageCatalog.supports(.whisperSmall, languageID: "th"))
    }

    func testUnsupportedAnalyzerLanguageDoesNotFallBackToStaticThaiList() {
        let original = AppleSpeechLiveCapability.analyzerLanguagePrefixes
        defer { AppleSpeechLiveCapability.setAnalyzerLanguagePrefixesForTesting(original) }
        AppleSpeechLiveCapability.setAnalyzerLanguagePrefixesForTesting(["en", "ko"])
        XCTAssertEqual(VoiceEngineLanguageReadiness.current(model: .appleSpeechAnalyzer, languageID: "th"), .unsupported)
        XCTAssertFalse(VoiceEngineLanguageReadiness.supportedLanguages(for: .appleSpeechAnalyzer).contains { $0.id == "th" })
    }

    func testEitherWayRequiresBothDirectionsReady() {
        let statuses: [TranslationPackAvailability] = [.unknown, .unsupported, .supported, .installed]
        for forward in statuses {
            for reverse in statuses {
                XCTAssertEqual(
                    EitherWayAvailability.isVisible(speechReady: true, forward: forward, reverse: reverse),
                    forward == .installed && reverse == .installed
                )
                XCTAssertFalse(EitherWayAvailability.isVisible(speechReady: false, forward: forward, reverse: reverse))
            }
        }
    }

    func testSwapRequiresKnownTranslationSupport() {
        XCTAssertFalse(LanguageChoicePolicy.translationSupported(.unsupported))
        XCTAssertFalse(LanguageChoicePolicy.translationSupported(.unknown))
        XCTAssertTrue(LanguageChoicePolicy.translationSupported(.supported))
        XCTAssertTrue(LanguageChoicePolicy.translationSupported(.installed))
    }

    func testTranslationMenusHideOnlyConfirmedUnsupportedPairs() {
        XCTAssertFalse(LanguageChoicePolicy.translationOffered(.unsupported))
        XCTAssertTrue(LanguageChoicePolicy.translationOffered(.unknown))
        XCTAssertTrue(LanguageChoicePolicy.translationOffered(.supported))
        XCTAssertTrue(LanguageChoicePolicy.translationOffered(.installed))
        XCTAssertEqual(LanguageOptionStatus.resolve(speech: nil, translation: .unknown), .checking)
    }

    func testUnknownAppleCapabilityIsOfferedAsCheckingNotConfirmed() {
        let original = AppleSpeechLiveCapability.analyzerLanguagePrefixes
        defer { AppleSpeechLiveCapability.setAnalyzerLanguagePrefixesForTesting(original) }
        AppleSpeechLiveCapability.setAnalyzerLanguagePrefixesForTesting(nil)
        XCTAssertNil(VoiceEngineLanguageCatalog.supportStatus(.appleSpeechAnalyzer, languageID: "en"))
        XCTAssertEqual(VoiceEngineLanguageReadiness.current(model: .appleSpeechAnalyzer, languageID: "en"), .checking)
        XCTAssertTrue(VoiceEngineLanguageReadiness.offeredLanguages(for: .appleSpeechAnalyzer).contains { $0.id == "en" })
        XCTAssertFalse(VoiceEngineLanguageReadiness.supportedLanguages(for: .appleSpeechAnalyzer).contains { $0.id == "en" })
        // No static route at all stays hidden even while unknown.
        XCTAssertEqual(VoiceEngineLanguageCatalog.supportStatus(.appleSpeechAnalyzer, languageID: "vi"), false)

        AppleSpeechLiveCapability.setAnalyzerLanguagePrefixesForTesting(["en"])
        XCTAssertEqual(VoiceEngineLanguageCatalog.supportStatus(.appleSpeechAnalyzer, languageID: "en"), true)
        XCTAssertEqual(VoiceEngineLanguageCatalog.supportStatus(.appleSpeechAnalyzer, languageID: "ko"), false)
        XCTAssertFalse(VoiceEngineLanguageReadiness.offeredLanguages(for: .appleSpeechAnalyzer).contains { $0.id == "ko" })
    }

    func testMenusReadinessAndSupportAgreeForEveryEngineAndLanguage() {
        for model in SettingsStore.SpeechModel.availableModels {
            let offered = Set(VoiceEngineLanguageReadiness.offeredLanguages(for: model).map(\.id))
            let confirmed = Set(VoiceEngineLanguageReadiness.supportedLanguages(for: model).map(\.id))
            XCTAssertTrue(confirmed.isSubset(of: offered), model.rawValue)
            for language in TranslationLanguageCatalog.all {
                let readiness = VoiceEngineLanguageReadiness.current(model: model, languageID: language.id)
                let label = "\(model.rawValue) \(language.id)"
                if offered.contains(language.id) {
                    XCTAssertNotEqual(readiness, .unsupported, label)
                } else {
                    // Permission is reported first; otherwise a hidden language must read as unsupported.
                    XCTAssertTrue(readiness == .unsupported || readiness == .permissionRequired, label)
                }
            }
        }
    }

    func testUnsupportedPacksAreHiddenEvenWhenSelected() {
        let rows = [
            LanguagePacksViewModel.Row(language: TranslationLanguageCatalog.thai, coverage: .unsupported, roles: ["I speak"], isDownloading: false),
            LanguagePacksViewModel.Row(language: TranslationLanguageCatalog.english, coverage: .needsDownload, roles: [], isDownloading: false),
            LanguagePacksViewModel.Row(language: TranslationLanguageCatalog.korean, coverage: .packDownloaded, roles: [], isDownloading: false),
        ]
        XCTAssertEqual(LanguagePacksViewModel.visibleRows(rows).map(\.id), ["en", "ko"])
    }

    func testSameLanguageDisablesEitherWayAndKeepsWhisperSelected() {
        let settings = SettingsStore.shared
        let originalModel = settings.selectedSpeechModel
        let originalSource = settings.translationSourceLanguageID
        let originalTarget = settings.translationTargetLanguageID
        let originalDynamic = settings.theaterDynamicPairing
        let originalWhisper = settings.selectedWhisperLanguageCode
        let originalApple = settings.selectedAppleSpeechLocaleIdentifier
        let originalCohere = settings.selectedCohereLanguage
        let originalNemotron = settings.selectedNemotronLanguage
        defer {
            settings.selectedSpeechModel = originalModel
            settings.translationSourceLanguageID = originalSource
            settings.translationTargetLanguageID = originalTarget
            settings.theaterDynamicPairing = originalDynamic
            settings.selectedWhisperLanguageCode = originalWhisper
            settings.selectedAppleSpeechLocaleIdentifier = originalApple
            settings.selectedCohereLanguage = originalCohere
            settings.selectedNemotronLanguage = originalNemotron
        }
        settings.selectedSpeechModel = .whisperSmall
        settings.translationSourceLanguageID = "en"
        settings.translationTargetLanguageID = "ko"
        settings.theaterDynamicPairing = true
        LiveTranslationController.shared.applyTargetLanguage("en")
        XCTAssertFalse(settings.theaterDynamicPairing)
        XCTAssertFalse(SpokenLanguageResolver.showsEitherWayControl(settings: settings))
        XCTAssertEqual(settings.selectedSpeechModel, .whisperSmall)
    }

    func testSwapCannotSelectAHiddenUnsupportedSpokenLanguage() {
        let settings = SettingsStore.shared
        let originalModel = settings.selectedSpeechModel
        let originalSource = settings.translationSourceLanguageID
        let originalTarget = settings.translationTargetLanguageID
        defer {
            settings.selectedSpeechModel = originalModel
            settings.translationSourceLanguageID = originalSource
            settings.translationTargetLanguageID = originalTarget
        }
        settings.selectedSpeechModel = .parakeetRealtime
        settings.translationSourceLanguageID = "en"
        settings.translationTargetLanguageID = "th"
        XCTAssertFalse(LanguageChoicePolicy.canSwap(settings: settings))
        LiveTranslationController.shared.swapDirection()
        XCTAssertEqual(settings.translationSourceLanguageID, "en")
        XCTAssertEqual(settings.translationTargetLanguageID, "th")
    }

    func testSwapWorksBeforeTheReversePairHasBeenChecked() {
        let settings = SettingsStore.shared
        let originalModel = settings.selectedSpeechModel
        let originalSource = settings.translationSourceLanguageID
        let originalTarget = settings.translationTargetLanguageID
        let originalMode = settings.theaterSessionMode
        defer {
            settings.selectedSpeechModel = originalModel
            settings.translationSourceLanguageID = originalSource
            settings.translationTargetLanguageID = originalTarget
            settings.theaterSessionMode = originalMode
        }
        settings.theaterSessionMode = .translation
        settings.selectedSpeechModel = .whisperSmall
        settings.translationSourceLanguageID = "en"
        settings.translationTargetLanguageID = "ko"
        // Whisper hears Korean; ko→en may still be unchecked. Only a confirmed "cannot" blocks Swap.
        if AppleTranslationEngine.shared.cachedPackAvailability(
            source: TranslationLanguageCatalog.korean, target: TranslationLanguageCatalog.english
        ) != .unsupported {
            XCTAssertNil(LanguageChoicePolicy.swapUnavailableReason(settings: settings))
            LiveTranslationController.shared.swapDirection()
            XCTAssertEqual(settings.translationSourceLanguageID, "ko")
            XCTAssertEqual(settings.translationTargetLanguageID, "en")
        }
        settings.translationTargetLanguageID = settings.translationSourceLanguageID
        XCTAssertNotNil(LanguageChoicePolicy.swapUnavailableReason(settings: settings))
    }

    func testPackDownloadUsesTheDirectionThatWasChecked() throws {
        let source = TranslationLanguageCatalog.thai
        let target = TranslationLanguageCatalog.english
        let forward = try XCTUnwrap(LanguagePacksViewModel.downloadPair(for: target, source: source, target: target))
        XCTAssertEqual(forward.source.id, "th")
        XCTAssertEqual(forward.target.id, "en")
        let sourceRow = try XCTUnwrap(LanguagePacksViewModel.downloadPair(for: source, source: source, target: target))
        XCTAssertEqual(sourceRow.source.id, "th")
        XCTAssertEqual(sourceRow.target.id, "en")
    }
}


final class CapabilityConsistencyTests: XCTestCase {
    @MainActor
    func testMenuBarOnlyOffersSpeechLanguagesWithInstalledAssetsAndStatus() {
        let settings = SettingsStore.shared
        let model = settings.selectedSpeechModel
        let mode = settings.theaterSessionMode
        let supported = AppleSpeechLiveCapability.analyzerLanguagePrefixes
        let installed = AppleSpeechLiveCapability.installedAnalyzerLanguagePrefixes
        defer {
            settings.selectedSpeechModel = model
            settings.theaterSessionMode = mode
            AppleSpeechLiveCapability.setAnalyzerLanguagePrefixesForTesting(supported)
            AppleSpeechLiveCapability.setInstalledAnalyzerLanguagePrefixesForTesting(installed)
        }
        settings.selectedSpeechModel = .appleSpeechAnalyzer
        settings.theaterSessionMode = .transcription
        AppleSpeechLiveCapability.setAnalyzerLanguagePrefixesForTesting(["en", "th"])
        AppleSpeechLiveCapability.setInstalledAnalyzerLanguagePrefixesForTesting(["en"])
        let menu = NSMenu()
        TheaterMenuBarController.appendOverlayControls(to: menu, target: TheaterMenuBarController.shared)
        TheaterMenuBarController.applyState(to: menu)
        let choices = TheaterMenuBarController.item(.speakLanguage, in: menu)?.submenu?.items ?? []
        XCTAssertEqual(choices.compactMap { $0.representedObject as? String }, ["en"])
        XCTAssertTrue(choices.allSatisfy { $0.title.contains(AppLanguage.text("Ready")) })
        XCTAssertTrue(choices.allSatisfy { $0.toolTip?.isEmpty == false })
    }

    func testThermalFallbackRequiresReadyLanguageAssets() {
        XCTAssertNil(LiveTranslationThermalEngine.readyFallback(languageID: "th", readiness: { _, _ in .needsDownload }))
        XCTAssertNil(LiveTranslationThermalEngine.readyFallback(languageID: "th", readiness: { _, _ in .unsupported }))
        XCTAssertNil(LiveTranslationThermalEngine.readyFallback(languageID: "th", readiness: { _, _ in .checking }))
        XCTAssertEqual(LiveTranslationThermalEngine.readyFallback(languageID: "th", readiness: { model, language in
            XCTAssertEqual(language, "th")
            return model == .appleSpeech ? .ready : .needsDownload
        }), .appleSpeech)
        XCTAssertNil(LiveTranslationThermalEngine.readyFallback(languageID: "th", availableModels: [], readiness: { _, _ in .ready }))
    }

    func testSilenceFallbackSkipsUnavailableSpeechAssets() {
        for status in [VoiceEngineLanguageReadiness.unsupported, .checking, .permissionRequired, .needsDownload] {
            XCTAssertNil(VoiceEngineLanguageCatalog.nextFallbackModel(after: .appleSpeechAnalyzer, forLanguageID: "th",
                                                                     availableModels: [.appleSpeech], readiness: { _, _ in status }))
        }
    }

    func testLanguageIndicatorsSeparateSpeechAndTranslationDownloads() {
        XCTAssertEqual(LanguageOptionStatus.resolve(speech: .needsDownload, translation: .installed), .speechDownload)
        XCTAssertEqual(LanguageOptionStatus.resolve(speech: .ready, translation: .supported), .translationDownload)
        XCTAssertEqual(LanguageOptionStatus.resolve(speech: .ready, translation: .unknown), .checking)
        XCTAssertEqual(LanguageOptionStatus.resolve(speech: .ready, translation: .unsupported), .unsupported)
        XCTAssertEqual(LanguageOptionStatus.resolve(speech: .permissionRequired, translation: .installed), .permissionRequired)
        XCTAssertEqual(LanguageOptionStatus.resolve(speech: .unsupported, translation: .installed), .unsupported)
        XCTAssertEqual(LanguageOptionStatus.resolve(speech: nil, translation: .installed), .ready)
    }

    func testUnsupportedTranslationDoesNotRecommendADownload() {
        let snapshot = TheaterReadyGate.snapshot(engineSupportsSource: true, modelInstalled: true,
                                                sameLanguagePair: false, pack: .unsupported,
                                                microphone: .authorized, firstCaptionPrinted: true)
        XCTAssertFalse(snapshot.canListen)
        XCTAssertFalse(snapshot.languagePackReady)
        XCTAssertEqual(snapshot.nextAction, AppLanguage.text(TheaterReadiness.packUnsupported))
    }

    func testPlaybackNeedsVoicesInBothDirectionsOnlyForEitherWay() {
        XCTAssertEqual(SpokenCaptionAvailability.evaluate(sameLanguage: false, targetVoice: true, reverseVoice: false,
                                                          bidirectional: false, outputAvailable: true), .ready)
        XCTAssertEqual(SpokenCaptionAvailability.evaluate(sameLanguage: false, targetVoice: true, reverseVoice: false,
                                                          bidirectional: true, outputAvailable: true), .voiceMissing)
        XCTAssertEqual(SpokenCaptionAvailability.evaluate(sameLanguage: false, targetVoice: false, reverseVoice: true,
                                                          bidirectional: false, outputAvailable: true), .voiceMissing)
    }

    func testPlaybackExplainsInactiveModesAndDisconnectedOutput() {
        XCTAssertEqual(SpokenCaptionAvailability.evaluate(sameLanguage: true, targetVoice: true, reverseVoice: true,
                                                          bidirectional: false, outputAvailable: true), .sameLanguage)
        XCTAssertEqual(SpokenCaptionAvailability.evaluate(sameLanguage: false, targetVoice: true, reverseVoice: true,
                                                          bidirectional: false, outputAvailable: false), .outputMissing)
    }

    @MainActor
    func testUnknownPacksAreNeitherReadyNorDownloadable() {
        XCTAssertEqual(AppleTranslationEngine.coverage(forRichStatus: .unknown), .checking)
        for coverage in [LanguagePackCoverage.checking, .unsupported, .packDownloaded] {
            let row = LanguagePacksViewModel.Row(language: TranslationLanguageCatalog.thai, coverage: coverage,
                                                roles: ["Show as"], isDownloading: false)
            XCTAssertFalse(row.canDownload)
        }
        let downloadable = LanguagePacksViewModel.Row(language: TranslationLanguageCatalog.thai, coverage: .needsDownload,
                                                     roles: ["Show as"], isDownloading: false)
        XCTAssertTrue(downloadable.canDownload)
    }
}
