import AppKit
import AVFoundation
import SwiftUI

struct LiveTranslationHomeView: View {
    @EnvironmentObject private var appServices: AppServices
    @Environment(\.theme) private var theme
    @ObservedObject private var settings = SettingsStore.shared
    @ObservedObject private var controller = LiveTranslationController.shared

    var openVoiceEngine: (() -> Void)?
    var openTranslationEngine: (() -> Void)?

    private var asr: ASRService {
        self.appServices.asr
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                self.header
                    .padding(.bottom, 8)
                if !TheaterAvailability.isSupported {
                    Text(TheaterAvailability.unsupportedCopy)
                        .font(self.theme.typography.body)
                        .foregroundStyle(self.theme.palette.warning)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("theater.needsMacOS26")
                }
                if self.theaterStatusText != nil {
                    self.statusRow
                }
                if TheaterAvailability.isSupported {
                    if self.readySnapshot.needsAttention {
                        self.readinessCard
                    }
                    self.stageCard
                    DisclosureGroup(AppLanguage.text("Caption appearance")) {
                        TheaterCaptionAppearanceSettings()
                            .padding(.top, 12)
                    }
                    .accessibilityIdentifier("theater.home.appearance")
                    if self.settings.theaterListenUsed, self.settings.theaterSessionMode.showsTranslation {
                        TheaterTalkPackCard()
                    }
                    ThemedCard(style: .standard, hoverEffect: false) {
                        DisclosureGroup(AppLanguage.text("Advanced")) {
                            VStack(alignment: .leading, spacing: 16) {
                                TheaterEngineCards(
                                    openVoiceEngine: self.openVoiceEngine,
                                    openTranslationEngine: self.openTranslationEngine,
                                    showsPurpose: false
                                )
                                TheaterAdvancedSettings()
                            }
                            .padding(.top, 12)
                        }
                        .accessibilityIdentifier("theater.home.advanced")
                    }
                }
                if self.settings.isCommerciallyLicensed || self.settings.commercialLicenseRecord != nil {
                    CommercialLicenseStatusCard(compact: true)
                }
            }
            .fluidPageContent()
            .onAppear {
                self.controller.alignSpokenEngineWithTheater()
                Task { await MicrophoneAccess.refresh(self.asr) }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                Task { await MicrophoneAccess.refresh(self.asr) }
            }
            .onChange(of: self.settings.theaterSessionMode) { _, _ in
                Task { await MicrophoneAccess.refresh(self.asr) }
            }
        }
    }

    private var modePicker: some View {
        TheaterModeSection(accessibilityIdentifier: "theater.mode")
    }

    private var stageCard: some View {
        ThemedCard(style: .prominent, hoverEffect: false) {
            VStack(alignment: .leading, spacing: 16) {
                self.modePicker
                self.sectionRule
                TranslationLanguagePairCard(showsCard: false)
                self.sectionRule
                TheaterMicrophoneStatus()
                self.sectionRule
                TheaterCaptionStackPreview(
                    message: self.settings.theaterListenUsed
                        ? TheaterReadiness.boardAfterFirstCaption
                        : TheaterReadiness.boardIdle,
                    lines: TheaterBoardPreview.current(
                        session: self.settings.theaterSessionMode,
                        spokenMode: self.settings.theaterSpokenLineMode
                    ),
                    titleSize: 22,
                    spokenSize: 13
                )
                self.sectionRule
                TheaterAudienceCard(showsCard: false)
                if self.settings.theaterSessionMode.showsTranslation {
                    Text(
                        SpokenLanguageResolver.isDynamicPairingEnabled()
                            ? TheaterReadiness.eitherWayCloseMic
                            : TheaterReadiness.oneSpeakerCloseMic
                    )
                    .font(self.theme.typography.bodySmall)
                    .foregroundStyle(self.theme.palette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("theater.stage.closeMic")
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("theater.stage")
    }

    private var sectionRule: some View {
        Rectangle()
            .fill(self.theme.palette.separator)
            .frame(height: 1)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var statusRow: some View {
        if let status = self.theaterStatusText {
            HStack(spacing: 8) {
                Text(status)
                    .font(self.theme.typography.caption)
                    .foregroundStyle(self.theaterStatusColor)
                    .accessibilityIdentifier("theater.status")
                if self.controller.subscriber.canRetryTranslation {
                    AppButton("Retry") {
                        self.controller.retryFailedTranslation()
                    }
                    .buttonStyle(.theaterTextCompact)
                    .help(TheaterChromeHelp.retry)
                    .accessibilityIdentifier("theater.home.retry")
                }
            }
        }
    }

    private var header: some View {
        FluidPageHeader(
            systemImage: "captions.bubble",
            title: AppLanguage.text("Theater"),
            subtitle: ConnectingCaptionsProduct.tagline
        ) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    OpenTheaterButton()
                    TheaterListenButton()
                }
                VStack(alignment: .trailing, spacing: 6) {
                    OpenTheaterButton()
                    TheaterListenButton()
                }
            }
        }
    }

    private var theaterStatusColor: Color {
        if self.controller.subscriber.statusKind.usesWarningColor {
            return self.theme.palette.warning
        }
        if self.controller.subscriber.statusKind == .success {
            return self.theme.palette.accent
        }
        return self.theme.palette.secondaryText
    }

    private var theaterStatusText: String? {
        if self.controller.isPaused {
            return TheaterReadiness.pausedStatus
        }
        if self.controller.isSessionActive, self.controller.listenKind == .captions {
            if self.controller.subscriber.statusKind.usesWarningColor {
                let failure = self.controller.subscriber.statusText
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !failure.isEmpty,
                   failure != "Listening…",
                   failure != SpokenLanguageResolver.voiceEngineMismatchMessage()
                {
                    return failure
                }
            }
            return TheaterReadiness.listeningStatus
        }
        let failure = self.controller.subscriber.statusText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !failure.isEmpty, failure != "Listening…" {
            if failure == SpokenLanguageResolver.voiceEngineMismatchMessage() {
                return nil
            }
            return failure
        }
        if self.settings.theaterWindowEnabled {
            return self.settings.theaterMinimized
                ? TheaterReadiness.theaterMinimizedStatus
                : TheaterReadiness.theaterOpenStatus
        }
        return nil
    }

    private var readySnapshot: TheaterReadyGate.Snapshot {
        TheaterReadyGate.liveSnapshot(
            pack: self.controller.packAvailability,
            microphone: self.asr.micStatus,
            firstCaptionPrinted: self.settings.theaterListenUsed
        )
    }

    private var readinessCard: some View {
        ThemedCard(style: .standard, hoverEffect: false) {
            TheaterReadinessChecklist(
                openVoiceEngine: self.openVoiceEngine,
                openTranslationEngine: self.openTranslationEngine,
                compact: true
            )
        }
        .accessibilityIdentifier("theater.readiness")
    }
}

struct LiveTranslationSettingsView: View {
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var settings = SettingsStore.shared
    @ObservedObject private var controller = LiveTranslationController.shared
    @ObservedObject private var subscriber = LiveTranslationController.shared.subscriber
    @State private var showClearConfirmation = false
    @State private var speakOutputDevices: [AudioDevice.Device] = []
    @State private var advancedExpanded = false
    @Environment(\.settingsSearchPresentation) private var searchPresentation

    var recordListenShortcut: (() -> Void)?
    var isRecordingListenShortcut = false
    var shortcutRecordingMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            self.theaterAppearanceCard
                .settingsSearchTarget(.theaterAppearance)

            self.sessionControlsCard
                .settingsSearchTarget(.theaterPlayback)
            ThemedCard(style: .standard, hoverEffect: false) {
                DisclosureGroup(AppLanguage.text("Advanced"), isExpanded: self.$advancedExpanded) {
                    VStack(alignment: .leading, spacing: 16) {
                        TheaterAdvancedSettings()
                            .settingsSearchTarget(.theaterAdvanced)
                        TranslateListenShortcutCard(
                            recordListenShortcut: self.recordListenShortcut,
                            isRecordingListenShortcut: self.isRecordingListenShortcut,
                            shortcutRecordingMessage: self.shortcutRecordingMessage
                        )
                        .settingsSearchTarget(.captionListenShortcut)
                    }
                    .padding(.top, 12)
                }
            }
        }
        .alert(AppLanguage.text("Clear captions?"), isPresented: self.$showClearConfirmation) {
            AppButton("Cancel", role: .cancel) {}
            AppButton("Clear", role: .destructive) {
                self.controller.clearBoard()
            }
        } message: {
            AppText(TheaterReadiness.clearCaptionsConfirm)
        }
        .onChange(of: self.searchPresentation?.matchedTargets, initial: true) { _, targets in
            if targets?.contains(.captionListenShortcut) == true || targets?.contains(.theaterAdvanced) == true {
                self.advancedExpanded = true
            }
        }
    }

    private var theaterAppearanceCard: some View {
        TheaterCaptionAppearanceSettings()
    }

    private var sessionControlsCard: some View {
        ThemedCard(style: .standard, hoverEffect: false) {
            VStack(alignment: .leading, spacing: 14) {
                FluidSectionHeader(title: AppLanguage.text("Playback and session"), systemImage: "speaker.wave.2")
                self.settingsToggleRow(
                    title: AppLanguage.text("Speak captions"),
                    description: self.spokenCaptionAvailability.detail
                ) {
                    AppToggle("Speak captions", isOn: Binding(
                        get: { self.settings.theaterSpeakCaptions && self.spokenCaptionAvailability == .ready },
                        set: { enabled in
                            self.settings.theaterSpeakCaptions = enabled
                            if !enabled { TheaterSpokenDelivery.shared.dropPending() }
                        }
                    ))
                        .disabled(self.spokenCaptionAvailability != .ready)
                        .toggleStyle(.switch)
                        .tint(self.theme.palette.accent)
                        .labelsHidden()
                        .accessibilityLabel(AppLanguage.text("Speak captions"))
                        .accessibilityIdentifier("theater.settings.speakCaptions")
                }

                self.speakOutputPicker

                self.settingsToggleRow(title: AppLanguage.text("Clear captions"), description: TheaterReadiness.clearCaptions) {
                    AppButton("Clear") { self.showClearConfirmation = true }
                        .buttonStyle(.theaterTextDestructive)
                        .disabled(!self.canClearCaptions)
                        .accessibilityLabel(AppLanguage.text("Clear captions"))
                        .accessibilityIdentifier("theater.settings.clear")
                }
            }
        }
    }

    private var spokenCaptionAvailability: SpokenCaptionAvailability {
        .current(settings: self.settings, outputUIDs: self.speakOutputDevices.map(\.uid))
    }

    private var speakOutputPicker: some View {
        VStack(alignment: .leading, spacing: 4) {
            AppText("Speak on")
                .font(self.theme.typography.bodyStrong)
                .foregroundStyle(self.settingsTitleText)
            Picker(AppLanguage.text("Speak on"), selection: Binding<String>(
                get: { self.settings.preferredOutputDeviceUID ?? "" },
                set: { uid in
                    self.settings.preferredOutputDeviceUID = uid.isEmpty ? nil : uid
                }
            )) {
                AppText("System output").tag(String(""))
                if let uid = self.settings.preferredOutputDeviceUID, !uid.isEmpty,
                   !self.speakOutputDevices.contains(where: { $0.uid == uid }) {
                    AppText("Disconnected output").tag(uid)
                }
                ForEach(self.speakOutputDevices, id: \.uid) { device in
                    Text(device.name).tag(String(device.uid))
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .accessibilityIdentifier("theater.settings.speakOutput")
        }
        .onReceive(AppServices.shared.audioObserver.$changeTick) { _ in
            self.speakOutputDevices = AudioDevice.listOutputDevices()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            self.speakOutputDevices = AudioDevice.listOutputDevices()
        }
    }

    private func settingsToggleRow<Accessory: View>(
        title: String,
        description: String,
        @ViewBuilder accessory: @escaping () -> Accessory
    ) -> some View {
        TheaterSettingRow(title: title, detail: description, control: accessory)
    }

    /// What the caption title line actually renders at, before the window's
    /// width grows it further or a short Overlay bar shrinks it to fit.
    private var renderedCaptionSize: Int {
        Int(TheaterCaptionScale.translatedSize(setting: CGFloat(self.settings.presenterFontSize)).rounded())
    }

    private var canClearCaptions: Bool {
        self.controller.hasClearableBoard
            || self.subscriber.committedLines.contains {
                !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
    }

    private var settingsTitleText: Color {
        Color(nsColor: .labelColor)
    }

    private var settingsSecondaryText: Color {
        self.colorScheme == .light ? Color(nsColor: .labelColor).opacity(0.90) : self.theme.palette.primaryText.opacity(0.82)
    }
}

struct OpenTheaterButton: View {
    @ObservedObject private var settings = SettingsStore.shared
    @ObservedObject private var controller = LiveTranslationController.shared

    private var homeAction: TheaterMinimize.HomeAction {
        TheaterMinimize.homeAction(
            windowEnabled: self.settings.theaterWindowEnabled,
            minimized: self.settings.theaterMinimized
        )
    }

    var body: some View {
        Button {
            switch self.homeAction {
            case .close:
                PresenterCaptionController.shared.requestClose()
            case .open, .show:
                PresenterCaptionController.shared.setVisible(true)
            }
        } label: {
            TheaterActionLabel(
                title: TheaterMinimize.homeTitle(for: self.homeAction),
                systemImage: TheaterMinimize.homeSystemImage(for: self.homeAction)
            )
        }
        .buttonStyle(.theaterText)
        .disabled(!TheaterAvailability.isSupported)
        .help(
            TheaterAvailability.isSupported
                ? TheaterMinimize.homeHelp(
                    for: self.homeAction,
                    listening: self.controller.isSessionActive && self.controller.listenKind == .captions
                )
                : TheaterAvailability.unsupportedCopy
        )
        .accessibilityLabel(TheaterMinimize.homeTitle(for: self.homeAction))
        .accessibilityIdentifier("theater.open")
    }
}

struct TheaterListenButton: View {
    var usesChromeKey = false
    var listenIdentifier = "theater.listen"
    var stopIdentifier = "theater.listen"
    var pauseIdentifier = "theater.home.pause"

    @ObservedObject private var controller = LiveTranslationController.shared
    @ObservedObject private var settings = SettingsStore.shared
    @ObservedObject private var asr = AppServices.shared.asr
    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isListening: Bool {
        self.controller.isSessionActive && self.controller.listenKind == .captions
    }

    private var listenTitle: String {
        if self.controller.isFinishingSession {
            return "Stopping…"
        }
        return self.isListening ? "Stop" : "Listen"
    }

    private var snapshot: TheaterReadyGate.Snapshot {
        TheaterReadyGate.liveSnapshot(
            pack: self.controller.packAvailability,
            microphone: self.asr.micStatus,
            firstCaptionPrinted: self.settings.theaterListenUsed
        )
    }

    private var dictationBusy: Bool {
        !self.isListening && self.asr.isRunningOrStarting
    }

    private var listenHelp: String {
        if self.dictationBusy {
            return TheaterReadiness.dictationBusy
        }
        if self.isListening {
            return TheaterReadiness.stopHelp
        }
        if self.snapshot.canListen {
            return TheaterReadiness.pressListen
        }
        return self.snapshot.nextAction
    }

    private var listenButtonStyle: TheaterTextButtonStyle {
        if self.isListening || self.controller.isFinishingSession {
            return self.usesChromeKey ? .theaterTextCompactStop : .theaterTextStop
        }
        return self.usesChromeKey ? .theaterTextCompactProminent : .theaterTextProminent
    }

    var body: some View {
        HStack(spacing: self.usesChromeKey ? 4 : 8) {
            if self.isListening, !self.usesChromeKey {
                self.listeningWaveform
            }
            if self.isListening {
                Button {
                    self.run {
                        if self.controller.isPaused {
                            self.controller.resumeListening()
                        } else {
                            self.controller.pauseListening()
                        }
                    }
                } label: {
                    TheaterActionLabel(
                        title: self.controller.isPaused ? "Resume" : "Pause",
                        systemImage: self.usesChromeKey
                            ? nil
                            : (self.controller.isPaused ? "play.fill" : "pause.fill"),
                        compact: self.usesChromeKey
                    )
                }
                .buttonStyle(self.usesChromeKey ? .theaterTextCompact : .theaterText)
                .theaterTag(
                    self.usesChromeKey
                        ? (self.controller.isPaused ? TheaterChromeHelp.resume : TheaterChromeHelp.pause)
                        : (self.controller.isPaused ? TheaterReadiness.resumeHelp : TheaterReadiness.pauseHelp),
                    paints: self.usesChromeKey
                )
                .accessibilityLabel(self.controller.isPaused ? "Resume" : "Pause")
                .accessibilityIdentifier(self.pauseIdentifier)
            }

            Button {
                self.run {
                    if self.isListening {
                        self.controller.stopListening()
                    } else if self.usesChromeKey {
                        self.controller.startCaptionListening()
                    } else {
                        LiveTranslationController.shared.toggleCaptionListening()
                    }
                }
            } label: {
                TheaterActionLabel(
                    title: self.listenTitle,
                    systemImage: self.usesChromeKey
                        ? nil
                        : (self.isListening || self.controller.isFinishingSession ? "stop.fill" : "mic.fill"),
                    compact: self.usesChromeKey
                )
            }
            .buttonStyle(self.listenButtonStyle)
            .disabled(
                self.controller.isFinishingSession
                    || (!self.isListening && (!self.snapshot.canListen || self.dictationBusy))
            )
            .theaterTag(
                self.usesChromeKey
                    ? (self.isListening ? TheaterChromeHelp.stop : TheaterChromeHelp.listen)
                    : self.listenHelp,
                paints: self.usesChromeKey
            )
            .accessibilityLabel(self.listenTitle)
            .accessibilityIdentifier(self.isListening ? self.stopIdentifier : self.listenIdentifier)
        }
        .onAppear {
            Task { await MicrophoneAccess.refresh(self.asr) }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await MicrophoneAccess.refresh(self.asr) }
        }
    }

    @ViewBuilder
    private var listeningWaveform: some View {
        let image = Image(systemName: "waveform")
            .font(.system(size: self.usesChromeKey ? 12 : 15, weight: .semibold))
            .foregroundStyle(self.theme.palette.accent)
            .accessibilityHidden(true)
        if self.reduceMotion {
            image
        } else {
            image.symbolEffect(.variableColor.iterative, isActive: true)
        }
    }

    private func run(_ action: () -> Void) {
        if self.usesChromeKey {
            PresenterCaptionController.shared.performChromeAction(action)
        } else {
            action()
        }
    }
}

struct TranslationLanguagePairCard: View {
    @Environment(\.theme) private var theme
    @ObservedObject private var settings = SettingsStore.shared
    @ObservedObject private var controller = LiveTranslationController.shared
    @State private var downloadRequestID: UUID?
    @State private var downloadTask: Task<Void, Never>?
    private var isRequestingPack: Bool {
        self.downloadRequestID != nil
    }

    var showsCard = true

    var body: some View {
        Group {
            if self.showsCard {
                ThemedCard(style: .standard, hoverEffect: false) {
                    self.cardBody
                }
            } else {
                self.cardBody
            }
        }
        .task(id: self.availabilityPair) {
            await self.prepareAndRefreshAvailability()
        }
        .onChange(of: self.availabilityPair) { _, _ in
            self.downloadTask?.cancel()
            self.downloadRequestID = nil
        }
        .onDisappear {
            self.downloadTask?.cancel()
            self.downloadRequestID = nil
        }
    }

    private var availabilityPair: TranslationPairKey {
        .current()
    }

    private var cardBody: some View {
        VStack(alignment: .leading, spacing: 14) {
            FluidSectionHeader(title: AppLanguage.text("Languages"), systemImage: "globe")
                .accessibilityIdentifier("theater.languages")
            self.languagePairRow
            self.engineHint
            if self.settings.theaterSessionMode == .translation {
                Label(AppLanguage.format("{0} · {1}", SpokenLanguageResolver.pairLabel(), self.pairStatus.title),
                      systemImage: self.pairStatus.symbol)
                    .font(self.theme.typography.caption)
                    .foregroundStyle(self.pairStatus == .ready ? self.theme.palette.accent : self.theme.palette.warning)
                    .accessibilityIdentifier("theater.languages.pairStatus")
            }
            self.packAction
        }
    }

    private var languagePairRow: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 10) {
                self.iSpeakPicker
                if self.settings.theaterSessionMode == .translation {
                    self.swapButton
                    self.showAsPicker
                }
            }
            VStack(alignment: .leading, spacing: 12) {
                self.iSpeakPicker
                if self.settings.theaterSessionMode == .translation {
                    HStack(alignment: .center, spacing: 10) {
                        self.swapButton
                        self.showAsPicker
                    }
                }
            }
        }
    }

    private var iSpeakPicker: some View {
        self.languagePicker(
            title: AppLanguage.text("I speak"),
            selection: self.sourceLanguageID,
            languages: LanguageChoicePolicy.spokenLanguages(),
            isSource: true,
            issueHint: { language in
                let model = self.settings.selectedSpeechModel
                guard !VoiceEngineLanguageCatalog.supports(model, languageID: language.id) else { return nil }
                return "not heard by \(model.displayName)"
            }
        )
    }

    private var showAsPicker: some View {
        self.languagePicker(
            title: AppLanguage.text("Show as"),
            selection: self.targetLanguageID,
            languages: self.targetLanguages,
            issueHint: { language in
                let source = SpokenLanguageResolver.sourceLanguage()
                guard source.id != language.id else { return nil }
                guard self.controller.appleEngine.cachedPackAvailability(source: source, target: language) == .unsupported
                else { return nil }
                return "not supported by Apple Translation"
            }
        )
    }

    private func languagePicker(
        title: String,
        selection: Binding<String>,
        languages: [TranslationLanguage],
        isSource: Bool = false,
        issueHint: ((TranslationLanguage) -> String?)? = nil
    ) -> some View {
        TheaterLanguageMenu(
            title: title,
            selection: selection,
            languages: languages,
            issueHint: issueHint,
            status: { LanguageChoicePolicy.status(for: $0, isSource: isSource) }
        )
    }

    private var swapButton: some View {
        Button {
            self.controller.swapDirection()
        } label: {
            Image(systemName: "arrow.left.arrow.right")
                .font(.system(size: 12, weight: .semibold))
                .accessibilityHidden(true)
        }
        .buttonStyle(.theaterTextIcon)
        .disabled(!LanguageChoicePolicy.canSwap())
        .help(LanguageChoicePolicy.swapUnavailableReason() ?? TheaterChromeHelp.swapLanguages)
        .accessibilityLabel(AppLanguage.text("Swap languages"))
    }

    private var engineHint: some View {
        let source = SpokenLanguageResolver.sourceLanguage()
        let readiness = VoiceEngineLanguageReadiness.current(model: self.settings.selectedSpeechModel, languageID: source.id)
        return Text(SpokenLanguageResolver.stageEngineSummary())
            .font(self.theme.typography.caption)
            .foregroundStyle(readiness == .ready ? self.theme.palette.secondaryText : self.theme.palette.warning)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var packAction: some View {
        if self.packUnsupported {
            AppText(TheaterReadiness.packUnsupported)
                .font(self.theme.typography.caption)
                .foregroundStyle(self.theme.palette.warning)
                .fixedSize(horizontal: false, vertical: true)
        } else if self.showsPackDownload {
            Button(self.isRequestingPack ? TheaterReadiness.downloadPackBusy : TheaterReadiness.downloadPack) {
                let requestID = UUID()
                self.downloadRequestID = requestID
                let source = SpokenLanguageResolver.sourceLanguage()
                let target = SpokenLanguageResolver.targetLanguage()
                self.downloadTask = Task {
                    await self.controller.requestNeededLanguagePackDownload()
                    // The download sheet polls and dismisses itself, but never tells
                    // this card — without this loop, Listen stays disabled forever
                    // after a successful download that takes longer than one check.
                    let deadline = ProcessInfo.processInfo.systemUptime + 180
                    while !self.controller.packAvailability.isReady,
                          self.controller.packAvailability != .unsupported,
                          ProcessInfo.processInfo.systemUptime < deadline
                    {
                        try? await Task.sleep(nanoseconds: 2_000_000_000)
                        if Task.isCancelled {
                            break
                        }
                        guard source.id == SpokenLanguageResolver.sourceLanguage().id,
                              target.id == SpokenLanguageResolver.targetLanguage().id
                        else { break }
                        await self.prepareAndRefreshAvailability()
                    }
                    if self.downloadRequestID == requestID {
                        self.downloadRequestID = nil
                    }
                }
            }
            .buttonStyle(.theaterText)
            .disabled(self.isRequestingPack)
            .help(TheaterChromeHelp.downloadPack)
        }
    }

    private var pairStatus: LanguageOptionStatus {
        .resolve(speech: nil, translation: self.controller.packAvailability)
    }

    private var packUnsupported: Bool {
        self.settings.theaterSessionMode == .translation && !SpokenLanguageResolver.isSameLanguagePair()
            && self.controller.packAvailability == .unsupported
    }

    private var showsPackDownload: Bool {
        self.settings.theaterSessionMode == .translation && !SpokenLanguageResolver.isSameLanguagePair()
            && self.controller.packAvailability == .supported
    }

    private var sourceLanguageID: Binding<String> {
        Binding(
            get: { SpokenLanguageResolver.sourceLanguage().id },
            set: { id in
                self.controller.applySourceLanguage(id)
            }
        )
    }

    private var targetLanguageID: Binding<String> {
        Binding(
            get: { SpokenLanguageResolver.targetLanguage().id },
            set: { id in
                self.controller.applyTargetLanguage(id)
            }
        )
    }

    private var targetLanguages: [TranslationLanguage] {
        LanguageChoicePolicy.targetLanguages()
    }

    private func prepareAndRefreshAvailability() async {
        await self.controller.refreshPackAvailability()
    }
}

/// Shortcut key shown the same way on Listen and Listen and type.
struct TheaterShortcutBadge: View {
    @Environment(\.theme) private var theme

    var text: String
    var isRecording: Bool

    var body: some View {
        Text(self.text)
            .font(self.theme.typography.caption.monospaced().weight(.medium))
            .foregroundStyle(self.isRecording ? self.theme.palette.warning : self.theme.palette.primaryText)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(
                        self.isRecording
                            ? self.theme.palette.warning.opacity(0.16)
                            : self.theme.palette.separator.opacity(0.45)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(
                                self.isRecording
                                    ? self.theme.palette.warning.opacity(0.5)
                                    : self.theme.palette.separator,
                                lineWidth: 1
                            )
                    }
            }
    }
}

struct TranslateListenShortcutCard: View {
    @Environment(\.theme) private var theme
    @ObservedObject private var settings = SettingsStore.shared

    var recordListenShortcut: (() -> Void)?
    var isRecordingListenShortcut = false
    var shortcutRecordingMessage: String?

    var body: some View {
        ThemedCard(style: .standard, hoverEffect: false) {
            VStack(alignment: .leading, spacing: 14) {
                FluidSectionHeader(title: AppLanguage.text("Listen Shortcut"), systemImage: "mic.fill")
                    .accessibilityIdentifier("theater.listenShortcut")

                AppText("Starts or stops Theater Listen. It does not type into another app.")
                    .font(self.theme.typography.bodySmall)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                TheaterSettingRow(
                    title: AppLanguage.text("Theater Listen shortcut"),
                    detail: AppLanguage.text("Separate from dictation and Insert.")
                ) {
                    AppToggle("Enable Theater Listen shortcut", isOn: Binding(
                        get: { self.settings.captionListenHotkeyEnabled },
                        set: { self.settings.captionListenHotkeyEnabled = $0 }
                    ))
                    .toggleStyle(.switch)
                    .tint(self.theme.palette.accent)
                    .labelsHidden()
                    .disabled(self.settings.captionListenHotkeyShortcut == nil && !self.settings.captionListenHotkeyEnabled)
                    .accessibilityLabel(AppLanguage.text("Enable Theater Listen shortcut"))
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        TheaterShortcutBadge(
                            text: self.isRecordingListenShortcut
                                ? "Press shortcut…"
                                : (self.settings.captionListenHotkeyShortcut?.displayString ?? "Not set"),
                            isRecording: self.isRecordingListenShortcut
                        )

                        if let recordListenShortcut {
                            Button(self.isRecordingListenShortcut ? "Cancel" : "Change") {
                                recordListenShortcut()
                            }
                            .buttonStyle(.theaterText)
                        }
                    }

                    if self.isRecordingListenShortcut, let shortcutRecordingMessage, !shortcutRecordingMessage.isEmpty {
                        Text(shortcutRecordingMessage)
                            .font(self.theme.typography.caption)
                            .foregroundStyle(self.theme.palette.warning)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }
}

struct TranslateInsertShortcutCard: View {
    @Environment(\.theme) private var theme
    @ObservedObject private var settings = SettingsStore.shared

    var recordTranslateShortcut: (() -> Void)?
    var isRecordingTranslateShortcut = false
    var shortcutRecordingMessage: String?
    var accessibilityTrusted = true
    var openAccessibility: () -> Void = {}

    var body: some View {
        ThemedCard(style: .standard, hoverEffect: false) {
            VStack(alignment: .leading, spacing: 14) {
                FluidSectionHeader(title: AppLanguage.text("Shortcut"), systemImage: "text.cursor")

                AppText(TheaterReadiness.typeIntoAppBody)
                    .font(self.theme.typography.bodySmall)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if !self.settings.theaterListenUsed {
                    AppText(TheaterReadiness.typeIntoAppLocked)
                        .font(self.theme.typography.caption)
                        .foregroundStyle(self.theme.palette.warning)
                        .accessibilityIdentifier("theater.listenAndType.locked")
                }

                if DictationHotkeyCaptureStart.blocksListenAndType(
                    enabled: self.settings.translationInsertHotkeyEnabled,
                    accessibilityTrusted: self.accessibilityTrusted
                ) {
                    AppText(TheaterReadiness.typeIntoAppNeedsAccessibility)
                        .font(self.theme.typography.caption)
                        .foregroundStyle(self.theme.palette.warning)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("theater.listenAndType.accessibility")
                    AppButton("Allow Accessibility", action: self.openAccessibility)
                        .buttonStyle(.theaterText)
                        .controlSize(.regular)
                }

                TheaterSettingRow(
                    title: AppLanguage.text("Listen, then type shortcut"),
                    detail: TheaterReadiness.typeIntoAppShortcutDetail
                ) {
                    AppToggle("Enable listen and type shortcut", isOn: Binding(
                        get: { self.settings.translationInsertHotkeyEnabled },
                        set: { enabled in
                            self.settings.translationInsertHotkeyEnabled = enabled
                            if DictationHotkeyCaptureStart.blocksListenAndType(
                                enabled: enabled,
                                accessibilityTrusted: self.accessibilityTrusted
                            ) {
                                self.openAccessibility()
                            }
                        }
                    ))
                    .toggleStyle(.switch)
                    .tint(self.theme.palette.accent)
                    .labelsHidden()
                    .disabled(
                        !self.settings.theaterListenUsed
                            || (self.settings.translationInsertHotkeyShortcut == nil
                                && !self.settings.translationInsertHotkeyEnabled)
                    )
                    .accessibilityLabel(AppLanguage.text("Enable Listen, then type shortcut"))
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        TheaterShortcutBadge(
                            text: self.isRecordingTranslateShortcut
                                ? "Press shortcut…"
                                : (self.settings.translationInsertHotkeyShortcut?.displayString ?? "Not set"),
                            isRecording: self.isRecordingTranslateShortcut
                        )

                        if let recordTranslateShortcut {
                            Button(self.isRecordingTranslateShortcut ? "Cancel" : "Change") {
                                recordTranslateShortcut()
                            }
                            .buttonStyle(.theaterText)
                            .disabled(!self.settings.theaterListenUsed)
                        }
                    }

                    if self.isRecordingTranslateShortcut, let shortcutRecordingMessage, !shortcutRecordingMessage.isEmpty {
                        Text(shortcutRecordingMessage)
                            .font(self.theme.typography.caption)
                            .foregroundStyle(self.theme.palette.warning)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }
}

/// Who sees the captions: the room, the meeting, or both.
struct TheaterAudienceCard: View {
    @Environment(\.theme) private var theme
    var showsCard = true

    var body: some View {
        if self.showsCard {
            ThemedCard(style: .standard, hoverEffect: false) {
                self.cardBody
            }
        } else {
            self.cardBody
        }
    }

    private var cardBody: some View {
        Text(AppLanguage.text(TheaterReadiness.screenShare))
            .font(self.theme.typography.bodySmall)
            .foregroundStyle(self.theme.palette.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("theater.audience")
            .help(TheaterChromeHelp.screenShare)
    }
}
