import SwiftUI

/// Speak and type. Its own section, separate from Theater captions.
struct SpeakAndTypeView: View {
    @ObservedObject private var controller = LiveTranslationController.shared
    @ObservedObject private var settings = SettingsStore.shared
    @ObservedObject private var asr = AppServices.shared.asr
    var showsPageHeader = true
    var tracksSearch = false
    var recordShortcut: (() -> Void)?
    var isRecordingShortcut = false
    var shortcutRecordingMessage: String?
    var accessibilityTrusted = true
    var openAccessibility: () -> Void = {}
    var openVoiceEngine: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if self.showsPageHeader {
                FluidPageHeader(
                    systemImage: "text.cursor",
                    title: AppLanguage.text("Speak & Type"),
                    subtitle: TheaterReadiness.speakAndTypeSubtitle
                )
            }

            ThemedCard(style: .standard, hoverEffect: false) {
                TheaterModeSection(
                    accessibilityIdentifier: "speakAndType.mode",
                    title: AppLanguage.text("What gets typed")
                )
            }

            if self.readiness.needsAttention {
                ThemedCard(style: .standard, hoverEffect: false) {
                    TheaterReadinessChecklist(
                        openVoiceEngine: self.openVoiceEngine ?? { AppNavigationRouter.shared.request(.voiceEngine) },
                        openTranslationEngine: { AppNavigationRouter.shared.request(.languagePacks) },
                        compact: true
                    )
                }
            }
            TranslationLanguagePairCard()
            ThemedCard(style: .standard, hoverEffect: false) {
                TheaterMicrophoneStatus()
            }
            self.shortcutCard
            ThemedCard(style: .standard, hoverEffect: false) {
                DisclosureGroup(AppLanguage.text("Advanced")) {
                    VStack(alignment: .leading, spacing: 16) {
                        TheaterEngineCards(
                            openVoiceEngine: self.openVoiceEngine ?? { AppNavigationRouter.shared.request(.voiceEngine) },
                            openTranslationEngine: { AppNavigationRouter.shared.request(.languagePacks) },
                            showsPurpose: false
                        )
                        if SpokenLanguageResolver.showsEitherWayControl() {
                            TheaterSharedSettingsNotice()
                            TheaterEitherWaySection(accessibilityIdentifier: "speakAndType.eitherWay")
                        }
                    }
                    .padding(.top, 12)
                }
            }
        }
        .accessibilityIdentifier("speakAndType.home")
    }

    private var readiness: TheaterReadyGate.Snapshot {
        TheaterReadyGate.liveSnapshot(
            pack: self.controller.packAvailability,
            microphone: self.asr.micStatus,
            firstCaptionPrinted: self.settings.theaterListenUsed
        )
    }

    @ViewBuilder
    private var shortcutCard: some View {
        let card = TranslateInsertShortcutCard(
            recordTranslateShortcut: self.recordShortcut,
            isRecordingTranslateShortcut: self.isRecordingShortcut,
            shortcutRecordingMessage: self.shortcutRecordingMessage,
            accessibilityTrusted: self.accessibilityTrusted,
            openAccessibility: self.openAccessibility
        )
        if self.tracksSearch {
            card.settingsSearchTarget(.translateInsertShortcut)
        } else {
            card
        }
    }
}

extension SettingsView {
    var settingsSectionSubtitle: String? {
        switch self.selectedSection {
        case .translation:
            return ConnectingCaptionsProduct.tagline
        case .speakAndType:
            return TheaterReadiness.speakAndTypeSubtitle
        default:
            return nil
        }
    }

    var speakAndTypeSettings: some View {
        SpeakAndTypeView(
            showsPageHeader: false,
            tracksSearch: true,
            recordShortcut: { self.toggleSpeakAndTypeRecording() },
            isRecordingShortcut: self.isRecording(.translateInsert),
            shortcutRecordingMessage: self.isRecording(.translateInsert) ? self.shortcutRecordingMessage : nil,
            accessibilityTrusted: self.accessibilityEnabled,
            openAccessibility: self.openAccessibilitySettings
        )
    }

    func toggleSpeakAndTypeRecording() {
        self.shortcutRecordingMessage = nil
        if self.isRecording(.translateInsert) {
            self.activeShortcutRecordingTarget = nil
        } else {
            self.activeShortcutRecordingTarget = .translateInsert
        }
    }
}
