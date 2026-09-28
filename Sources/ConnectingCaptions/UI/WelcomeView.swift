//
//  WelcomeView.swift
//  fluid
//
//  Welcome and setup guide view
//

import AppKit
import AVFoundation
import SwiftUI

struct WelcomeView: View {
    @EnvironmentObject var appServices: AppServices
    private var asr: ASRService {
        self.appServices.asr
    }

    @ObservedObject private var settings = SettingsStore.shared
    @Binding var selectedSidebarItem: SidebarItem?
    @Environment(\.theme) private var theme

    let accessibilityEnabled: Bool
    let openAccessibilitySettings: () -> Void

    @State private var languagePackAvailability = ""

    private var isLanguagePackReady: Bool {
        self.languagePackAvailability.hasPrefix("Ready")
    }

    private var needsTranslationPack: Bool {
        !SpokenLanguageResolver.isSameLanguagePair()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                FluidPageHeader(
                    systemImage: "captions.bubble",
                    title: "Getting Started",
                    subtitle: ConnectingCaptionsProduct.tagline
                )

                ThemedCard(style: .prominent) {
                    VStack(alignment: .leading, spacing: 12) {
                        FluidSectionHeader(title: "Checklist", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(self.theme.palette.accent)

                        VStack(alignment: .leading, spacing: 8) {
                            SetupStepView(
                                step: 1,
                                title: (self.asr.isAsrReady || self.asr.modelsExistOnDisk) ? "Voice Engine ready" : "Download a Voice Engine",
                                description: self.asr.isAsrReady
                                    ? "Voice Engine is sharpening speech into text."
                                    : (
                                        self.asr.modelsExistOnDisk
                                            ? "The speech-to-text model is on disk. It loads when you Listen."
                                            : "Download a speech-to-text model for the language you speak. Apple Speech is enough to try."
                                    ),
                                status: (self.asr.isAsrReady || self.asr.modelsExistOnDisk) ? .completed : .pending,
                                action: {
                                    self.selectedSidebarItem = .voiceEngine
                                },
                                actionButtonTitle: "Voice Engine",
                                showActionButton: !(self.asr.isAsrReady || self.asr.modelsExistOnDisk)
                            )

                            SetupStepView(
                                step: 2,
                                title: self.asr.micStatus == .authorized ? "Microphone allowed" : "Allow the microphone",
                                description: self.asr.micStatus == .authorized
                                    ? TheaterReadiness.gettingStartedMicrophoneReady
                                    : TheaterReadiness.gettingStartedMicrophone,
                                status: self.asr.micStatus == .authorized ? .completed : .pending,
                                action: {
                                    if self.asr.micStatus == .notDetermined {
                                        self.asr.requestMicAccess()
                                    } else if self.asr.micStatus == .denied {
                                        self.asr.openSystemSettingsForMic()
                                    }
                                },
                                actionButtonTitle: self.asr.micStatus == .notDetermined ? "Allow" : "Open Settings",
                                showActionButton: self.asr.micStatus != .authorized
                            )

                            if self.needsTranslationPack {
                                SetupStepView(
                                    step: 3,
                                    title: self.isLanguagePackReady ? "Language pack ready" : "Download language pack",
                                    description: self.languagePackAvailability.isEmpty
                                        ? "Translation Engine is Apple Translation by default. Download the language pack once, or try the experimental local LLM."
                                        : self.languagePackAvailability,
                                    status: self.isLanguagePackReady ? .completed : .pending,
                                    action: {
                                        self.selectedSidebarItem = .translationEngine
                                    },
                                    actionButtonTitle: "Translation Engine",
                                    showActionButton: !self.isLanguagePackReady
                                )
                            }

                            SetupStepView(
                                step: self.needsTranslationPack ? 4 : 3,
                                title: TheaterAvailability.isSupported
                                    ? (self.settings.theaterListenUsed
                                        ? TheaterReadiness.gettingStartedReady
                                        : TheaterReadiness.gettingStartedOpen)
                                    : TheaterAvailability.unsupportedCopy,
                                description: TheaterAvailability.isSupported
                                    ? (self.settings.theaterListenUsed
                                        ? TheaterReadiness.gettingStartedReadyDetail
                                        : TheaterReadiness.gettingStartedOpenDetail)
                                    : TheaterAvailability.unsupportedCopy,
                                status: TheaterAvailability.isSupported && self.settings.theaterListenUsed
                                    ? .completed
                                    : .pending,
                                action: {
                                    self.selectedSidebarItem = .liveTranslation
                                    PresenterCaptionController.shared.setVisible(true)
                                },
                                actionButtonTitle: "Open Theater",
                                showActionButton: TheaterAvailability.isSupported && !self.settings.theaterListenUsed
                            )
                            .accessibilityIdentifier("getting-started-theater")

                            SetupStepView(
                                step: self.needsTranslationPack ? 5 : 4,
                                title: self.accessibilityEnabled
                                    ? "Typing into another app is ready"
                                    : "Optional: type into another app",
                                description: self.accessibilityEnabled
                                    ? "Type the board types captions already printed. Listen, then type starts a new Listen. Theater captions do not need this."
                                    : "Only for Type the board or Listen, then type. Theater captions work without it.",
                                status: self.accessibilityEnabled ? .completed : .notNeeded,
                                action: {
                                    self.openAccessibilitySettings()
                                },
                                actionButtonTitle: "Open Settings",
                                showActionButton: !self.accessibilityEnabled
                            )
                        }

                        Text(TheaterReadiness.macOSNote)
                            .font(self.theme.typography.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        Button(TheaterSetupWizard.title) {
                            self.settings.startSetupWizard()
                        }
                        .buttonStyle(.theaterText)
                        .accessibilityIdentifier("getting-started-setup-wizard")
                    }
                }

                CommercialLicenseStatusCard()
            }
            .fluidPageContent()
        }
        .onAppear {
            Task { @MainActor in
                await AudioStartupGate.shared.scheduleOpenAfterInitialUISettled()
                await AudioStartupGate.shared.waitUntilOpen()
                self.asr.micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
                await self.asr.checkIfModelsExistAsync()
                let source = SpokenLanguageResolver.sourceLanguage()
                let target = SpokenLanguageResolver.targetLanguage()
                await AppleTranslationEngine.shared.warm(source: source, target: target)
                self.languagePackAvailability = await AppleTranslationEngine.shared.checkAvailability(
                    source: source,
                    target: target
                )
            }
        }
    }
}
