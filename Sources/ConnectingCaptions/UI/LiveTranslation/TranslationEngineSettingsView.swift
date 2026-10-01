import SwiftUI

/// Setup tab for Translation Engine. Apple Translation is the caption engine.
struct TranslationEngineSettingsScreen: View {
    let theme: AppTheme

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                TranslationEngineSettingsView(theme: self.theme)
                    .fluidPageContent()
                    .id(Self.pageTopID)
            }
            .defaultScrollAnchor(.top)
            .onAppear {
                proxy.scrollTo(Self.pageTopID, anchor: .top)
            }
        }
    }

    private static let pageTopID = "translation-engine-page-top"
}

struct TranslationEngineSettingsView: View {
    let theme: AppTheme
    @ObservedObject private var settings = SettingsStore.shared
    @ObservedObject private var controller = LiveTranslationController.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            FluidPageHeader(
                systemImage: "translate",
                title: TheaterEngineCopy.translationTitle,
                subtitle: TheaterEngineCopy.translationPurpose
            )

            ThemedCard(style: .standard, hoverEffect: false) {
                VStack(alignment: .leading, spacing: 8) {
                    FluidSectionHeader(title: "Apple Translation", systemImage: "translate")
                    Text(self.appleStatusLine)
                        .font(self.theme.typography.bodySmall)
                        .foregroundStyle(self.appleStatusIsWarning ? self.theme.palette.warning : self.theme.palette.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .accessibilityIdentifier("translationEngine.setup")
        .task {
            await self.controller.refreshPackAvailability()
        }
    }

    private var appleStatusLine: String {
        TheaterEngineCopy.translationRunningLine(
            mode: self.settings.theaterSessionMode,
            sameLanguage: SpokenLanguageResolver.isSameLanguagePair(),
            pack: self.controller.packAvailability,
            engine: .apple
        )
    }

    private var appleStatusIsWarning: Bool {
        guard self.settings.theaterSessionMode == .translation,
              !SpokenLanguageResolver.isSameLanguagePair()
        else { return false }
        switch self.controller.packAvailability {
        case .supported, .unsupported, .unknown:
            return true
        case .installed:
            return false
        }
    }
}
