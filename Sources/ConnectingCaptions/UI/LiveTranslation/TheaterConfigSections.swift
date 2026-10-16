import AVFoundation
import SwiftUI

/// Theater mode picker, shared by the Setup Wizard and Home so they can't drift.
struct TheaterModeSection: View {
    @Environment(\.theme) private var theme
    @ObservedObject private var settings = SettingsStore.shared
    @ObservedObject private var controller = LiveTranslationController.shared

    var accessibilityIdentifier: String?
    var title = "Caption language"

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TheaterSharedSettingsNotice()
            Text(AppLanguage.text(self.title))
                .font(self.theme.typography.bodyStrong)
                .foregroundStyle(self.theme.palette.primaryText)
            TheaterWordPicker(
                accessibilityLabel: AppLanguage.text(self.title),
                accessibilityIdentifier: self.accessibilityIdentifier,
                options: Array(TheaterSessionMode.allCases),
                title: { $0.displayName },
                selection: Binding(
                    get: { self.settings.theaterSessionMode },
                    set: { self.controller.applyTheaterSessionMode($0) }
                )
            )
            .help(TheaterReadiness.modeStopsListen)
            Text(self.settings.theaterSessionMode.help)
                .font(self.theme.typography.bodySmall)
                .foregroundStyle(self.theme.palette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Either way: speak either language of the pair; Theater flips the clause.
/// Shared by the language card and Theater chrome. Turning it on downloads
/// Whisper Small once; Apple Speech stays the default for one speaker.
struct TheaterEitherWaySection: View {
    @ObservedObject private var settings = SettingsStore.shared
    @ObservedObject private var controller = LiveTranslationController.shared
    @ObservedObject private var asr = AppServices.shared.asr

    var accessibilityIdentifier: String
    var compact = false
    /// Board chrome wraps Listen-stopping changes; Home can leave this nil.
    var apply: ((Bool) -> Void)?

    /// Either way only turns on once Whisper Small is already on disk —
    /// no surprise download kicked off from a toggle flip.
    private var addOnInstalled: Bool {
        SettingsStore.SpeechModel.eitherWayAddOn.isInstalled
    }

    /// Flipping the toggle forces the Voice Engine to the add-on, so whether
    /// it's worth tapping depends on what the add-on supports for this pair —
    /// not on whichever engine happens to be selected before the flip.
    private var pairSupported: Bool {
        SpokenLanguageResolver.dynamicPairingSupportsCurrentPair(settings: self.settings)
    }

    private var detail: String {
        SpokenLanguageResolver.dynamicPairingControlCopy(settings: self.settings)
    }

    private var pairingBinding: Binding<Bool> {
        Binding(
            get: { self.settings.theaterDynamicPairing },
            set: { enabled in
                if let apply = self.apply {
                    apply(enabled)
                } else {
                    self.controller.applyDynamicPairing(enabled)
                }
            }
        )
    }

    var body: some View {
        if SpokenLanguageResolver.showsEitherWayControl(settings: self.settings) {
            self.control
        }
    }

    @ViewBuilder
    private var control: some View {
        if self.compact {
            Toggle(AppLanguage.text("Either way"), isOn: self.pairingBinding)
                .toggleStyle(.switch)
                .controlSize(.small)
                .disabled(!self.addOnInstalled || !self.pairSupported)
                .help(self.detail)
                .theaterTag(self.detail)
                .accessibilityLabel(AppLanguage.text("Either way"))
                .accessibilityHint(self.detail)
                .accessibilityIdentifier(self.accessibilityIdentifier)
        } else {
            TheaterSettingRow(
                title: AppLanguage.text("Either way"),
                detail: self.detail
            ) {
                Toggle(AppLanguage.text("Either way"), isOn: self.pairingBinding)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .disabled(!self.addOnInstalled || !self.pairSupported)
                    .help(self.detail)
                    .accessibilityLabel(AppLanguage.text("Either way"))
                    .accessibilityHint(self.detail)
                    .accessibilityIdentifier(self.accessibilityIdentifier)
            }
        }
    }
}

/// Spoken-line picker, shared by Home, Settings, and the Setup Wizard. Stays visible and
/// disabled (rather than disappearing) when the pair is the same language, so
/// the control's absence is never mistaken for a bug.
struct TheaterSpokenLineSection: View {
    @Environment(\.theme) private var theme
    @ObservedObject private var settings = SettingsStore.shared

    var accessibilityIdentifier: String

    var body: some View {
        TheaterSettingRow(
            title: TheaterReadiness.spokenLineTitle,
            detail: SpokenLanguageResolver.isSameLanguagePair()
                ? TheaterReadiness.spokenLineSameLanguage
                : self.settings.theaterSpokenLineMode.help
        ) {
            TheaterSpokenLinePicker(accessibilityIdentifier: self.accessibilityIdentifier)
                .disabled(SpokenLanguageResolver.isSameLanguagePair())
        }
    }
}

/// "Before you Listen" checklist, shared by Home and the Setup Wizard's Ready
/// step so a user can't finish the wizard without seeing what's still missing.
struct TheaterReadinessChecklist: View {
    @Environment(\.theme) private var theme
    @EnvironmentObject private var appServices: AppServices
    @ObservedObject private var settings = SettingsStore.shared
    @ObservedObject private var controller = LiveTranslationController.shared

    var openVoiceEngine: (() -> Void)?
    var openTranslationEngine: (() -> Void)?
    var compact = false

    private var asr: ASRService {
        self.appServices.asr
    }

    private var microphoneActionTitle: String {
        if MicrophoneAccess.isOpenedFromDownload {
            return "Show in Finder"
        }
        return self.asr.micStatus == .notDetermined ? "Allow" : "Open Settings"
    }

    private var readinessGuidance: String {
        guard self.snapshot.osSupported, self.snapshot.voiceEngineReady else {
            return self.snapshot.nextAction
        }
        if !self.snapshot.microphoneAllowed, !self.asr.microphoneAccessDetail.isEmpty {
            return self.asr.microphoneAccessDetail
        }
        return self.snapshot.nextAction
    }

    private var snapshot: TheaterReadyGate.Snapshot {
        TheaterReadyGate.liveSnapshot(
            pack: self.controller.packAvailability,
            microphone: self.asr.micStatus,
            firstCaptionPrinted: self.settings.theaterListenUsed
        )
    }

    var body: some View {
        Group {
            if self.compact {
                TheaterSideBySide(spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        FluidSectionHeader(title: AppLanguage.text("Before you Listen"), systemImage: "exclamationmark.circle")
                        self.guidance
                    }
                } trailing: {
                    self.primaryAction
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    FluidSectionHeader(title: AppLanguage.text("Before you Listen"), systemImage: "checklist")
                    self.readyRow(TheaterEngineCopy.voiceTitle, done: self.snapshot.voiceEngineReady)
                    if self.settings.theaterSessionMode == .translation {
                        self.readyRow(TheaterEngineCopy.translationTitle, done: self.snapshot.languagePackReady)
                    }
                    self.readyRow("Microphone", done: self.snapshot.microphoneAllowed)
                    self.guidance
                    self.allActions
                }
            }
        }
        .task(id: TranslationPairKey.current()) {
            await self.controller.refreshPackAvailability()
        }
    }

    private var guidance: some View {
        Text(self.readinessGuidance)
            .font(self.theme.typography.bodySmall)
            .foregroundStyle(self.theme.palette.warning)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var primaryAction: some View {
        if !self.snapshot.voiceEngineReady {
            if self.snapshot.voiceEngineNeedsRealign {
                AppButton("Match I speak") { self.controller.alignSpokenEngineWithTheater() }
                    .buttonStyle(.theaterText)
                    .accessibilityIdentifier("theater.readiness.matchISpeak")
            } else if let openVoiceEngine {
                AppButton("Open Voice Engine", action: openVoiceEngine)
                    .buttonStyle(.theaterText)
            }
        } else if !self.snapshot.microphoneAllowed {
            Button(self.microphoneActionTitle) { self.asr.requestMicAccess() }
                .buttonStyle(.theaterText)
        } else if !self.snapshot.languagePackReady, let openTranslationEngine {
            AppButton("Language packs", action: openTranslationEngine)
                .buttonStyle(.theaterText)
        }
    }

    private var allActions: some View {
        VStack(alignment: .leading, spacing: 8) {
            if self.snapshot.voiceEngineNeedsRealign {
                AppButton("Match I speak") {
                    self.controller.alignSpokenEngineWithTheater()
                }
                .buttonStyle(.theaterText)
                .accessibilityIdentifier("theater.readiness.matchISpeak")
            } else if !self.snapshot.voiceEngineReady, let openVoiceEngine {
                AppButton("Voice Engine", action: openVoiceEngine)
                    .buttonStyle(.theaterText)
            }
            if self.settings.theaterSessionMode == .translation,
               !self.snapshot.languagePackReady,
               let openTranslationEngine
            {
                AppButton("Language packs", action: openTranslationEngine)
                    .buttonStyle(.theaterText)
            }
            if !self.snapshot.microphoneAllowed {
                Button(self.microphoneActionTitle) {
                    self.asr.requestMicAccess()
                }
                .buttonStyle(.theaterText)
                if MicrophoneAccess.isOpenedFromDownload {
                    Text(MicrophoneAccess.moveToApplicationsCopy)
                        .font(self.theme.typography.bodySmall)
                        .foregroundStyle(self.theme.palette.warning)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func readyRow(_ title: String, done: Bool) -> some View {
        Label(title, systemImage: done ? "checkmark.circle.fill" : "circle")
            .foregroundStyle(done ? self.theme.palette.accent : self.theme.palette.secondaryText)
    }
}
