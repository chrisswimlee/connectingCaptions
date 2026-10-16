import SwiftUI

struct VoiceEngineLanguageSupportView: View {
    let model: SettingsStore.SpeechModel
    let source: TranslationLanguage
    @Environment(\.theme) private var theme

    private var supported: [TranslationLanguage] {
        VoiceEngineLanguageReadiness.supportedLanguages(for: self.model)
    }

    private var ready: [TranslationLanguage] {
        if self.model == .appleSpeechAnalyzer {
            let installed = AppleSpeechLiveCapability.installedAnalyzerLanguagePrefixes ?? []
            return self.supported.filter { installed.contains($0.id) }
        }
        return self.model.isInstalled ? self.supported : []
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            self.languageList(AppLanguage.text("Supported languages"), languages: self.supported)
                .accessibilityIdentifier("voiceEngine.languages.\(self.model.rawValue)")
            self.languageList(AppLanguage.text("Ready on this Mac"), languages: self.ready)
                .accessibilityIdentifier("voiceEngine.readyLanguages.\(self.model.rawValue)")
            let state = VoiceEngineLanguageReadiness.current(model: self.model, languageID: self.source.id)
            Text(state.message(model: self.model, language: self.source))
                .font(self.theme.typography.caption)
                .foregroundStyle(state == .ready ? self.theme.palette.success : self.theme.palette.warning)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("voiceEngine.languageStatus.\(self.model.rawValue)")
        }
    }

    private func languageList(_ title: String, languages: [TranslationLanguage]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            AppText(title)
                .font(self.theme.typography.captionStrong)
            Text(languages.isEmpty ? AppLanguage.text("None confirmed") : languages.map { AppLanguage.localizedName(for: $0) }.joined(separator: ", "))
                .font(self.theme.typography.caption)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(self.theme.palette.secondaryText)
        .accessibilityElement(children: .combine)
    }
}
