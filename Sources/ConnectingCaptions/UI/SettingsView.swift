//
//  SettingsView.swift
//  fluid
//
//  App preferences and audio device settings
//

import AppKit
import AVFoundation
import PromiseKit
import SwiftUI
import UniformTypeIdentifiers

// swiftlint:disable type_body_length function_body_length cyclomatic_complexity
// Tracked grandfather: settings form. New rows belong in a focused view.
struct SettingsView: View {
    struct ShortcutRowContent {
        let icon: String
        let iconColor: Color
        let title: String
        let description: String
    }

    @EnvironmentObject var appServices: AppServices
    var asr: ASRService {
        self.appServices.asr
    }

    @Environment(\.colorScheme) var colorScheme
    @Environment(\.theme) var theme
    @Environment(\.accessibilityReduceMotion) var accessibilityReduceMotion
    @ObservedObject var settings = SettingsStore.shared
    let selectedSection: SettingsSection
    let searchResults: [SettingsSearchResult]
    let searchScrollRequest: Int
    @ObservedObject var microphonePreferenceCoordinator: MicrophonePreferenceCoordinator
    @Binding var appear: Bool
    @Binding var visualizerNoiseThreshold: Double
    @Binding var selectedInputUID: String
    @Binding var selectedOutputUID: String
    @Binding var inputDevices: [AudioDevice.Device]
    @Binding var outputDevices: [AudioDevice.Device]
    @Binding var accessibilityEnabled: Bool
    @Binding var primaryDictationShortcuts: [HotkeyShortcut]
    @Binding var activeShortcutRecordingTarget: ShortcutRecordingTarget?
    @Binding var shortcutRecordingMessage: String?
    @Binding var cancelRecordingShortcut: HotkeyShortcut
    @Binding var pasteLastTranscriptionShortcut: HotkeyShortcut?
    @Binding var pasteLastTranscriptionShortcutEnabled: Bool
    @Binding var hotkeyManagerInitialized: Bool
    @Binding var hotkeyMode: HotkeyActivationMode
    @Binding var enableStreamingPreview: Bool
    @Binding var copyToClipboard: Bool

    // CRITICAL FIX: Cache default device names to avoid CoreAudio calls during view body evaluation.
    // Querying AudioDevice.getDefaultInputDevice() in the view body triggers HALSystem::InitializeShell()
    // which races with SwiftUI's AttributeGraph metadata processing and causes EXC_BAD_ACCESS crashes.
    @State var cachedDefaultInputUID: String = ""
    @State var cachedDefaultOutputName: String = ""

    @State var rollbackVersion: String = ""
    @State var isRollingBack: Bool = false
    @State var audioHistoryBudgetText: String = Self.audioBudgetText(for: SettingsStore.shared.audioHistoryBudgetGB)
    @State var audioHistoryUsageBytes: Int64 = 0
    @State var draggedMicrophoneUID: String?
    @State var hoveredMicrophoneUID: String?
    @State var searchScrollCoordinator = SettingsSearchScrollCoordinator()

    let hotkeyManager: GlobalHotkeyManager?
    let menuBarManager: MenuBarManager
    let startRecording: () -> Void
    var stopListening: () async -> Void = {}
    let refreshDevices: () -> Void
    let openAccessibilitySettings: () -> Void
    let restartApp: () -> Void
    let revealAppInFinder: () -> Void
    let openApplicationsFolder: () -> Void

    func isRecording(_ target: ShortcutRecordingTarget) -> Bool {
        self.activeShortcutRecordingTarget == target
    }

    var currentAppVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
    }

    var appDisplayName: String {
        Bundle.main.fluidAppDisplayName
    }

    var launchAtStartupBinding: Binding<Bool> {
        Binding(
            get: { self.settings.launchAtStartupEnabled },
            set: { self.settings.setLaunchAtStartup($0) }
        )
    }

    func dictationPromptSelectionBinding(for slot: SettingsStore.DictationShortcutSlot) -> Binding<String> {
        Binding(
            get: {
                switch self.settings.dictationPromptSelection(for: slot) {
                case .off:
                    return "__OFF__"
                case .default:
                    return "__DEFAULT__"
                case .privateAI:
                    return PrivateAIProviderPromptFormat.promptSelectionID
                case let .profile(id):
                    return id
                }
            },
            set: { newValue in
                switch newValue {
                case "__OFF__":
                    self.settings.setDictationPromptSelection(.off, for: slot)
                case "__DEFAULT__":
                    self.settings.setDictationPromptSelection(.default, for: slot)
                case PrivateAIProviderPromptFormat.promptSelectionID:
                    guard PrivateAIProviderPromptFormat.isAvailable(settings: self.settings) else { return }
                    self.settings.setDictationPromptSelection(.privateAI, for: slot)
                default:
                    self.settings.setDictationPromptSelection(.profile(newValue), for: slot)
                }
            }
        )
    }

    @ViewBuilder
    func dictationPromptPicker(for slot: SettingsStore.DictationShortcutSlot) -> some View {
        let profiles = self.settings.promptProfiles(for: .dictate)
        let privateAIAvailable = PrivateAIProviderPromptFormat.isAvailable(settings: self.settings)
        HStack {
            AppText("AI Prompt")
                .font(self.theme.typography.bodySmall)
                .foregroundStyle(self.settingsSecondaryText)
                .padding(.leading, 30)
            Spacer()
            Picker("", selection: self.dictationPromptSelectionBinding(for: slot)) {
                Section("ON-DEVICE") {
                    AppText("Fast — No cleanup").tag("__OFF__")
                    if PrivateFeatures.privateAIProvider {
                        AppText("Cleanup — Fluid-1")
                            .tag(PrivateAIProviderPromptFormat.promptSelectionID)
                            .disabled(!privateAIAvailable)
                    }
                }
                Section("EXTERNAL") {
                    AppText("Cleanup").tag("__DEFAULT__")
                    ForEach(profiles) { profile in
                        Text(profile.name.isEmpty ? "Untitled" : profile.name)
                            .tag(profile.id)
                    }
                }
            }
            .frame(width: 220)
        }
        .padding(.bottom, 4)
    }

    var body: some View {
        SettingsPersistentScrollView(
            theme: self.theme,
            colorScheme: self.colorScheme,
            searchScrollCoordinator: self.searchScrollCoordinator,
            searchScrollTarget: self.selectedSectionSearchResults.first?.target,
            searchScrollRequest: self.searchScrollRequest
        ) {
            VStack(spacing: 16) {
                FluidPageHeader(
                    systemImage: self.selectedSection.systemImage,
                    title: self.selectedSection.title,
                    subtitle: self.settingsSectionSubtitle
                ) {
                    if self.selectedSection == .translation {
                        HStack(spacing: 8) {
                            OpenTheaterButton()
                            TheaterListenButton()
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .settingsSearchTarget(self.selectedSection.searchTarget)

                LiveTranslationSettingsView(
                    recordListenShortcut: {
                        if self.isRecording(.captionListen) {
                            self.shortcutRecordingMessage = nil
                            self.activeShortcutRecordingTarget = nil
                        } else {
                            self.shortcutRecordingMessage = nil
                            self.activeShortcutRecordingTarget = .captionListen
                        }
                    },
                    isRecordingListenShortcut: self.isRecording(.captionListen),
                    shortcutRecordingMessage: self.isRecording(.captionListen)
                        ? self.shortcutRecordingMessage
                        : nil
                )
                    .shownInSettingsSection(.translation, selectedSection: self.selectedSection)

                self.speakAndTypeSettings
                    .shownInSettingsSection(.speakAndType, selectedSection: self.selectedSection)

                // Startup Card
                ThemedCard(style: .standard) {
                    VStack(alignment: .leading, spacing: 14) {
                        FluidSectionHeader(title: AppLanguage.text("Startup"), systemImage: "power")

                        VStack(spacing: 16) {
                            AppInterfaceLanguageSettings()
                            Divider().opacity(0.2)
                            // Launch at startup
                            self.settingsToggleRow(
                                title: AppLanguage.text("Launch at startup"),
                                description: AppLanguage.format("Automatically start {0} when you log in", String(describing: ConnectingCaptionsProduct.displayName)),
                                footnote: self.settings.launchAtStartupStatusMessage,
                                errorMessage: self.settings.launchAtStartupErrorMessage,
                                isOn: self.launchAtStartupBinding
                            )
                            .settingsSearchTarget(.launchAtStartup)
                            Divider().opacity(0.2)

                            // Show window when launched at login
                            self.settingsToggleRow(
                                title: AppLanguage.text("Show window when launched at login"),
                                description: AppLanguage.format("When off, {0} starts silently in the menu bar at login. Opening the app yourself always shows the window.", String(describing: ConnectingCaptionsProduct.displayName)),
                                isOn: Binding(
                                    get: { SettingsStore.shared.showMainWindowAtLoginLaunch },
                                    set: { SettingsStore.shared.showMainWindowAtLoginLaunch = $0 }
                                )
                            )
                            .settingsSearchTarget(.showWindowAtLogin)
                            Divider().opacity(0.2)

                            // Hide from Dock & App Switcher
                            self.settingsToggleRow(
                                title: AppLanguage.text("Hide from Dock & App Switcher"),
                                description: AppLanguage.format("Keep {0} in the menu bar only (hides Dock icon and Cmd+Tab entry)", String(describing: ConnectingCaptionsProduct.displayName)),
                                footnote: AppLanguage.text("Note: May require app restart to take effect."),
                                isOn: Binding(
                                    get: { SettingsStore.shared.hideFromDockAndAppSwitcher },
                                    set: { SettingsStore.shared.hideFromDockAndAppSwitcher = $0 }
                                )
                            )
                            .settingsSearchTarget(.dockVisibility)
                        }
                    }
                    .padding(16)
                }
                .shownInSettingsSection(.general, selectedSection: self.selectedSection)

                // Appearance Card
                ThemedCard(style: .standard) {
                    VStack(alignment: .leading, spacing: 14) {
                        FluidSectionHeader(title: AppLanguage.text("Appearance"), systemImage: "paintpalette.fill")

                        // Accent Color
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(alignment: .center) {
                                VStack(alignment: .leading, spacing: 2) {
                                    AppText("Accent Color")
                                        .font(self.theme.typography.bodyStrong)
                                        .foregroundStyle(self.settingsTitleText)
                                    Text(TheaterSetupWizard.accentDetail)
                                        .font(self.theme.typography.bodySmall)
                                        .foregroundStyle(self.settingsSecondaryText)
                                }

                                Spacer()

                                AccentColorSwatches(accessibilityIdentifier: "settings.accentColor")
                            }
                        }
                        .settingsSearchTarget(.accentColor)
                    }
                    .padding(16)
                }
                .shownInSettingsSection(.general, selectedSection: self.selectedSection)

                // Updates Card
                ThemedCard(style: .standard) {
                    VStack(alignment: .leading, spacing: 14) {
                        FluidSectionHeader(title: AppLanguage.text("Updates"), systemImage: "arrow.triangle.2.circlepath")

                        VStack(alignment: .leading, spacing: 16) {
                            // Automatic Updates
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(alignment: .center) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        AppText("Automatic Updates")
                                            .font(self.theme.typography.bodyStrong)
                                            .foregroundStyle(self.settingsTitleText)
                                        AppText("Off unless you turn it on. Hourly GitHub checks when enabled.")
                                            .font(self.theme.typography.bodySmall)
                                            .foregroundStyle(self.settingsSecondaryText)
                                    }

                                    Spacer()

                                    Toggle("", isOn: Binding(
                                        get: { SettingsStore.shared.autoUpdateCheckEnabled },
                                        set: { SettingsStore.shared.autoUpdateCheckEnabled = $0 }
                                    ))
                                    .toggleStyle(.switch)
                                    .tint(self.theme.palette.accent)
                                    .labelsHidden()
                                }

                                HStack(alignment: .center) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        AppText("Beta Releases")
                                            .font(self.theme.typography.bodyStrong)
                                            .foregroundStyle(self.settingsTitleText)
                                        AppText("Opt in to preview builds that may be unstable")
                                            .font(self.theme.typography.bodySmall)
                                            .foregroundStyle(self.settingsSecondaryText)
                                    }

                                    Spacer()

                                    Toggle("", isOn: Binding(
                                        get: { SettingsStore.shared.betaReleasesEnabled },
                                        set: { SettingsStore.shared.betaReleasesEnabled = $0 }
                                    ))
                                    .toggleStyle(.switch)
                                    .tint(self.theme.palette.accent)
                                    .labelsHidden()
                                }

                                if SettingsStore.shared.betaReleasesEnabled {
                                    AppText("Beta opt-in enabled. Update checks include both stable and beta builds.")
                                        .font(.caption)
                                        .foregroundStyle(self.theme.palette.warning)
                                }

                                if let lastCheck = SettingsStore.shared.lastUpdateCheckDate {
                                    AppText("Last checked: {0}", arguments: [String(describing: lastCheck.formatted(date: .abbreviated, time: .shortened))])
                                        .font(self.theme.typography.bodySmall)
                                        .foregroundStyle(self.settingsSecondaryText)
                                }

                                AppText("Current version: {0}", arguments: [String(describing: self.currentAppVersion)])
                                    .font(self.theme.typography.bodySmall)
                                    .foregroundStyle(self.settingsSecondaryText)

                                VStack(alignment: .leading, spacing: 2) {
                                    AppText("A product of {0}", arguments: [String(describing: ConnectingCaptionsProduct.publisherName)])
                                        .font(self.theme.typography.bodySmall)
                                        .foregroundStyle(self.settingsSecondaryText)
                                    HStack(spacing: 12) {
                                        Link(ConnectingCaptionsProduct.publisherSiteHost, destination: ConnectingCaptionsProduct.publisherURL)
                                            .textLinkPointer()
                                        Link(ConnectingCaptionsProduct.authorSiteHost, destination: ConnectingCaptionsProduct.authorURL)
                                            .textLinkPointer()
                                    }
                                    .font(self.theme.typography.bodySmall)
                                    VoiceEngineCredit()
                                        .font(self.theme.typography.bodySmall)
                                        .foregroundStyle(self.settingsSecondaryText)
                                }
                            }
                            .settingsSearchTarget(.automaticUpdates)

                            // Update Buttons
                            HStack(spacing: 10) {
                                AppButton("Check for Updates") {
                                    Task { @MainActor in
                                        do {
                                            let includePrerelease = SettingsStore.shared.betaReleasesEnabled
                                            let repository = try SimpleUpdater.shared.publishedRepository()
                                            try await SimpleUpdater.shared.checkAndUpdate(
                                                owner: repository.owner,
                                                repo: repository.repo,
                                                includePrerelease: includePrerelease
                                            )
                                        } catch SimpleUpdateError.updateAlreadyInProgress {
                                            DebugLogger.shared.info(
                                                "Update installation already in progress",
                                                source: "SettingsView"
                                            )
                                        } catch {
                                            let msg = NSAlert()
                                            if let pmkError = error as? PMKError, pmkError.isCancelled {
                                                let isBeta = SettingsStore.shared.betaReleasesEnabled
                                                msg.messageText = isBeta ? "You're Up To Date (Beta)" : "You're Up To Date"
                                                msg.informativeText = isBeta
                                                    ? "You're already running the latest build available in the beta channel."
                                                    : "You're already running the latest version of \(ConnectingCaptionsProduct.displayName)."
                                            } else {
                                                msg.messageText = "Update Check Failed"
                                                msg.informativeText = "Unable to check for updates. Please try again later.\n\nError: \(error.localizedDescription)"
                                            }
                                            msg.alertStyle = .informational
                                            msg.runModal()
                                        }
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(self.theme.palette.accent)
                                .controlSize(.regular)

                                AppButton("Release Notes") {
                                    if let url = ConnectingCaptionsProduct.releasesURL {
                                        NSWorkspace.shared.open(url)
                                    }
                                }
                                .disabled(ConnectingCaptionsProduct.releasesURL == nil)
                                .buttonStyle(.bordered)
                                .controlSize(.regular)

                                Button(self.rollbackVersion.isEmpty ? "Rollback" : "Rollback to \(self.rollbackVersion)") {
                                    guard !self.isRollingBack else { return }

                                    let infoText = self.rollbackVersion.isEmpty ? "your previously installed version" : self.rollbackVersion
                                    let targetVersion = self.rollbackVersion
                                    let confirm = NSAlert()
                                    confirm.messageText = "Rollback to \(infoText)?"
                                    confirm.informativeText = "This will restore a previous app version and relaunch \(ConnectingCaptionsProduct.displayName)."
                                    confirm.alertStyle = .warning
                                    confirm.addButton(withTitle: "Rollback")
                                    confirm.addButton(withTitle: "Cancel")

                                    guard confirm.runModal() == .alertFirstButtonReturn else { return }

                                    self.isRollingBack = true
                                    Task {
                                        defer {
                                            Task { @MainActor in
                                                self.isRollingBack = false
                                            }
                                        }

                                        do {
                                            try await SimpleUpdater.shared.rollbackToLatestBackup()
                                            await MainActor.run {
                                                let success = NSAlert()
                                                success.messageText = "Rollback Successful"
                                                success.informativeText = "Rolled back to \(targetVersion). \(ConnectingCaptionsProduct.displayName) will relaunch shortly."
                                                success.alertStyle = .informational
                                                success.addButton(withTitle: "Report Bug")
                                                success.addButton(withTitle: "OK")
                                                let response = success.runModal()
                                                if response == .alertFirstButtonReturn {
                                                    self.openIssueReportingPage()
                                                }
                                            }
                                        } catch {
                                            await MainActor.run {
                                                let fail = NSAlert()
                                                fail.messageText = "Rollback Failed"
                                                fail.informativeText = error.localizedDescription
                                                fail.alertStyle = .critical
                                                fail.addButton(withTitle: "OK")
                                                fail.runModal()
                                                self.refreshRollbackState()
                                            }
                                        }
                                    }
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.regular)
                                .disabled(self.rollbackVersion.isEmpty || self.isRollingBack)
                                .opacity(self.isRollingBack ? 0.7 : 1.0)

                                AppButton("Get Previous Builds") {
                                    self.openPreviousBuildPicker()
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.regular)
                            }
                            .padding(.top, 12)

                            if self.rollbackVersion.isEmpty {
                                AppText("No rollback backup found.")
                                    .font(self.theme.typography.bodySmall)
                                    .foregroundStyle(self.settingsSecondaryText)
                            } else {
                                AppText("Rollback target: {0}", arguments: [String(describing: self.rollbackVersion)])
                                    .font(self.theme.typography.bodySmall)
                                    .foregroundStyle(self.settingsSecondaryText)
                            }
                        }
                    }
                    .padding(16)
                }
                .shownInSettingsSection(.general, selectedSection: self.selectedSection)

                CommercialLicenseStatusCard(showsKeyField: true)
                    .settingsSearchTarget(.commercialLicense)
                    .shownInSettingsSection(.general, selectedSection: self.selectedSection)

                if self.asr.micStatus != .authorized {
                    // Only surface microphone permission when the user needs to act.
                    ThemedCard(style: .standard) {
                        VStack(alignment: .leading, spacing: 14) {
                            FluidSectionHeader(title: AppLanguage.text("Microphone Permission"), systemImage: "mic.fill")

                            VStack(alignment: .leading, spacing: 12) {
                                HStack(spacing: 10) {
                                    Circle()
                                        .fill(self.theme.palette.warning)
                                        .frame(width: 8, height: 8)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(
                                            self.asr.micStatus == .denied
                                                ? "Microphone access denied"
                                                : "Microphone access not determined"
                                        )
                                        .font(self.theme.typography.bodyStrong)
                                        .foregroundStyle(self.theme.palette.warning)

                                        AppText("Microphone access is required for voice recording")
                                            .font(self.theme.typography.bodySmall)
                                            .foregroundStyle(self.settingsSecondaryText)
                                    }
                                    Spacer()

                                    if self.asr.micStatus == .notDetermined {
                                        Button {
                                            self.asr.requestMicAccess()
                                        } label: {
                                            AppLabel("Grant Access", systemImage: "mic.fill")
                                        }
                                        .buttonStyle(.borderedProminent)
                                        .tint(self.theme.palette.accent)
                                        .controlSize(.regular)
                                    } else if self.asr.micStatus == .denied {
                                        Button {
                                            self.asr.openSystemSettingsForMic()
                                        } label: {
                                            AppLabel("Open Settings", systemImage: "gear")
                                        }
                                        .buttonStyle(.bordered)
                                        .controlSize(.regular)
                                    }
                                }

                                self.instructionsBox(
                                    title: AppLanguage.text("How to enable microphone access:"),
                                    steps: self.asr.micStatus == .notDetermined
                                        ? ["Click **Grant Access** above", "Choose **Allow** in the system dialog"]
                                        : [
                                            "Click **Open Settings** above",
                                            "Find **\(self.appDisplayName)** in the microphone list",
                                            "Toggle **\(self.appDisplayName) ON** to allow access",
                                        ]
                                )
                            }
                        }
                        .padding(16)
                    }
                    .settingsSearchTarget(.microphonePermission)
                    .shownInSettingsSection(.audio, selectedSection: self.selectedSection)
                }

                // Global Hotkey Card
                ThemedCard(style: .standard) {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(spacing: 8) {
                            FluidSectionHeader(title: AppLanguage.text("Global Hotkey"), systemImage: "keyboard")

                            Spacer()

                            if self.accessibilityEnabled {
                                if self.isRecordingAnyShortcut {
                                    AppText("Recording…")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.orange)
                                } else if self.hotkeyManagerInitialized {
                                    HStack(spacing: 6) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(Color.fluidGreen)
                                            .font(.caption)
                                        AppText("Active")
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(self.settingsSecondaryText)
                                    }
                                } else {
                                    AppText("Initializing…")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(self.settingsSecondaryText)
                                }
                            }
                        }
                        .settingsSearchTarget(.globalHotkey)

                        if self.accessibilityEnabled {
                            VStack(alignment: .leading, spacing: 12) {
                                if self.isRecordingAnyShortcut {
                                    HStack(spacing: 8) {
                                        Image(systemName: "hand.point.up.left.fill")
                                            .foregroundStyle(.orange)
                                        AppText("Press your new hotkey combination now…")
                                            .font(.caption)
                                            .foregroundStyle(.orange)
                                    }
                                } else if !self.hotkeyManagerInitialized {
                                    HStack(spacing: 8) {
                                        ProgressView()
                                            .controlSize(.small)
                                            .fixedSize()
                                        AppText("Hotkey initializing…")
                                            .font(.caption)
                                            .foregroundStyle(self.settingsSecondaryText)
                                    }
                                }

                                // MARK: - Shortcuts Section

                                VStack(alignment: .leading, spacing: 8) {
                                    AppText("Shortcuts")
                                        .font(self.theme.typography.bodySmallStrong)
                                        .foregroundStyle(self.settingsTitleText)

                                    AppText("Dictation starts from a shortcut. Theater Listen is on the Theater page.")
                                        .font(.caption)
                                        .foregroundStyle(self.settingsTertiaryText)

                                    if SettingsStore.shared.listeningHotkeyEnabled {
                                        self.primaryDictationShortcutsList()
                                            .settingsSearchTarget(.primaryDictationShortcuts)
                                        self.dictationPromptPicker(for: .primary)
                                        Divider().opacity(0.2).padding(.vertical, 4)
                                    }

                                    self.shortcutRow(
                                        content: .init(
                                            icon: "xmark.circle.fill",
                                            iconColor: .secondary,
                                            title: AppLanguage.text("Cancel Recording"),
                                            description: AppLanguage.text("Cancel the current recording or dismiss the active recording overlay")
                                        ),
                                        shortcut: self.cancelRecordingShortcut,
                                        isRecording: self.isRecording(.cancel),
                                        isAnyRecordingActive: self.isRecordingAnyShortcut,
                                        recordingMessage: self.isRecording(.cancel) ? self.shortcutRecordingMessage : nil,
                                        onChangePressed: {
                                            DebugLogger.shared.debug("Starting to record new cancel shortcut", source: "SettingsView")
                                            self.shortcutRecordingMessage = nil
                                            self.activeShortcutRecordingTarget = .cancel
                                        }
                                    )
                                    .settingsSearchTarget(.cancelRecordingShortcut)
                                    Divider().opacity(0.2).padding(.vertical, 4)

                                    self.shortcutRow(
                                        content: .init(
                                            icon: "arrow.down.doc",
                                            iconColor: .secondary,
                                            title: AppLanguage.text("Paste Last Transcription"),
                                            description: AppLanguage.text("Re-insert your most recent transcription without using the clipboard")
                                        ),
                                        shortcut: self.pasteLastTranscriptionShortcut,
                                        isRecording: self.isRecording(.pasteLast),
                                        isAnyRecordingActive: self.isRecordingAnyShortcut,
                                        recordingMessage: self.isRecording(.pasteLast) ? self.shortcutRecordingMessage : nil,
                                        isEnabled: self.$pasteLastTranscriptionShortcutEnabled,
                                        requiresShortcutToEnable: true,
                                        onChangePressed: {
                                            DebugLogger.shared.debug("Starting to record new paste last transcription shortcut", source: "SettingsView")
                                            self.shortcutRecordingMessage = nil
                                            self.activeShortcutRecordingTarget = .pasteLast
                                        },
                                        onRemovePressed: {
                                            if self.activeShortcutRecordingTarget == .pasteLast {
                                                self.shortcutRecordingMessage = nil
                                                self.activeShortcutRecordingTarget = nil
                                            }
                                            self.pasteLastTranscriptionShortcut = nil
                                            self.pasteLastTranscriptionShortcutEnabled = false
                                        }
                                    )
                                    .settingsSearchTarget(.pasteLastTranscriptionShortcut)
                                }
                                .padding(12)
                                .background(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(self.theme.palette.elevatedCardBackground)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                                .stroke(self.theme.palette.cardBorder.opacity(0.45), lineWidth: 1)
                                        )
                                )
                            }
                        } else {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack(spacing: 10) {
                                    Circle()
                                        .fill(self.theme.palette.warning)
                                        .frame(width: 8, height: 8)

                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack(spacing: 6) {
                                            Image(systemName: "exclamationmark.triangle.fill")
                                                .foregroundStyle(self.theme.palette.warning)
                                            AppText("Accessibility is only for typing into other apps")
                                                .font(self.theme.typography.bodyStrong)
                                                .foregroundStyle(self.theme.palette.warning)
                                        }
                                        AppText("Theater captions do not need this. Enable it to type a translation or dictation into another app.")
                                            .font(self.theme.typography.bodySmall)
                                            .foregroundStyle(self.settingsSecondaryText)
                                    }
                                    Spacer()

                                    AppButton("Open Accessibility Settings") {
                                        self.openAccessibilitySettings()
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .tint(self.theme.palette.accent)
                                    .controlSize(.regular)
                                }

                                self.instructionsBox(
                                    title: AppLanguage.text("Follow these steps to enable Accessibility:"),
                                    steps: [
                                        "Click **Open Accessibility Settings** above",
                                        "In the Accessibility window, click the **+ button**",
                                        "Select **\(self.appDisplayName)**; use **Reveal in Finder** below if needed",
                                        "Click **Open**, then toggle **\(self.appDisplayName) ON** in the list",
                                    ],
                                    warningStyle: true
                                )

                                HStack(spacing: 10) {
                                    AppButton("Reveal in Finder") {
                                        self.revealAppInFinder()
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)

                                    AppButton("Open Applications") {
                                        self.openApplicationsFolder()
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                }
                            }
                            .settingsSearchTarget(.accessibilityPermission)
                        }

                                // MARK: - Options Section

                                VStack(spacing: 12) {
                                    self.optionToggleRow(
                                        title: AppLanguage.text("Start listening with a keyboard shortcut"),
                                        description: AppLanguage.text("Dictation. Types what you said. Does not translate."),
                                        isOn: Binding(
                                            get: { SettingsStore.shared.listeningHotkeyEnabled },
                                            set: { newValue in
                                                SettingsStore.shared.listeningHotkeyEnabled = newValue
                                                self.hotkeyManager?.updatePrimaryShortcuts(self.primaryDictationShortcuts)
                                            }
                                        )
                                    )
                                    .settingsSearchTarget(.activationMode)
                                    Divider().opacity(0.2)

                                    if SettingsStore.shared.listeningHotkeyEnabled {
                                        HStack(alignment: .center) {
                                            VStack(alignment: .leading, spacing: 2) {
                                                AppText("Shortcut behavior")
                                                    .font(self.theme.typography.bodyStrong)
                                                    .foregroundStyle(self.settingsTitleText)
                                                Text(self.hotkeyMode.description)
                                                    .font(self.theme.typography.bodySmall)
                                                    .foregroundStyle(self.settingsSecondaryText)
                                                    .fixedSize(horizontal: false, vertical: true)
                                            }
                                            .frame(maxWidth: .infinity, alignment: .leading)

                                            Picker("", selection: self.$hotkeyMode) {
                                                ForEach(HotkeyActivationMode.allCases) { mode in
                                                    AppText(mode.displayName).tag(mode)
                                                }
                                            }
                                            .pickerStyle(.menu)
                                            .frame(width: 170, alignment: .trailing)
                                        }
                                        .onChange(of: self.hotkeyMode) { _, newValue in
                                            SettingsStore.shared.hotkeyMode = newValue
                                            self.hotkeyManager?.setHotkeyMode(newValue)
                                        }
                                        Divider().opacity(0.2)
                                    }

                                    self.optionToggleRow(
                                        title: AppLanguage.text("Copy to Clipboard"),
                                        description: AppLanguage.text("Automatically copy transcribed text to clipboard as a backup."),
                                        isOn: self.$copyToClipboard
                                    )
                                    .onChange(of: self.copyToClipboard) { _, newValue in
                                        SettingsStore.shared.copyTranscriptionToClipboard = newValue
                                    }
                                    .settingsSearchTarget(.copyToClipboard)
                                    Divider().opacity(0.2)

                                    HStack(alignment: .center) {
                                        VStack(alignment: .leading, spacing: 2) {
                                            AppText("Text Insertion Mode")
                                                .font(self.theme.typography.bodyStrong)
                                                .foregroundStyle(self.settingsTitleText)
                                            Text(SettingsStore.shared.textInsertionMode.description)
                                                .font(self.theme.typography.bodySmall)
                                                .foregroundStyle(self.settingsSecondaryText)
                                                .fixedSize(horizontal: false, vertical: true)
                                        }
                                        .frame(maxWidth: .infinity, alignment: .leading)

                                        Picker("", selection: Binding(
                                            get: { SettingsStore.shared.textInsertionMode },
                                            set: { SettingsStore.shared.textInsertionMode = $0 }
                                        )) {
                                            ForEach(SettingsStore.TextInsertionMode.allCases) { mode in
                                                AppText(mode.displayName).tag(mode)
                                            }
                                        }
                                        .pickerStyle(.menu)
                                        .frame(width: 170, alignment: .trailing)
                                    }
                                    .settingsSearchTarget(.textInsertionMode)
                                    Divider().opacity(0.2)

                                    self.spokenSendSettings
                                        .settingsSearchTarget(.spokenSend)
                                    Divider().opacity(0.2)

                                    self.optionToggleRow(
                                        title: AppLanguage.text("Weekends Don't Break Streak"),
                                        description: AppLanguage.text("Skip Saturday and Sunday when calculating usage streaks. Perfect for weekday-only users."),
                                        isOn: Binding(
                                            get: { SettingsStore.shared.weekendsDontBreakStreak },
                                            set: { SettingsStore.shared.weekendsDontBreakStreak = $0 }
                                        )
                                    )
                                    .settingsSearchTarget(.usageStreak)
                                    Divider().opacity(0.2)

                                    self.optionToggleRow(
                                        title: AppLanguage.text("Skip Silent Recordings"),
                                        description: AppLanguage.text("Avoid transcription when a recording up to four seconds contains only clear silence. Disabled by default to preserve quiet speech."),
                                        isOn: Binding(
                                            get: { SettingsStore.shared.skipSilentRecordingsEnabled },
                                            set: { SettingsStore.shared.skipSilentRecordingsEnabled = $0 }
                                        )
                                    )
                                    .settingsSearchTarget(.skipSilentRecordings)
                                    Divider().opacity(0.2)

                                    DictionarySuggestionsSettingsRow()
                                        .settingsSearchTarget(.dictionarySuggestions)
                                }
                                .padding(12)
                    }
                    .padding(16)
                }
                .shownInSettingsSection(.dictation, selectedSection: self.selectedSection)

                ThemedCard(style: .standard) {
                    VStack(alignment: .leading, spacing: 14) {
                        FluidSectionHeader(title: AppLanguage.text("Text Formatting"), systemImage: "textformat")

                        VStack(spacing: 16) {
                            self.settingsToggleRow(
                                title: AppLanguage.text("Lowercase First Letter"),
                                description: AppLanguage.text("Start each transcription with a lowercase letter."),
                                isOn: Binding(
                                    get: { self.settings.gaavLowercaseFirstLetterEnabled },
                                    set: { self.settings.gaavLowercaseFirstLetterEnabled = $0 }
                                )
                            )
                            Divider().opacity(0.2)

                            self.settingsToggleRow(
                                title: AppLanguage.text("Remove Trailing Period"),
                                description: AppLanguage.text("Drop a final period from transcriptions."),
                                isOn: Binding(
                                    get: { self.settings.gaavRemoveTrailingPeriodEnabled },
                                    set: { self.settings.gaavRemoveTrailingPeriodEnabled = $0 }
                                )
                            )
                            Divider().opacity(0.2)

                            self.settingsToggleRow(
                                title: AppLanguage.text("Slash Commands & @ Formatting"),
                                description: AppLanguage.text("Convert spoken slash commands and supported @ mentions into symbols."),
                                isOn: Binding(
                                    get: { self.settings.literalDictationFormattingEnabled },
                                    set: { self.settings.literalDictationFormattingEnabled = $0 }
                                )
                            )
                            Divider().opacity(0.2)

                            self.settingsToggleRow(
                                title: AppLanguage.text("Space Between Dictations"),
                                description: AppLanguage.text("Add spacing when consecutive dictations are joined."),
                                isOn: Binding(
                                    get: { self.settings.continuousDictationSpacingEnabled },
                                    set: { self.settings.continuousDictationSpacingEnabled = $0 }
                                )
                            )
                            Divider().opacity(0.2)

                            self.settingsToggleRow(
                                title: AppLanguage.text("Smart Capitalization"),
                                description: AppLanguage.text("Use text before the cursor to choose uppercase or lowercase."),
                                isOn: Binding(
                                    get: { self.settings.contextAwareCapitalizationEnabled },
                                    set: { self.settings.contextAwareCapitalizationEnabled = $0 }
                                )
                            )
                        }
                    }
                    .padding(16)
                }
                .settingsSearchTarget(.textFormatting)
                .shownInSettingsSection(.dictation, selectedSection: self.selectedSection)

                // Notification Settings Card
                ThemedCard(style: .standard) {
                    VStack(alignment: .leading, spacing: 14) {
                        VStack(alignment: .leading, spacing: 12) {
                            self.optionToggleRow(
                                title: AppLanguage.text("Microphone Changes"),
                                description: AppLanguage.format("Show an alert when {0} changes or loses its microphone.", String(describing: ConnectingCaptionsProduct.displayName)),
                                isOn: Binding(
                                    get: { self.settings.showMicrophoneChangeAlerts },
                                    set: { enabled in
                                        self.settings.showMicrophoneChangeAlerts = enabled
                                        if enabled == false {
                                            MicrophoneChangeOverlayController.shared.hide()
                                        }
                                    }
                                )
                            )
                            .settingsSearchTarget(.microphoneChanges)
                        }
                    }
                    .padding(16)
                }
                .shownInSettingsSection(.notifications, selectedSection: self.selectedSection)

                // Audio Devices Card
                ThemedCard(style: .standard) {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            FluidSectionHeader(title: AppLanguage.text("Audio Devices"), systemImage: "mic")

                            Spacer()

                            Button {
                                self.refreshDevices()
                                // Update cached default device names on refresh
                                let defaultInput = AudioDevice.getDefaultInputDevice()
                                self.cachedDefaultInputUID = defaultInput?.uid ?? ""
                                self.cachedDefaultOutputName = AudioDevice.getDefaultOutputDevice()?.name ?? ""
                            } label: {
                                AppLabel("Refresh", systemImage: "arrow.clockwise")
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }

                        VStack(alignment: .leading, spacing: 12) {
                            self.microphonePrioritySection
                                .settingsSearchTarget(.inputDevicePriority)
                                .onChange(of: self.inputDevices) { _, newDevices in
                                    let defaultInput = AudioDevice.getDefaultInputDevice()
                                    self.cachedDefaultInputUID = defaultInput?.uid ?? ""
                                    guard newDevices.isEmpty == false else { return }
                                    if let selectedInput = self.appServices.microphonePreferenceCoordinator
                                        .reconcileMicrophoneSelection(
                                            availableInputs: newDevices,
                                            defaultInputUID: self.cachedDefaultInputUID
                                        )
                                    {
                                        self.selectedInputUID = selectedInput.uid
                                    }
                                }

                            HStack {
                                AppText("Output Device")
                                    .font(self.theme.typography.bodyStrong)
                                    .foregroundStyle(self.settingsTitleText)
                                Spacer()
                                Picker("", selection: self.$selectedOutputUID) {
                                    // Handle empty state gracefully
                                    if self.outputDevices.isEmpty {
                                        AppText("Loading...").tag("")
                                    } else {
                                        ForEach(self.outputDevices, id: \.uid) { dev in
                                            // Add "(System Default)" tag using cached name to avoid CoreAudio calls during layout
                                            let isSystemDefault = !self.cachedDefaultOutputName.isEmpty && dev.name == self.cachedDefaultOutputName
                                            Text(isSystemDefault ? "\(dev.name) (System Default)" : dev.name).tag(dev.uid)
                                        }
                                    }
                                }
                                .pickerStyle(.menu)
                                .frame(width: 240)
                                .disabled(self.asr.isRunning) // Disable device changes during recording
                                .onChange(of: self.selectedOutputUID) { oldUID, newUID in
                                    guard !newUID.isEmpty else { return }

                                    // Prevent device changes during active recording
                                    if self.asr.isRunning {
                                        DebugLogger.shared.warning("Cannot change output device during recording", source: "SettingsView")
                                        // Revert to previous value
                                        self.selectedOutputUID = oldUID
                                        return
                                    }

                                    SettingsStore.shared.preferredOutputDeviceUID = newUID
                                    _ = AudioDevice.setDefaultOutputDevice(uid: newUID)
                                }
                                // Sync selection when devices load or change
                                .onChange(of: self.outputDevices) { _, newDevices in
                                    // Update cached default device name when device list changes
                                    self.cachedDefaultOutputName = AudioDevice.getDefaultOutputDevice()?.name ?? ""

                                    if !newDevices.isEmpty {
                                        let currentValid = newDevices.contains { $0.uid == self.selectedOutputUID }
                                        if !currentValid {
                                            if let prefUID = SettingsStore.shared.preferredOutputDeviceUID,
                                               newDevices.contains(where: { $0.uid == prefUID })
                                            {
                                                self.selectedOutputUID = prefUID
                                            } else if let defaultUID = AudioDevice.getDefaultOutputDevice()?.uid,
                                                      newDevices.contains(where: { $0.uid == defaultUID })
                                            {
                                                self.selectedOutputUID = defaultUID
                                            } else {
                                                self.selectedOutputUID = newDevices.first?.uid ?? ""
                                            }
                                        }
                                    }
                                }
                            }
                            .settingsSearchTarget(.outputDevice)

                            self.microphoneQualityGuidance
                        }
                    }
                    .padding(16)
                }
                .shownInSettingsSection(.audio, selectedSection: self.selectedSection)

                // Overlay Settings Card
                ThemedCard(style: .standard) {
                    VStack(alignment: .leading, spacing: 14) {
                        FluidSectionHeader(title: AppLanguage.text("Recording Overlay"), systemImage: "rectangle.on.rectangle")
                        AppText("This is the dictation recording chip. It is not Theater.")
                            .font(self.theme.typography.bodySmall)
                            .foregroundStyle(self.settingsSecondaryText)
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    AppText("Sensitivity")
                                        .font(self.theme.typography.bodyStrong)
                                        .foregroundStyle(self.settingsTitleText)
                                    AppText("Control how sensitive the audio visualizer is to sound input")
                                        .font(self.theme.typography.bodySmall)
                                        .foregroundStyle(self.settingsSecondaryText)
                                }

                                Spacer()

                                AppButton("Reset") {
                                    self.visualizerNoiseThreshold = 0.4
                                    SettingsStore.shared.visualizerNoiseThreshold = self.visualizerNoiseThreshold
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                            .settingsSearchTarget(.overlaySensitivity)

                            HStack(spacing: 10) {
                                AppText("More")
                                    .font(.caption)
                                    .foregroundStyle(self.settingsSecondaryText)
                                    .frame(width: 36, alignment: .trailing)

                                Slider(value: self.$visualizerNoiseThreshold, in: 0.01...0.8, step: 0.01)
                                    .controlSize(.regular)

                                AppText("Less")
                                    .font(.caption)
                                    .foregroundStyle(self.settingsSecondaryText)
                                    .frame(width: 36, alignment: .leading)

                                Text(String(format: "%.2f", self.visualizerNoiseThreshold))
                                    .font(.caption.monospaced())
                                    .foregroundStyle(self.settingsTertiaryText)
                                    .frame(width: 36)
                            }

                            Divider().padding(.vertical, 8)

                            // Overlay Position
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    AppText("Overlay Position")
                                        .font(self.theme.typography.bodyStrong)
                                        .foregroundStyle(self.settingsTitleText)
                                    AppText("Where the recording indicator appears on screen")
                                        .font(self.theme.typography.bodySmall)
                                        .foregroundStyle(self.settingsSecondaryText)
                                }

                                Spacer()

                                Picker("", selection: self.$settings.overlayPosition) {
                                    ForEach(SettingsStore.OverlayPosition.allCases, id: \.self) { position in
                                        AppText(position.displayName).tag(position)
                                    }
                                }
                                .pickerStyle(.menu)
                                .frame(width: 170, alignment: .trailing)
                            }
                            .settingsSearchTarget(.overlayPosition)

                            Divider().padding(.vertical, 8)

                            VStack(alignment: .leading, spacing: 10) {
                                HStack(alignment: .top) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        AppText("Transcription Preview Length")
                                            .font(self.theme.typography.bodyStrong)
                                            .foregroundStyle(self.settingsTitleText)
                                        AppText("How many recent characters appear in the notch/pill preview")
                                            .font(self.theme.typography.bodySmall)
                                            .foregroundStyle(self.settingsSecondaryText)
                                    }

                                    Spacer()

                                    AppText("{0} chars", arguments: [String(describing: self.settings.transcriptionPreviewCharLimit)])
                                        .font(.caption.monospaced())
                                        .foregroundStyle(self.settingsSecondaryText)
                                }

                                HStack(spacing: 10) {
                                    AppText("Less")
                                        .font(.caption)
                                        .foregroundStyle(self.settingsSecondaryText)
                                        .frame(width: 36, alignment: .trailing)

                                    Slider(
                                        value: Binding(
                                            get: { Double(self.settings.transcriptionPreviewCharLimit) },
                                            set: { self.settings.transcriptionPreviewCharLimit = Int($0.rounded()) }
                                        ),
                                        in: Double(SettingsStore.transcriptionPreviewCharLimitRange.lowerBound)...Double(SettingsStore.transcriptionPreviewCharLimitRange.upperBound),
                                        step: Double(SettingsStore.transcriptionPreviewCharLimitStep)
                                    )
                                    .controlSize(.regular)

                                    AppText("More")
                                        .font(.caption)
                                        .foregroundStyle(self.settingsSecondaryText)
                                        .frame(width: 36, alignment: .leading)
                                }
                            }
                            .settingsSearchTarget(.transcriptionPreviewLength)

                            Divider().padding(.vertical, 4)

                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(self.settings.overlayPosition == .bottom ? "Overlay Size" : "Notch Style")
                                        .font(self.theme.typography.bodyStrong)
                                        .foregroundStyle(self.settingsTitleText)
                                    Text(
                                        self.settings.overlayPosition == .bottom
                                            ? "How large the recording indicator appears"
                                            : "Choose the regular notch or the compact layout"
                                    )
                                    .font(self.theme.typography.bodySmall)
                                    .foregroundStyle(self.settingsSecondaryText)
                                }

                                Spacer()

                                if self.settings.overlayPosition == .bottom {
                                    Picker("", selection: self.$settings.overlaySize) {
                                        ForEach(SettingsStore.OverlaySize.allCases, id: \.self) { size in
                                            AppText(size.displayName).tag(size)
                                        }
                                    }
                                    .pickerStyle(.menu)
                                    .frame(width: 170, alignment: .trailing)
                                } else {
                                    Picker("", selection: self.$settings.notchPresentationMode) {
                                        ForEach(SettingsStore.NotchPresentationMode.allCases, id: \.self) { mode in
                                            AppText(mode.displayName).tag(mode)
                                        }
                                    }
                                    .pickerStyle(.menu)
                                    .frame(width: 170, alignment: .trailing)
                                }
                            }
                            .settingsSearchTarget(.overlayStyle)

                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    AppText("Live Preview")
                                        .font(self.theme.typography.bodyStrong)
                                        .foregroundStyle(self.settingsTitleText)
                                    AppText("Show transcription text in the overlay while you speak")
                                        .font(self.theme.typography.bodySmall)
                                        .foregroundStyle(self.settingsSecondaryText)
                                }

                                Spacer()

                                Toggle("", isOn: self.$enableStreamingPreview)
                                    .labelsHidden()
                                    .onChange(of: self.enableStreamingPreview) { _, newValue in
                                        SettingsStore.shared.enableStreamingPreview = newValue
                                    }
                            }
                            .settingsSearchTarget(.livePreview)

                            // Bottom overlay specific settings (only show when bottom is selected)
                            if self.settings.overlayPosition == .bottom {
                                Divider().padding(.vertical, 4)

                                // Bottom Offset
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        AppText("Bottom Offset")
                                            .font(self.theme.typography.bodyStrong)
                                            .foregroundStyle(self.settingsTitleText)
                                        AppText("Distance from bottom of screen")
                                            .font(self.theme.typography.bodySmall)
                                            .foregroundStyle(self.settingsSecondaryText)
                                    }

                                    Spacer()

                                    HStack(spacing: 6) {
                                        Slider(value: self.$settings.overlayBottomOffset, in: 20...500)
                                            .frame(width: 110)
                                            .controlSize(.small)

                                        AppText("{0} px", arguments: [String(describing: Int(self.settings.overlayBottomOffset))])
                                            .font(.caption.monospaced())
                                            .foregroundStyle(self.settingsSecondaryText)
                                            .frame(width: 54, alignment: .trailing)
                                    }
                                    .frame(width: 170, alignment: .trailing)
                                }
                                .settingsSearchTarget(.bottomOffset)
                            }

                            if self.asr.isRunning {
                                AppText("Settings are disabled during active recording")
                                    .font(.caption)
                                    .foregroundStyle(self.settingsSecondaryText)
                                    .italic()
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.top, 4)
                            }
                        }
                    }
                    .padding(16)
                }
                .settingsSearchTarget(.overlay)
                .shownInSettingsSection(.dictation, selectedSection: self.selectedSection)

                self.historySettingsCard
                    .shownInSettingsSection(.dataAndDiagnostics, selectedSection: self.selectedSection)

                // Backup & Restore Card
                ThemedCard(style: .standard) {
                    self.backupUtilityRow()
                        .padding(16)
                }
                .settingsSearchTarget(.backupAndRestore)
                .shownInSettingsSection(.dataAndDiagnostics, selectedSection: self.selectedSection)

                // Debug Settings Card
                ThemedCard(style: .standard) {
                    VStack(alignment: .leading, spacing: 14) {
                        FluidSectionHeader(title: AppLanguage.text("Debug Settings"), systemImage: "ladybug.fill")

                        VStack(alignment: .leading, spacing: 8) {
                            self.settingsToggleRow(
                                title: AppLanguage.text("Show Debug Logs in App"),
                                description: AppLanguage.text("File logs are always collected for diagnostics."),
                                isOn: Binding(
                                    get: { SettingsStore.shared.enableDebugLogs },
                                    set: { SettingsStore.shared.enableDebugLogs = $0 }
                                )
                            )

                            Divider().padding(.vertical, 8)

                            Button {
                                let url = FileLogger.shared.currentLogFileURL()
                                if FileManager.default.fileExists(atPath: url.path) {
                                    NSWorkspace.shared.activateFileViewerSelecting([url])
                                } else {
                                    DebugLogger.shared.info("Log file not found at \(url.path)", source: "SettingsView")
                                }
                            } label: {
                                AppLabel("Reveal Log File", systemImage: "doc.richtext")
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.regular)

                            DiagnosticLogClearButton()

                            AppText("The debug log contains detailed information about app operations and can help with troubleshooting.")
                                .font(self.theme.typography.bodySmall)
                                .foregroundStyle(self.settingsSecondaryText)
                            AppText("Crash diagnostics are written to Library/Logs/connectingCaptions/connectingCaptions.log by default.")
                                .font(self.theme.typography.bodySmall)
                                .foregroundStyle(self.settingsSecondaryText)
                        }
                    }
                    .padding(16)
                }
                .settingsSearchTarget(.debugLogs)
                .shownInSettingsSection(.dataAndDiagnostics, selectedSection: self.selectedSection)

                ThemedCard(style: .standard) {
                    VStack(alignment: .leading, spacing: 14) {
                        self.settingsToggleRow(
                            title: AppLanguage.text("Show Performance in History"),
                            description: AppLanguage.text("Display transcription time and optional cleanup time."),
                            isOn: Binding(
                                get: { SettingsStore.shared.showHistoryPerformanceMetrics },
                                set: { SettingsStore.shared.showHistoryPerformanceMetrics = $0 }
                            )
                        )
                        .settingsSearchTarget(.historyPerformance)

                        Divider().padding(.vertical, 4)

                        HStack(alignment: .center) {
                            VStack(alignment: .leading, spacing: 2) {
                                AppText("Run Onboarding Again")
                                    .font(self.theme.typography.bodyStrong)
                                    .foregroundStyle(self.settingsTitleText)
                                AppText("Replay the first-run Theater setup. Your models and settings stay.")
                                    .font(self.theme.typography.bodySmall)
                                    .foregroundStyle(self.settingsSecondaryText)
                            }
                            Spacer()
                            AppButton("Run Onboarding") {
                                self.settings.resetOnboardingProgress()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                    .padding(16)
                }
                .settingsSearchTarget(.experimental)
                .shownInSettingsSection(.experimental, selectedSection: self.selectedSection)
            }
            .fluidPageContent()
            .environment(\.settingsSearchPresentation, self.settingsSearchPresentation)
        }
        .id(self.selectedSection)
        .task(id: self.selectedSection) {
            await self.prepareSelectedSection()
        }
        .onChange(of: self.visualizerNoiseThreshold) { _, newValue in
            SettingsStore.shared.visualizerNoiseThreshold = newValue
        }
    }

    func refreshRollbackState() {
        self.rollbackVersion = SimpleUpdater.shared.latestRollbackVersion() ?? ""
    }

    func openIssueReportingPage() {
        guard let url = ConnectingCaptionsProduct.issuesURL else { return }
        NSWorkspace.shared.open(url)
    }

    func exportBackup() {
        Task { await self.performBackupExport() }
    }

    func performBackupExport() async {
        do {
            let panel = NSSavePanel()
            panel.canCreateDirectories = true
            panel.allowedContentTypes = [.json]
            panel.nameFieldStringValue = BackupService.shared.suggestedFilename()

            guard panel.runModal() == .OK, let url = panel.url else { return }

            let document = try await BackupService.shared.makeBackupDocument()
            let data = try BackupService.shared.encode(document)
            try data.write(to: url, options: .atomic)

            self.presentInfoAlert(
                title: AppLanguage.text("Backup Exported"),
                message: AppLanguage.format("Saved your {0} backup to:\n{1}", String(describing: ConnectingCaptionsProduct.displayName), String(describing: url.path))
            )
        } catch {
            self.presentErrorAlert(
                title: AppLanguage.text("Backup Export Failed"),
                message: error.localizedDescription
            )
        }
    }

    func importBackup() {
        Task { await self.performBackupImport() }
    }

    func performBackupImport() async {
        do {
            let panel = NSOpenPanel()
            panel.canChooseDirectories = false
            panel.canChooseFiles = true
            panel.allowsMultipleSelection = false
            panel.allowedContentTypes = [.json]

            guard panel.runModal() == .OK, let url = panel.url else { return }

            let data = try Data(contentsOf: url)
            let document = try BackupService.shared.decode(data)

            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short

            let confirm = NSAlert()
            confirm.messageText = "Import this backup?"
            confirm.informativeText = """
            This replaces your current settings, prompt profiles, and stats history.

            Exported: \(formatter.string(from: document.exportedAt))
            API keys are not included and will not be changed.
            """
            confirm.alertStyle = .warning
            confirm.addButton(withTitle: "Import")
            confirm.addButton(withTitle: "Cancel")

            guard confirm.runModal() == .alertFirstButtonReturn else { return }

            try await BackupService.shared.restore(document)
            self.syncLocalSettingsAfterBackupRestore()

            self.presentInfoAlert(
                title: AppLanguage.text("Backup Imported"),
                message: AppLanguage.text("Your settings, prompt profiles, and stats were restored successfully.")
            )
        } catch {
            self.presentErrorAlert(
                title: AppLanguage.text("Backup Import Failed"),
                message: error.localizedDescription
            )
        }
    }

    func syncLocalSettingsAfterBackupRestore() {
        self.refreshAudioHistoryUsage()
    }

    /// Handing the audio walk to the background is the whole point of this
    /// helper. Counting every saved `.wav` on the main actor stalls the settings
    /// panel for as long as the walk takes, and four of the call sites below run
    /// inside a click or a modal alert, where the stall is the whole interaction.
    /// Nothing reads `audioHistoryUsageBytes` on the same turn, so a late but
    /// non-blocking number is strictly better than an on-time frozen panel.
    func refreshAudioHistoryUsage() {
        Task { await self.refreshAudioHistoryUsageInBackground() }
    }

    func applyAudioHistoryBudget() async {
        let normalized = self.audioHistoryBudgetText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        guard let value = Double(normalized), value > 0 else {
            self.presentErrorAlert(title: AppLanguage.text("Invalid Budget"), message: AppLanguage.text("Enter a positive number of GB."))
            self.refreshAudioHistoryUsage()
            return
        }

        let newBudget = max(0.1, value)
        let newBudgetBytes = DictationAudioHistoryStore.bytes(forGigabytes: newBudget)
        // Measure fresh usage rather than trusting `audioHistoryUsageBytes`, which is
        // populated by a background scan and can still read its 0 default here — a
        // stale/zero value would skip this confirmation while pruning still deletes
        // real audio below.
        let currentUsageBytes = await Task.detached(priority: .utility) {
            DictationAudioHistoryStore.shared.audioUsageBytes()
        }.value
        self.audioHistoryUsageBytes = currentUsageBytes
        if currentUsageBytes > newBudgetBytes {
            let confirm = NSAlert()
            confirm.messageText = "Prune saved audio?"
            confirm.informativeText = """
            This budget is below current audio usage. \(ConnectingCaptionsProduct.displayName) will delete the oldest saved audio first and keep transcript history.
            """
            confirm.alertStyle = .warning
            confirm.addButton(withTitle: "Apply and Prune")
            confirm.addButton(withTitle: "Cancel")
            guard confirm.runModal() == .alertFirstButtonReturn else {
                self.refreshAudioHistoryUsage()
                return
            }
        }

        SettingsStore.shared.audioHistoryBudgetGB = newBudget
        do {
            let pruned = try await TranscriptionHistoryStore.shared.pruneAudioToBudget()
            self.refreshAudioHistoryUsage()
            if pruned > 0 {
                self.presentInfoAlert(title: AppLanguage.text("Audio Pruned"), message: AppLanguage.format("Deleted oldest saved audio from {0} history entries.", String(describing: pruned)))
            }
        } catch {
            self.refreshAudioHistoryUsage()
            self.presentInfoAlert(title: AppLanguage.text("Audio Pruning Failed"), message: error.localizedDescription)
        }
    }

    func deleteSavedAudio() {
        let confirm = NSAlert()
        confirm.messageText = "Delete saved audio?"
        confirm.informativeText = "This removes saved dictation audio only. Transcript history stays intact."
        confirm.alertStyle = .warning
        confirm.addButton(withTitle: "Delete Audio")
        confirm.addButton(withTitle: "Cancel")
        guard confirm.runModal() == .alertFirstButtonReturn else { return }

        let removed = TranscriptionHistoryStore.shared.deleteAllSavedAudio()
        self.refreshAudioHistoryUsage()
        self.presentInfoAlert(title: AppLanguage.text("Audio Deleted"), message: AppLanguage.format("Removed audio from {0} history entries.", String(describing: removed)))
    }

    func exportAudioZip() {
        Task { @MainActor in
            do {
                let entries = try await TranscriptionHistoryStore.shared.entriesWithSavedAudio()
                guard entries.contains(where: {
                    DictationAudioHistoryStore.shared.audioFileExists(for: $0)
                }) else {
                    throw DictationAudioHistoryError.noAudioEntries
                }

                let panel = NSSavePanel()
                panel.canCreateDirectories = true
                panel.allowedContentTypes = [.zip]
                panel.nameFieldStringValue = DictationAudioHistoryStore.shared.suggestedAudioExportFilename()

                guard panel.runModal() == .OK, let url = panel.url else { return }
                try await DictationAudioHistoryStore.shared.exportAudioArchive(
                    entries: entries,
                    to: url
                )
                self.presentInfoAlert(title: AppLanguage.text("Audio Export Saved"), message: AppLanguage.format("Saved your dictation audio export to:\n{0}", String(describing: url.path)))
            } catch {
                self.presentErrorAlert(title: AppLanguage.text("Audio Export Failed"), message: error.localizedDescription)
            }
        }
    }

    func presentInfoAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    func presentErrorAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .critical
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    func openPreviousBuildPicker() {
        Task { @MainActor in
            do {
                let repository = try SimpleUpdater.shared.publishedRepository()
                let options = try await SimpleUpdater.shared.fetchRecentReleaseBuildOptions(
                    owner: repository.owner,
                    repo: repository.repo,
                    limit: 3,
                    includePrerelease: SettingsStore.shared.betaReleasesEnabled
                )
                self.presentPreviousBuildPicker(options)
            } catch {
                self.openAllReleasesPage()
            }
        }
    }

    func presentPreviousBuildPicker(_ options: [SimpleUpdater.ReleaseBuildOption]) {
        guard !options.isEmpty else {
            self.openAllReleasesPage()
            return
        }

        let picker = NSAlert()
        picker.messageText = "Download Previous Build"
        picker.informativeText = "No local rollback backup was found. Choose a recent release build:"
        picker.alertStyle = .informational

        for option in options {
            picker.addButton(withTitle: option.version)
        }
        picker.addButton(withTitle: "All Releases")
        picker.addButton(withTitle: "Cancel")

        let response = picker.runModal()
        let first = NSApplication.ModalResponse.alertFirstButtonReturn.rawValue
        let index = response.rawValue - first

        if index >= 0, index < options.count {
            NSWorkspace.shared.open(options[index].url)
            return
        }
        if index == options.count {
            self.openAllReleasesPage()
        }
    }

    func openAllReleasesPage() {
        guard let url = ConnectingCaptionsProduct.releasesURL else { return }
        NSWorkspace.shared.open(url)
    }

}

struct MicrophonePriorityDropDelegate: DropDelegate {
    let targetUID: String
    let settings: SettingsStore
    @Binding var draggedUID: String?
    let reorderAnimation: Animation?
    let onDropCompleted: () -> Void

    func validateDrop(info _: DropInfo) -> Bool {
        self.draggedUID != nil
    }

    func dropEntered(info _: DropInfo) {
        guard let draggedUID = self.draggedUID,
              draggedUID != self.targetUID
        else { return }

        let entries = self.settings.microphonePriority
        guard let sourceIndex = entries.firstIndex(where: { $0.uid == draggedUID }),
              let targetIndex = entries.firstIndex(where: { $0.uid == self.targetUID })
        else { return }

        withAnimation(self.reorderAnimation) {
            self.settings.reorderMicrophonePriority(
                fromOffsets: IndexSet(integer: sourceIndex),
                toOffset: targetIndex > sourceIndex ? targetIndex + 1 : targetIndex
            )
        }
    }

    func dropUpdated(info _: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info _: DropInfo) -> Bool {
        self.draggedUID = nil
        self.onDropCompleted()
        return true
    }
}

private extension View {
    @ViewBuilder
    func shownInSettingsSection(_ section: SettingsSection, selectedSection: SettingsSection) -> some View {
        if section == selectedSection {
            self
        }
    }
}

