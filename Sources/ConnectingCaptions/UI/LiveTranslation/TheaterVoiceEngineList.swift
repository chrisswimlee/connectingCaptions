import SwiftUI

/// Voice Engine picker. Every available speech-to-text model gets its own
/// scannable card — title, status badge, description, specs, and actions —
/// so Not Downloaded / Installed / Active is obvious at a glance.
struct TheaterVoiceEngineList: View {
    @ObservedObject var viewModel: VoiceEngineSettingsViewModel
    @Environment(\.theme) private var theme

    /// Apple first (built in, no download), then the rest in rough "try this next" order.
    private static let providerOrder: [SettingsStore.SpeechModel.Provider] = [
        .apple, .nvidia, .openai, .cohere, .qwen,
    ]

    private var models: [SettingsStore.SpeechModel] {
        Self.providerOrder.flatMap { SettingsStore.SpeechModel.models(for: $0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            FluidPageHeader(
                systemImage: "waveform",
                title: TheaterEngineCopy.voiceTitle,
                subtitle: AppLanguage.text("Choose an engine for I speak. Speech languages and downloads are separate from Apple Translation packs.")
            )

            Text(SpokenLanguageResolver.stageEngineSummary(settings: self.viewModel.settings))
                .font(self.theme.typography.bodySmall)
                .foregroundStyle(
                    self.isReady(self.viewModel.settings.selectedSpeechModel)
                        && SpokenLanguageResolver.voiceEngineMismatchMessage(settings: self.viewModel.settings) == nil
                        ? self.theme.palette.secondaryText
                        : self.theme.palette.warning
                )
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("voiceEngine.summary")

            VStack(alignment: .leading, spacing: 14) {
                ForEach(self.models) { model in
                    self.card(for: model)
                }
            }
        }
        .accessibilityIdentifier("voiceEngine.list")
    }

    private func card(for model: SettingsStore.SpeechModel) -> some View {
        ThemedCard(style: .standard, hoverEffect: false) {
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(TheaterEngineCopy.voiceEngineName(model))
                            .font(self.theme.typography.bodyStrong)
                            .foregroundStyle(self.theme.palette.primaryText)
                        self.statusBadge(for: model)
                    }
                    Text(TheaterEngineCopy.voiceEngineDetail(model))
                        .font(self.theme.typography.bodySmall)
                        .foregroundStyle(self.theme.palette.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                self.specsRow(for: model)
                VoiceEngineLanguageSupportView(
                    model: model,
                    source: SpokenLanguageResolver.sourceLanguage(settings: self.viewModel.settings)
                )

                if let warning = model.memoryWarning {
                    Text(warning)
                        .font(self.theme.typography.caption)
                        .foregroundStyle(self.theme.palette.warning)
                        .fixedSize(horizontal: false, vertical: true)
                }

                self.testResult(for: model)

                HStack(spacing: 8) {
                    if model.isInstalled {
                        self.testAction(for: model)
                    }
                    if self.showsUninstall(for: model) {
                        self.uninstallAction(for: model)
                    }
                    Spacer(minLength: 8)
                    self.primaryAction(for: model)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("voiceEngine.\(model.rawValue)")
    }

    private func isReady(_ model: SettingsStore.SpeechModel) -> Bool {
        let source = SpokenLanguageResolver.sourceLanguage(settings: self.viewModel.settings)
        return VoiceEngineLanguageReadiness.current(model: model, languageID: source.id) == .ready
    }

    private func statusBadge(for model: SettingsStore.SpeechModel) -> some View {
        let (text, color) = self.statusInfo(for: model)
        return Text(text)
            .font(self.theme.typography.badge)
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(color.opacity(0.12)))
            .accessibilityIdentifier(
                self.viewModel.isActiveSpeechModel(model) ? "voiceEngine.inUse" : "voiceEngine.status.\(model.rawValue)"
            )
    }

    private func statusInfo(for model: SettingsStore.SpeechModel) -> (String, Color) {
        if self.viewModel.isActiveSpeechModel(model) {
            let source = SpokenLanguageResolver.sourceLanguage(settings: self.viewModel.settings)
            let ready = VoiceEngineLanguageReadiness.current(model: model, languageID: source.id) == .ready
            return (ready ? "Active" : "Selected · needs setup", ready ? self.theme.palette.success : self.theme.palette.warning)
        }
        if !model.isInstalled {
            return ("Not Downloaded", self.theme.palette.secondaryText)
        }
        if model == SettingsStore.SpeechModel.defaultModel {
            return ("Default", self.theme.palette.accent)
        }
        return ("Installed", self.theme.palette.secondaryText)
    }

    private func specsRow(for model: SettingsStore.SpeechModel) -> some View {
        HStack(spacing: 16) {
            self.specItem(icon: "internaldrive", text: model.downloadSize)
            self.specItem(icon: "waveform", text: model.supportsStreaming ? "Live captions" : "Text after Stop")
        }
    }

    private func specItem(icon: String, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundStyle(self.theme.palette.tertiaryText)
            Text(text)
                .font(self.theme.typography.caption)
                .foregroundStyle(self.theme.palette.secondaryText)
        }
    }

    private func showsUninstall(for model: SettingsStore.SpeechModel) -> Bool {
        model.isInstalled && model.downloadSize != "Built-in" && !self.viewModel.isActiveSpeechModel(model)
    }

    private func uninstallAction(for model: SettingsStore.SpeechModel) -> some View {
        AppButton("Uninstall") {
            self.viewModel.deleteSpeechModel(model)
        }
        .buttonStyle(.theaterTextDestructive)
        .disabled(self.viewModel.areSpeechModelActionsBlocked)
        .accessibilityIdentifier("voiceEngine.uninstall.\(model.rawValue)")
    }

    /// Raw mic → ASR result (or the real thrown error) from the last "Test" tap on
    /// this row — stays visible until a new test runs, on this row or another.
    @ViewBuilder
    private func testResult(for model: SettingsStore.SpeechModel) -> some View {
        if self.viewModel.testingModel == model {
            AppText("Listening…")
                .font(self.theme.typography.caption)
                .foregroundStyle(self.theme.palette.secondaryText)
        } else if self.viewModel.lastTestedModel == model, let error = self.viewModel.testErrorText {
            Text(error)
                .font(self.theme.typography.caption)
                .foregroundStyle(self.theme.palette.warning)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("voiceEngine.test.error.\(model.rawValue)")
        } else if self.viewModel.lastTestedModel == model, let text = self.viewModel.testResultText {
            AppText("Test heard: \u{201C}{0}\u{201D}", arguments: [String(describing: text)])
                .font(self.theme.typography.caption)
                .foregroundStyle(self.theme.palette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("voiceEngine.test.result.\(model.rawValue)")
        }
    }

    /// Runs a short, isolated mic → ASR round trip for `model` (see
    /// `VoiceEngineSettingsViewModel.testSpeechModel`) — no Theater session, no
    /// translation, just "does this engine hear this language right now."
    @ViewBuilder
    private func testAction(for model: SettingsStore.SpeechModel) -> some View {
        if self.viewModel.testingModel == model {
            AppButton("Stop test") {
                self.viewModel.cancelSpeechModelTest()
            }
            .buttonStyle(.theaterText)
            .accessibilityIdentifier("voiceEngine.test.stop.\(model.rawValue)")
        } else {
            AppButton("Test") {
                self.viewModel.testSpeechModel(model)
            }
            .buttonStyle(.theaterText)
            .disabled(self.viewModel.testingModel != nil || self.viewModel.areSpeechModelActionsBlocked || !self.isReady(model))
            .accessibilityIdentifier("voiceEngine.test.\(model.rawValue)")
        }
    }

    @ViewBuilder
    private func primaryAction(for model: SettingsStore.SpeechModel) -> some View {
        let blocked = self.viewModel.areSpeechModelActionsBlocked
        let source = SpokenLanguageResolver.sourceLanguage(settings: self.viewModel.settings)
        let readiness = VoiceEngineLanguageReadiness.current(model: model, languageID: source.id)
        if self.viewModel.downloadingModel == model {
            Text(self.viewModel.asr.modelPreparationStatusText)
                .font(self.theme.typography.caption)
                .foregroundStyle(self.theme.palette.secondaryText)
                .lineLimit(2)
        } else if self.viewModel.isActiveSpeechModel(model), model.isInstalled, !self.viewModel.asr.isAsrReady,
           self.viewModel.asr.isLoadingModel || self.viewModel.asr.isDownloadingModel
        {
            Text(self.viewModel.asr.modelPreparationStatusText)
                .font(self.theme.typography.caption)
                .foregroundStyle(self.theme.palette.secondaryText)
                .lineLimit(2)
        } else if readiness == .checking {
            Text(AppLanguage.text("Checking…"))
                .font(self.theme.typography.caption)
                .foregroundStyle(self.theme.palette.secondaryText)
        } else if readiness == .permissionRequired {
            AppButton("Allow Speech Recognition") {
                self.viewModel.requestSpeechLanguageAccess()
            }
            .buttonStyle(.theaterTextProminent)
            .disabled(blocked)
            .accessibilityIdentifier("voiceEngine.allowSpeech")
        } else if readiness == .needsDownload {
            AppButton(model == .appleSpeechAnalyzer ? AppLanguage.text("Download speech language") : AppLanguage.text("Download")) {
                self.viewModel.downloadSpeechModel(model)
            }
            .buttonStyle(.theaterTextProminent)
            .disabled(blocked)
            .accessibilityIdentifier("voiceEngine.download.\(model.rawValue)")
        } else if readiness == .ready, !self.viewModel.isActiveSpeechModel(model) {
            AppButton("Select") {
                self.viewModel.activateSpeechModel(model)
            }
            .buttonStyle(.theaterTextProminent)
            .disabled(blocked)
            .accessibilityIdentifier("voiceEngine.use.\(model.rawValue)")
        }
    }
}

extension Notification.Name {
    static let openCustomDictionaryFromVoiceEngine = Notification.Name("OpenCustomDictionaryFromVoiceEngine")
}
