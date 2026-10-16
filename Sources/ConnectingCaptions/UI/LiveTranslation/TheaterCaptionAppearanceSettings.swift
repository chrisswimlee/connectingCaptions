import SwiftUI

struct TheaterCaptionAppearanceSettings: View {
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var settings = SettingsStore.shared

    var body: some View {
        ThemedCard(style: .standard, hoverEffect: false) {
            VStack(alignment: .leading, spacing: 14) {
                FluidSectionHeader(title: AppLanguage.text("Caption appearance"), systemImage: "textformat.size")

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        AppText("Window style")
                            .font(self.theme.typography.bodyStrong)
                            .foregroundStyle(self.settingsTitleText)
                        AppText(TheaterReadiness.presentationStyle)
                            .font(self.theme.typography.bodySmall)
                            .foregroundStyle(self.settingsSecondaryText)
                    }
                    Spacer()
                    TheaterWordPicker(
                        accessibilityLabel: "Theater board",
                        accessibilityIdentifier: "theater.settings.presentationStyle",
                        options: Array(TheaterPresentationStyle.allCases),
                        title: { $0.displayName },
                        selection: Binding(
                            get: { self.settings.theaterPresentation },
                            set: { self.settings.theaterPresentationStyle = $0.rawValue }
                        )
                    )
                    .help(self.settings.theaterPresentation.help)
                }

                if self.settings.theaterSessionMode == .translation {
                    TheaterSpokenLineSection(accessibilityIdentifier: "theater.settings.spokenLine")
                    AppText(TheaterReadiness.spokenLineSetupNote)
                        .font(self.theme.typography.bodySmall)
                        .foregroundStyle(self.settingsSecondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("theater.settings.spokenLineNote")
                }

                self.settingsToggleRow(
                    title: AppLanguage.text("Captions only"),
                    description: self.settings.theaterPresentation == .transparent
                        ? TheaterReadiness.captionsOnlyPopupOnly
                        : TheaterReadiness.captionsOnlyWindow
                ) {
                    AppToggle("Captions only", isOn: self.$settings.theaterHideChrome)
                        .toggleStyle(.switch)
                        .tint(self.theme.palette.accent)
                        .labelsHidden()
                        .disabled(self.settings.theaterPresentation == .transparent)
                        .accessibilityLabel(AppLanguage.text("Captions only"))
                }

                self.settingsToggleRow(
                    title: AppLanguage.text("Caption plate"),
                    description: TheaterReadiness.backingBar
                ) {
                    AppToggle("Caption plate", isOn: self.$settings.theaterBackingBar)
                        .toggleStyle(.switch)
                        .tint(self.theme.palette.accent)
                        .labelsHidden()
                        .disabled(self.settings.theaterPresentation != .transparent)
                        .accessibilityLabel(AppLanguage.text("Caption plate"))
                        .accessibilityIdentifier("theater.settings.backingBar")
                }

                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(TheaterSetupWizard.accentTitle)
                            .font(self.theme.typography.bodyStrong)
                            .foregroundStyle(self.settingsTitleText)
                        Text(TheaterSetupWizard.accentDetail)
                            .font(self.theme.typography.bodySmall)
                            .foregroundStyle(self.settingsSecondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 12)
                    AccentColorSwatches(accessibilityIdentifier: "theater.settings.accentColor")
                }

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        AppText("Theme")
                            .font(self.theme.typography.bodyStrong)
                            .foregroundStyle(self.settingsTitleText)
                        AppText("Choose Dark or Light for Theater. This does not change the main window.")
                            .font(self.theme.typography.bodySmall)
                            .foregroundStyle(self.settingsSecondaryText)
                    }
                    Spacer()
                    TheaterWordPicker(
                        accessibilityLabel: "Theater theme",
                        options: Array(TheaterAppearance.allCases),
                        title: { $0.displayName },
                        selection: Binding(
                            get: { TheaterAppearance.resolved(self.settings.theaterAppearance) },
                            set: { self.settings.theaterAppearance = $0.rawValue }
                        )
                    )
                }

                self.settingsToggleRow(
                    title: AppLanguage.text("High contrast"),
                    description: AppLanguage.text("Stronger background and a stroke on caption text.")
                ) {
                    AppToggle("High contrast", isOn: self.$settings.theaterHighContrast)
                        .toggleStyle(.switch)
                        .tint(self.theme.palette.accent)
                        .labelsHidden()
                        .accessibilityLabel(AppLanguage.text("High contrast"))
                }

                Divider().opacity(0.2)

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        AppText("Caption Font")
                            .font(self.theme.typography.bodyStrong)
                            .foregroundStyle(self.settingsTitleText)
                        AppText("Typeface used for Theater captions")
                            .font(self.theme.typography.bodySmall)
                            .foregroundStyle(self.settingsSecondaryText)
                    }
                    Spacer()
                    Picker(AppLanguage.text("Caption font"), selection: Binding(
                        get: { TheaterTypeface.resolved(self.settings.presenterFontFamily) },
                        set: { self.settings.presenterFontFamily = $0.rawValue }
                    )) {
                        ForEach(TheaterTypeface.allCases) { face in
                            AppText(face.displayName).tag(face)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 170, alignment: .trailing)
                }

                Divider().opacity(0.2)

                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            AppText("Caption Size")
                                .font(self.theme.typography.bodyStrong)
                                .foregroundStyle(self.settingsTitleText)
                            Text(
                                self.settings.theaterSessionMode == .translation
                                    ? TheaterReadiness.captionSizeSpoken
                                    : TheaterReadiness.captionSize
                            )
                            .font(self.theme.typography.bodySmall)
                            .foregroundStyle(self.settingsSecondaryText)
                        }
                        Spacer()
                        TheaterPointField(
                            label: "Caption size",
                            range: SettingsStore.presenterFontSizeRange,
                            value: Binding(
                                get: { self.settings.presenterFontSize },
                                set: { self.settings.presenterFontSize = $0 }
                            ),
                            accessibilityIdentifier: "theater.settings.captionSize"
                        )
                        AppText("pt")
                            .font(self.theme.typography.bodySmall)
                            .foregroundStyle(self.settingsSecondaryText)
                    }

                    Slider(
                        value: Binding(
                            get: { Double(self.settings.presenterFontSize) },
                            set: { self.settings.presenterFontSize = Int($0.rounded()) }
                        ),
                        in: Double(SettingsStore.presenterFontSizeRange.lowerBound)...Double(SettingsStore.presenterFontSizeRange.upperBound),
                        step: 2
                    )
                    .controlSize(.regular)

                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            AppText("Spacing")
                                .font(self.theme.typography.bodyStrong)
                                .foregroundStyle(self.settingsTitleText)
                            AppText("Points between caption lines.")
                                .font(self.theme.typography.bodySmall)
                                .foregroundStyle(self.settingsSecondaryText)
                        }
                        Spacer()
                        TheaterPointField(
                            label: "Spacing",
                            range: TheaterCaptionSpacing.range,
                            value: self.$settings.theaterCaptionSpacing,
                            accessibilityIdentifier: "theater.settings.captionSpacing"
                        )
                        AppText("pt")
                            .font(self.theme.typography.bodySmall)
                            .foregroundStyle(self.settingsSecondaryText)
                    }
                }
            }
        }
    }

    private func settingsToggleRow<Accessory: View>(
        title: String,
        description: String,
        @ViewBuilder accessory: @escaping () -> Accessory
    ) -> some View {
        TheaterSettingRow(title: title, detail: description, control: accessory)
    }

    private var settingsTitleText: Color {
        Color(nsColor: .labelColor)
    }

    private var settingsSecondaryText: Color {
        self.colorScheme == .light ? Color(nsColor: .labelColor).opacity(0.90) : self.theme.palette.primaryText.opacity(0.82)
    }
}
