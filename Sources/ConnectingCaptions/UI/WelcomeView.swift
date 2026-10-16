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

    private var microphoneNeedsAction: Bool {
        self.asr.micStatus != .authorized
    }

    private var microphoneStepDescription: String {
        if MicrophoneAccess.isOpenedFromDownload {
            return MicrophoneAccess.moveToApplicationsCopy
        }
        if !self.asr.microphoneAccessDetail.isEmpty {
            return self.asr.microphoneAccessDetail
        }
        return TheaterReadiness.gettingStartedMicrophone
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                FluidPageHeader(
                    systemImage: "captions.bubble",
                    title: AppLanguage.text("Getting Started"),
                    subtitle: ConnectingCaptionsProduct.tagline
                )

                ThemedCard(style: .prominent) {
                    VStack(alignment: .leading, spacing: 12) {
                        FluidSectionHeader(title: AppLanguage.text("Listen"), systemImage: "captions.bubble")
                            .foregroundStyle(self.theme.palette.accent)

                        AppText("Open Theater, pick Voice or Translate, then press Listen. Each sentence appears when it is ready.")
                            .font(self.theme.typography.body)
                            .foregroundStyle(self.theme.palette.primaryText)
                            .fixedSize(horizontal: false, vertical: true)

                        AppText("I speak and Show as are on the Theater card. The same language needs no download. Setup → Voice Engine switches newer or older Apple Speech.")
                            .font(self.theme.typography.bodySmall)
                            .foregroundStyle(self.theme.palette.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)

                        if self.microphoneNeedsAction {
                            Divider().opacity(0.2)
                            Text(self.microphoneStepDescription)
                                .font(self.theme.typography.bodySmall)
                                .foregroundStyle(self.theme.palette.warning)
                                .fixedSize(horizontal: false, vertical: true)
                            Button(MicrophoneAccess.isOpenedFromDownload
                                ? "Show in Finder"
                                : (self.asr.micStatus == .notDetermined ? "Allow" : "Open Settings")) {
                                self.asr.requestMicAccess()
                            }
                            .buttonStyle(.theaterText)
                        }

                        if self.needsTranslationPack, !self.isLanguagePackReady {
                            Divider().opacity(0.2)
                            Text(self.languagePackAvailability.isEmpty
                                ? "This pair still needs its Apple Translation pack."
                                : self.languagePackAvailability)
                                .font(self.theme.typography.bodySmall)
                                .foregroundStyle(self.theme.palette.secondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                            AppButton("Language packs") {
                                self.selectedSidebarItem = .languagePacks
                            }
                            .buttonStyle(.theaterText)
                        }

                        Divider().opacity(0.2)

                        AppButton("Open Theater") {
                            self.selectedSidebarItem = .liveTranslation
                            PresenterCaptionController.shared.setVisible(true)
                        }
                        .buttonStyle(.theaterText)
                        .accessibilityIdentifier("getting-started-theater")

                        if !self.accessibilityEnabled {
                            Divider().opacity(0.2)
                            AppText("Typing a caption into another app is optional. Theater captions do not need it.")
                                .font(self.theme.typography.bodySmall)
                                .foregroundStyle(self.theme.palette.secondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                            AppButton("Allow typing into another app") {
                                self.openAccessibilitySettings()
                            }
                            .buttonStyle(.theaterText)
                        }

                        Divider().opacity(0.2)

                        AppText(TheaterReadiness.macOSNote)
                            .font(self.theme.typography.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                if self.settings.isCommerciallyLicensed || self.settings.commercialLicenseRecord != nil {
                    CommercialLicenseStatusCard()
                }
            }
            .fluidPageContent()
        }
        .onAppear {
            Task { @MainActor in
                await AudioStartupGate.shared.scheduleOpenAfterInitialUISettled()
                await AudioStartupGate.shared.waitUntilOpen()
                self.asr.recordMicrophoneAccessRead(await MicrophoneAccess.statusOffMain())
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
