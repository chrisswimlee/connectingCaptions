@testable import ConnectingCaptions_Debug
import XCTest

final class AppleSpeechLocaleTests: XCTestCase {
    func testAnalyzerLocalesAreKoreanEnglishThaiJapanese() {
        XCTAssertEqual(VoiceEngineLanguageCatalog.preferredAppleSpeechAnalyzerLocale(forLanguageID: "en"), "en-US")
        XCTAssertEqual(VoiceEngineLanguageCatalog.preferredAppleSpeechAnalyzerLocale(forLanguageID: "ko"), "ko-KR")
        XCTAssertEqual(VoiceEngineLanguageCatalog.preferredAppleSpeechAnalyzerLocale(forLanguageID: "th"), "th-TH")
        XCTAssertEqual(VoiceEngineLanguageCatalog.preferredAppleSpeechAnalyzerLocale(forLanguageID: "ja"), "ja-JP")
        XCTAssertEqual(VoiceEngineLanguageCatalog.appleSpeechAnalyzerLocaleIdentifier(for: "fr"), "fr-FR")
        XCTAssertEqual(VoiceEngineLanguageCatalog.appleSpeechAnalyzerLocaleIdentifier(for: "zh"), "zh-CN")
        XCTAssertNil(VoiceEngineLanguageCatalog.appleSpeechAnalyzerLocaleIdentifier(for: "da"))
        XCTAssertEqual(VoiceEngineLanguageCatalog.preferredAppleSpeechAnalyzerLocale(forLanguageID: "fr"), "fr-FR")
        XCTAssertEqual(VoiceEngineLanguageCatalog.preferredAppleSpeechAnalyzerLocale(forLanguageID: "da"), "da-DK")
        XCTAssertEqual(VoiceEngineLanguageCatalog.preferredAppleSpeechAnalyzerLocale(forLanguageID: "no"), "nb-NO")
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
