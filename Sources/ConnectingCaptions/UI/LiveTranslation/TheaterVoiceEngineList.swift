import SwiftUI

/// Voice Engine picker. The two Apple Speech versions on this Mac.
struct TheaterVoiceEngineList: View {
    @ObservedObject var viewModel: VoiceEngineSettingsViewModel
    @Environment(\.theme) private var theme

    private var appleModels: [SettingsStore.SpeechModel] {
        SettingsStore.SpeechModel.availableModels.filter { $0.provider == .apple }
    }

    var body: some View {
        ThemedCard(style: .standard, hoverEffect: false) {
            VStack(alignment: .leading, spacing: 18) {
                FluidPageHeader(
                    systemImage: "waveform",
                    title: TheaterEngineCopy.voiceTitle,
                    subtitle: "Apple Speech Analyzer is newer. The older Apple Speech hears more languages already on this Mac."
                )

                Text(SpokenLanguageResolver.stageEngineSummary(settings: self.viewModel.settings))
                    .font(self.theme.typography.bodySmall)
                    .foregroundStyle(
                        SpokenLanguageResolver.voiceEngineMismatchMessage(settings: self.viewModel.settings) == nil
                            ? self.theme.palette.secondaryText
                            : self.theme.palette.warning
                    )
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("voiceEngine.summary")

                VStack(alignment: .leading, spacing: 8) {
                    ForEach(self.appleModels) { model in
                        self.row(model)
                    }
                }
            }
        }
        .accessibilityIdentifier("voiceEngine.list")
    }

    private func row(_ model: SettingsStore.SpeechModel) -> some View {
        TheaterSideBySide(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(TheaterEngineCopy.voiceEngineName(model))
                    .font(self.theme.typography.bodyStrong)
                    .foregroundStyle(self.theme.palette.primaryText)
                Text(TheaterEngineCopy.voiceEngineDetail(model))
                    .font(self.theme.typography.bodySmall)
                    .foregroundStyle(self.theme.palette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } trailing: {
            self.actions(for: model)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("voiceEngine.\(model.rawValue)")
    }

    @ViewBuilder
    private func actions(for model: SettingsStore.SpeechModel) -> some View {
        let blocked = self.viewModel.areSpeechModelActionsBlocked
        if self.viewModel.isActiveSpeechModel(model), model.isInstalled, !self.viewModel.asr.isAsrReady,
           self.viewModel.asr.isLoadingModel || self.viewModel.asr.isDownloadingModel
        {
            Text(self.viewModel.asr.modelPreparationStatusText)
                .font(self.theme.typography.caption)
                .foregroundStyle(self.theme.palette.secondaryText)
                .lineLimit(2)
        } else if self.viewModel.isActiveSpeechModel(model) {
            Text("In use")
                .font(self.theme.typography.captionStrong)
                .foregroundStyle(self.theme.palette.accent)
                .accessibilityIdentifier("voiceEngine.inUse")
        } else {
            Button("Use") {
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
