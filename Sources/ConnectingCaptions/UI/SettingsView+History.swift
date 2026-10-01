import SwiftUI

extension SettingsView {
    /// History stays advertised under Data & Diagnostics. Dictation leftovers do not.
    var historySettingsCard: some View {
        ThemedCard(style: .standard) {
            VStack(alignment: .leading, spacing: 14) {
                FluidSectionHeader(title: "History", systemImage: "clock.arrow.circlepath")

                VStack(spacing: 12) {
                    self.optionToggleRow(
                        title: "Save Transcription History",
                        description: "Save transcriptions for stats tracking. Disable for privacy.",
                        isOn: Binding(
                            get: { SettingsStore.shared.saveTranscriptionHistory },
                            set: {
                                SettingsStore.shared.saveTranscriptionHistory = $0
                                self.refreshAudioHistoryUsage()
                            }
                        )
                    )
                    .settingsSearchTarget(.transcriptionHistory)

                    if SettingsStore.shared.saveTranscriptionHistory {
                        self.historyRetentionControls()
                            .padding(.top, 2)
                            .settingsSearchTarget(.historyRetention)
                    }
                    Divider().opacity(0.2)

                    self.optionToggleRow(
                        title: "Save Audio With History",
                        description: "Store actual microphone audio locally with dictation history. Disabled by default.",
                        isOn: Binding(
                            get: { SettingsStore.shared.saveAudioWithTranscriptionHistory },
                            set: {
                                SettingsStore.shared.saveAudioWithTranscriptionHistory = $0
                                self.refreshAudioHistoryUsage()
                            }
                        )
                    )
                    .disabled(!SettingsStore.shared.saveTranscriptionHistory)
                    .settingsSearchTarget(.audioHistory)

                    if SettingsStore.shared.saveTranscriptionHistory,
                       SettingsStore.shared.saveAudioWithTranscriptionHistory
                    {
                        self.audioHistoryControls()
                            .padding(.top, 2)
                            .settingsSearchTarget(.audioStorage)
                    }
                }
            }
            .padding(16)
        }
    }
}
