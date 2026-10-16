import SwiftUI

struct TheaterLinePrintSettings: View {
    @Environment(\.theme) private var theme
    @ObservedObject private var settings = SettingsStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TheaterSettingRow(
                title: TheaterReadiness.linePrintTitle,
                detail: self.settings.theaterLinePrint.help
            ) {
                TheaterWordPicker(
                    accessibilityLabel: TheaterReadiness.linePrintTitle,
                    accessibilityIdentifier: "theater.home.linePrint",
                    options: Array(TheaterLinePrint.allCases),
                    title: { $0.displayName },
                    selection: Binding(
                        get: { self.settings.theaterLinePrint },
                        set: { self.settings.theaterLinePrint = $0 }
                    )
                )
            }
            TheaterSettingRow(
                title: TheaterReadiness.printGapTitle,
                detail: AppLanguage.text("The pause between each word or letter. Fade uses this as how long the line takes to arrive.")
            ) {
                TheaterWordPicker(
                    accessibilityLabel: TheaterReadiness.printGapTitle,
                    accessibilityIdentifier: "theater.home.printGap",
                    options: Array(TheaterPrintGap.allCases),
                    title: { $0.displayName },
                    selection: Binding(
                        get: { self.settings.theaterPrintGap },
                        set: { self.settings.theaterPrintGap = $0 }
                    )
                )
                .disabled(self.settings.theaterLinePrint == .atOnce)
                .opacity(self.settings.theaterLinePrint == .atOnce ? 0.45 : 1)
            }
            TheaterSettingRow(
                title: AppLanguage.text("Save transcript"),
                detail: TheaterReadiness.autoExportSession
            ) {
                AppToggle("Save transcript", isOn: self.$settings.theaterAutoExportSession)
                    .toggleStyle(.switch)
                    .tint(self.theme.palette.accent)
                    .labelsHidden()
                    .accessibilityLabel(AppLanguage.text("Save transcript"))
                    .accessibilityIdentifier("theater.home.autoExport")
            }
        }
    }
}
