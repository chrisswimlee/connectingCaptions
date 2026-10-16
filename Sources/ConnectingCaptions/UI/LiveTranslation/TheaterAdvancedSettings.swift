import SwiftUI

struct TheaterAdvancedSettings: View {
    @Environment(\.theme) private var theme
    @ObservedObject private var settings = SettingsStore.shared
    @ObservedObject private var controller = LiveTranslationController.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if SpokenLanguageResolver.showsEitherWayControl() {
                TheaterSharedSettingsNotice()
                TheaterEitherWaySection(accessibilityIdentifier: "theater.home.eitherWay")
            }
            TheaterLinePrintSettings()
            TheaterSettingRow(title: AppLanguage.text("Presenter shortcuts"), detail: TheaterReadiness.presenterHotkeys) {
                AppToggle("Presenter shortcuts", isOn: self.$settings.theaterPresenterHotkeysEnabled)
                    .toggleStyle(.switch)
                    .tint(self.theme.palette.accent)
                    .labelsHidden()
                    .accessibilityLabel(AppLanguage.text("Presenter shortcuts"))
                    .accessibilityIdentifier("theater.settings.presenterHotkeys")
            }
        }
    }
}

struct TheaterSharedSettingsNotice: View {
    @Environment(\.theme) private var theme
    @ObservedObject private var controller = LiveTranslationController.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            AppText("Mode and languages are shared with Theater and Speak & Type.")
                .foregroundStyle(self.theme.palette.secondaryText)
            if self.controller.isSessionActive {
                AppLabel("Changing mode, languages, or Either way will stop the current Listen.", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(self.theme.palette.warning)
                    .accessibilityIdentifier("theater.sharedSettings.stopWarning")
            }
        }
        .font(self.theme.typography.caption)
        .fixedSize(horizontal: false, vertical: true)
    }
}
