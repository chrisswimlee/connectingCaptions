import SwiftUI

/// Speak and type. Its own section, separate from Theater captions.
struct SpeakAndTypeView: View {
    var showsPageHeader = true
    var tracksSearch = false
    var recordShortcut: (() -> Void)?
    var isRecordingShortcut = false
    var shortcutRecordingMessage: String?
    var accessibilityTrusted = true
    var openAccessibility: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if self.showsPageHeader {
                FluidPageHeader(
                    systemImage: "text.cursor",
                    title: "Speak and type",
                    subtitle: TheaterReadiness.speakAndTypeSubtitle
                )
            }

            ThemedCard(style: .standard, hoverEffect: false) {
                TheaterModeSection(
                    accessibilityIdentifier: "speakAndType.mode",
                    title: "What gets typed"
                )
            }

            TranslationLanguagePairCard()

            self.shortcutCard
        }
        .accessibilityIdentifier("speakAndType.home")
    }

    @ViewBuilder
    private var shortcutCard: some View {
        let card = TranslateInsertShortcutCard(
            recordTranslateShortcut: self.recordShortcut,
            isRecordingTranslateShortcut: self.isRecordingShortcut,
            shortcutRecordingMessage: self.shortcutRecordingMessage,
            accessibilityTrusted: self.accessibilityTrusted,
            openAccessibility: self.openAccessibility
        )
        if self.tracksSearch {
            card.settingsSearchTarget(.translateInsertShortcut)
        } else {
            card
        }
    }
}

extension SettingsView {
    var settingsSectionSubtitle: String? {
        switch self.selectedSection {
        case .translation:
            return FluidProduct.tagline
        case .speakAndType:
            return TheaterReadiness.speakAndTypeSubtitle
        default:
            return nil
        }
    }

    var speakAndTypeSettings: some View {
        SpeakAndTypeView(
            showsPageHeader: false,
            tracksSearch: true,
            recordShortcut: { self.toggleSpeakAndTypeRecording() },
            isRecordingShortcut: self.isRecording(.translateInsert),
            shortcutRecordingMessage: self.isRecording(.translateInsert) ? self.shortcutRecordingMessage : nil,
            accessibilityTrusted: self.accessibilityEnabled,
            openAccessibility: self.openAccessibilitySettings
        )
    }

    func toggleSpeakAndTypeRecording() {
        self.shortcutRecordingMessage = nil
        if self.isRecording(.translateInsert) {
            self.activeShortcutRecordingTarget = nil
        } else {
            self.activeShortcutRecordingTarget = .translateInsert
        }
    }
}
