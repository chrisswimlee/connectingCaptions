import SwiftUI

/// Uses the existing capture meter; visiting this screen never opens the mic.
struct TheaterMicrophoneStatus: View {
    @Environment(\.theme) private var theme
    @ObservedObject private var settings = SettingsStore.shared
    @ObservedObject private var asr = AppServices.shared.asr
    @ObservedObject private var hardware = AppServices.shared.audioObserver
    @ObservedObject private var microphones = AppServices.shared.microphonePreferenceCoordinator
    @State private var inputName = "Checking microphone…"
    @State private var level: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TheaterSettingRow(title: AppLanguage.text("Microphone"), detail: self.inputName) {
                AppButton("Choose microphone") {
                    AppNavigationRouter.shared.request(.audioSettings)
                }
                .buttonStyle(.theaterText)
            }
            ProgressView(value: self.asr.isRunning ? Double(self.level) : 0, total: 1)
                .tint(self.theme.palette.accent)
                .accessibilityLabel(AppLanguage.text("Microphone input level"))
                .accessibilityValue(self.asr.isRunning ? "\(Int(self.level * 100)) percent" : "Not listening")
            Text(self.asr.isRunning ? "Input level while listening" : "Press Listen to check the input level.")
                .font(self.theme.typography.caption)
                .foregroundStyle(self.theme.palette.secondaryText)
        }
        .accessibilityIdentifier("theater.microphone")
        .task(id: self.inputRevision) {
            await AudioStartupGate.shared.scheduleOpenAfterInitialUISettled()
            await AudioStartupGate.shared.waitUntilOpen()
            guard !Task.isCancelled else { return }
            let snapshot = await Task.detached(priority: .utility) {
                (AudioDevice.listInputDevices(), AudioDevice.getDefaultInputDevice()?.uid)
            }.value
            guard !Task.isCancelled else { return }
            let selected = self.microphones.confirmedActiveInputUID.flatMap { uid in
                snapshot.0.first { $0.uid == uid }
            } ?? self.microphones.inputDeviceForCapture(availableInputs: snapshot.0, defaultInputUID: snapshot.1)
            self.inputName = selected?.name ?? "No microphone connected. Choose an input in Audio settings."
        }
        .onReceive(self.asr.audioLevelPublisher) { value in
            self.level = min(1, max(0, value))
        }
    }

    private var inputRevision: String {
        "\(self.hardware.changeTick):\(self.hardware.inputAvailabilityTick):\(self.microphones.confirmedActiveInputUID ?? ""):\(self.settings.preferredInputDeviceUID ?? ""):\(self.settings.microphonePriority.map(\.uid).joined(separator: ","))"
    }
}
