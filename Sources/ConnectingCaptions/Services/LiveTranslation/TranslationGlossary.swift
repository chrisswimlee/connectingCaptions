import Foundation

/// Protects custom-dictionary terms so Apple Translation does not rewrite names.
enum TranslationGlossary {
    typealias ProtectedText = TranslationGlossaryLock.ProtectedText

    static func protectedTerms(from settings: SettingsStore = .shared) -> [String] {
        var terms: [String] = []
        for entry in settings.customDictionaryEntries {
            terms.append(contentsOf: entry.triggers)
            if !entry.replacement.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                terms.append(entry.replacement)
            }
        }
        terms.append(contentsOf: TheaterTalkPack.sanitizedTerms(settings.theaterTalkPackTerms))
        return Array(Set(terms.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }))
            .filter { $0.count >= 2 }
            .sorted { $0.count > $1.count }
    }

    static func protect(_ text: String, terms: [String]) -> ProtectedText {
        TranslationGlossaryLock.protect(text, terms: terms)
    }

    static func restore(_ text: String, tokens: [String: String]) -> String {
        TranslationGlossaryLock.restore(text, tokens: tokens)
    }

    /// Terms that appear in the source but vanished from a polished caption.
    static func lostProtectedTerms(source: String, polished: String, terms: [String]) -> [String] {
        TranslationGlossaryLock.lostProtectedTerms(source: source, polished: polished, terms: terms)
    }

    static func containsTerm(_ term: String, in text: String) -> Bool {
        TranslationGlossaryLock.containsTerm(term, in: text)
    }
}

enum SpokenLanguageResolver {
    /// Latest Whisper language for this Listen. Nil when the model did not name one.
    private(set) static var detectedLanguageID: String?

    static func noteDetectedLanguage(_ code: String?) {
        guard let code else {
            self.detectedLanguageID = nil
            return
        }
        self.detectedLanguageID = TranslationLanguageCatalog.language(id: code)?.id
    }

    static func spokenLanguageID(settings: SettingsStore = .shared) -> String {
        if let heard = self.heardLanguage(settings: settings) {
            return heard.id
        }
        return self.rawSpokenLanguageID(settings: settings)
    }

    /// What the Voice Engine is actually set to hear, mapped onto the setup list.
    /// `en-US` and `en` are the same language.
    static func heardLanguage(settings: SettingsStore = .shared) -> TranslationLanguage? {
        TranslationLanguageCatalog.language(id: self.rawSpokenLanguageID(settings: settings))
    }

    static func rawSpokenLanguageID(settings: SettingsStore = .shared) -> String {
        let model = settings.selectedSpeechModel
        switch model {
        case .parakeetRealtime, .parakeetTDTv2:
            return "en"
        case .whisperTiny, .whisperBase, .whisperSmall, .whisperMedium, .whisperLargeTurbo, .whisperLarge:
            if let code = settings.selectedWhisperLanguageCode, !code.isEmpty {
                return code
            }
        case .cohereTranscribeSixBit:
            return settings.selectedCohereLanguage.rawValue
        case .nemotronOffline, .nemotronStreaming, .nemotronStreaming320:
            let raw = settings.selectedNemotronLanguage.rawValue
            if raw == "auto" {
                break
            }
            return raw
        case .appleSpeech, .appleSpeechAnalyzer:
            return settings.selectedAppleSpeechLocaleIdentifier
        default:
            break
        }
        return settings.onboardingSelectedLanguageID
    }

    static func sourceLanguage(settings: SettingsStore = .shared) -> TranslationLanguage {
        if let stored = TranslationLanguageCatalog.language(id: settings.translationSourceLanguageID) {
            return stored
        }
        return self.heardLanguage(settings: settings) ?? TranslationLanguageCatalog.english
    }

    static func voiceEngineSupportsSource(settings: SettingsStore = .shared) -> Bool {
        let source = self.sourceLanguage(settings: settings)
        let model = settings.selectedSpeechModel
        guard VoiceEngineLanguageCatalog.supports(model, languageID: source.id) else {
            return false
        }
        if self.heardLanguage(settings: settings)?.id == source.id {
            return true
        }
        if model.isWhisperModel, self.shouldAutoDetectWhisper(settings: settings) {
            return true
        }
        return false
    }

    static func voiceEngineMismatchMessage(settings: SettingsStore = .shared) -> String? {
        let source = self.sourceLanguage(settings: settings)
        let spoken = self.heardLanguage(settings: settings)
        if source.id == TranslationLanguageCatalog.thai.id,
           self.shouldWarnThaiNemotron(settings: settings, spoken: spoken)
        {
            return TranslationLanguageCatalog.thaiNemotronExperimentalWarning
        }

        if spoken?.id == source.id
            || spoken?.displayName == source.displayName
        {
            if VoiceEngineLanguageCatalog.supports(settings.selectedSpeechModel, languageID: source.id) {
                return nil
            }
            return "\(settings.selectedSpeechModel.displayName) does not hear \(source.displayName). Choose a Voice Engine that lists this language as supported."
        }

        guard !self.voiceEngineSupportsSource(settings: settings) else { return nil }

        if source.id == TranslationLanguageCatalog.korean.id
            || source.id == TranslationLanguageCatalog.japanese.id
        {
            return self.verbFinalMismatchMessage(
                language: source,
                model: settings.selectedSpeechModel,
                spoken: spoken
            )
        }

        switch settings.selectedSpeechModel {
        case .parakeetRealtime, .parakeetTDTv2:
            return "Parakeet Flash and TDT v2 only hear English. Switch Voice Engine to Apple Speech or Whisper for \(source.displayName)."
        case .parakeetTDT:
            return "Parakeet TDT v3 only hears English. Switch Voice Engine to Apple Speech or Whisper for \(source.displayName)."
        default:
            if source.id == TranslationLanguageCatalog.thai.id {
                let heard = spoken?.displayName ?? "another language"
                return "The current Voice Engine is set to hear \(heard), not Thai. Apple Speech or Whisper is the better Theater default."
            }
            let heard = spoken?.displayName ?? "another language"
            return "The current Voice Engine is set to hear \(heard), not \(source.displayName)."
        }
    }

    /// Caption under Theater pickers. Hidden when a mismatch is already showing.
    static func theaterEngineHint(settings: SettingsStore = .shared) -> String? {
        guard self.voiceEngineMismatchMessage(settings: settings) == nil else { return nil }
        if self.isDynamicPairingEnabled(settings: settings) {
            return TheaterReadiness.dynamicPairingHint(isWhisper: settings.selectedSpeechModel.isWhisperModel)
        }
        return TranslationLanguageCatalog.theaterEngineHint(forSource: self.sourceLanguage(settings: settings))
    }

    static func stageEngineSummary(settings: SettingsStore = .shared) -> String {
        let source = self.sourceLanguage(settings: settings)
        let selected = settings.selectedSpeechModel
        if let mismatch = self.voiceEngineMismatchMessage(settings: settings) {
            return mismatch
        }
        let readiness = VoiceEngineLanguageReadiness.current(model: selected, languageID: source.id)
        if readiness != .ready { return readiness.message(model: selected, language: source) }
        let model = settings.selectedSpeechModel.displayName
        return "Hearing \(source.displayName) with \(model)."
    }

    private static func isNemotronModel(_ model: SettingsStore.SpeechModel) -> Bool {
        switch model {
        case .nemotronOffline, .nemotronStreaming, .nemotronStreaming320:
            return true
        default:
            return false
        }
    }

    private static func shouldWarnThaiNemotron(
        settings: SettingsStore,
        spoken: TranslationLanguage?
    ) -> Bool {
        guard self.isNemotronModel(settings.selectedSpeechModel) else { return false }
        let language = settings.selectedNemotronLanguage
        let isExperimentalThai = language.rawValue.caseInsensitiveCompare("th-TH") == .orderedSame
            || language.displayName.localizedCaseInsensitiveContains("experimental")
        let spokenIsNotThai = spoken?.id != TranslationLanguageCatalog.thai.id
        return isExperimentalThai || spokenIsNotThai
    }

    private static func verbFinalMismatchMessage(
        language: TranslationLanguage,
        model: SettingsStore.SpeechModel,
        spoken: TranslationLanguage?
    ) -> String {
        switch model {
        case .parakeetRealtime, .parakeetTDTv2:
            return "Parakeet Flash and TDT v2 only hear English. Switch to Apple Speech, Cohere, or Whisper for \(language.displayName)."
        case .parakeetTDT:
            return "Parakeet TDT v3 does not hear \(language.displayName). Switch to Apple Speech, Cohere, or Whisper."
        default:
            let heard = spoken?.displayName ?? "English"
            return "The current Voice Engine is set to hear \(heard), not \(language.displayName). Switch to Apple Speech, Cohere, or Whisper."
        }
    }

    static func targetLanguage(settings: SettingsStore = .shared) -> TranslationLanguage {
        TranslationLanguageCatalog.language(id: settings.translationTargetLanguageID)
            ?? TranslationLanguageCatalog.defaultTarget(forSource: self.sourceLanguage(settings: settings))
    }

    static func setSourceLanguage(_ language: TranslationLanguage, settings: SettingsStore = .shared) {
        if settings.translationSourceLanguageID != language.id {
            settings.translationSourceLanguageID = language.id
        }
        if settings.onboardingSelectedLanguageID != language.id {
            settings.onboardingSelectedLanguageID = language.id
        }
        Self.pinSpokenEngineToSource(settings: settings)
    }

    static func pinSpokenEngineToSource(settings: SettingsStore = .shared) {
        Self.pinWhisperToSpokenSource(settings: settings)
        Self.pinAppleSpeechToSpokenSource(settings: settings)
        Self.pinCohereToSpokenSource(settings: settings)
        Self.pinNemotronToSpokenSource(settings: settings)
    }

    /// Pins every Voice Engine language binding to I speak. Returns true when
    /// the selected engine's listening language changed and ASR must reload.
    @discardableResult
    static func syncSpokenEngineToTheater(settings: SettingsStore = .shared) -> Bool {
        let before = self.selectedEngineLanguageKey(settings: settings)
        self.pinSpokenEngineToSource(settings: settings)
        return before != self.selectedEngineLanguageKey(settings: settings)
    }

    static func selectedEngineLanguageKey(settings: SettingsStore = .shared) -> String {
        switch settings.selectedSpeechModel {
        case .whisperTiny, .whisperBase, .whisperSmall, .whisperMedium, .whisperLargeTurbo, .whisperLarge:
            return "whisper:\(settings.selectedWhisperLanguageCode ?? "auto")"
        case .appleSpeech, .appleSpeechAnalyzer:
            return "\(settings.selectedSpeechModel.rawValue):\(settings.selectedAppleSpeechLocaleIdentifier)"
        case .cohereTranscribeSixBit:
            return "cohere:\(settings.selectedCohereLanguage.rawValue)"
        case .nemotronOffline, .nemotronStreaming, .nemotronStreaming320:
            return "nemotron:\(settings.selectedNemotronLanguage.rawValue)"
        default:
            return settings.selectedSpeechModel.rawValue
        }
    }

    /// Theater Listen refuses Whisper automatic detection unless Q&A extras
    /// or Either way are on. Auto-detect can name the language of this clause.
    static func pinWhisperToSpokenSource(settings: SettingsStore = .shared) {
        if self.shouldAutoDetectWhisper(settings: settings) { return }
        let sourceID = self.sourceLanguage(settings: settings).id
        guard let code = VoiceEngineLanguageCatalog.whisperLanguageCode(for: sourceID) else { return }
        if settings.selectedWhisperLanguageCode != code {
            settings.selectedWhisperLanguageCode = code
        }
    }

    /// Pins Apple Speech to I speak. Speech Analyzer locales stay on the languages
    /// that engine includes; every other product language uses Apple Speech's locale.
    static func pinAppleSpeechToSpokenSource(settings: SettingsStore = .shared) {
        let sourceID = self.sourceLanguage(settings: settings).id
        let locale = VoiceEngineLanguageCatalog.preferredAppleSpeechAnalyzerLocale(forLanguageID: sourceID)
        if settings.selectedAppleSpeechLocaleIdentifier != locale {
            settings.selectedAppleSpeechLocaleIdentifier = locale
        }
    }

    static func pinCohereToSpokenSource(settings: SettingsStore = .shared) {
        let sourceID = self.sourceLanguage(settings: settings).id
        guard let language = VoiceEngineLanguageCatalog.cohereLanguage(forLanguageID: sourceID) else { return }
        if settings.selectedCohereLanguage != language {
            settings.selectedCohereLanguage = language
        }
    }

    static func pinNemotronToSpokenSource(settings: SettingsStore = .shared) {
        let sourceID = self.sourceLanguage(settings: settings).id
        guard let language = VoiceEngineLanguageCatalog.nemotronLanguage(forLanguageID: sourceID) else { return }
        if settings.selectedNemotronLanguage != language {
            settings.selectedNemotronLanguage = language
        }
    }

    static func isSameLanguagePair(settings: SettingsStore = .shared) -> Bool {
        if settings.theaterSessionMode == .transcription { return true }
        return self.sourceLanguage(settings: settings).id == self.targetLanguage(settings: settings).id
    }

    static func pairLabel(settings: SettingsStore = .shared) -> String {
        let source = self.sourceLanguage(settings: settings)
        let target = self.targetLanguage(settings: settings)
        if source.id == target.id {
            return "\(source.displayName) captions"
        }
        if self.isDynamicPairingEnabled(settings: settings) {
            return "\(source.displayName) ↔ \(target.displayName)"
        }
        return "\(source.displayName) → \(target.displayName)"
    }

    static func shouldAutoDetectWhisper(settings: SettingsStore = .shared) -> Bool {
        settings.theaterAlsoHearOtherLanguages || self.isDynamicPairingEnabled(settings: settings)
    }

    /// Either way is on only when this Voice Engine can hear both sides.
    /// Whisper can. Apple Speech stays on I speak. Parakeet stays English-only.
    static func dynamicPairingAvailable(settings: SettingsStore = .shared) -> Bool {
        guard settings.theaterSessionMode == .translation else { return false }
        let source = self.sourceLanguage(settings: settings)
        let target = self.targetLanguage(settings: settings)
        guard source.id != target.id else { return false }
        let model = settings.selectedSpeechModel
        guard model.isWhisperModel else { return false }
        return VoiceEngineLanguageCatalog.supports(model, languageID: source.id)
            && VoiceEngineLanguageCatalog.supports(model, languageID: target.id)
    }

    /// Whether turning Either way on would actually hear both sides of this
    /// pair, judged by what the add-on (Whisper Small) supports — not by
    /// whichever Voice Engine happens to be selected right now. `applyDynamicPairing`
    /// switches to the add-on the moment the toggle flips, so this is the check
    /// that should gate whether the toggle is tappable in the first place.
    static func dynamicPairingSupportsCurrentPair(settings: SettingsStore = .shared) -> Bool {
        guard settings.theaterSessionMode == .translation else { return false }
        let source = self.sourceLanguage(settings: settings)
        let target = self.targetLanguage(settings: settings)
        guard source.id != target.id else { return false }
        let addOn = SettingsStore.SpeechModel.eitherWayAddOn
        return VoiceEngineLanguageCatalog.supports(addOn, languageID: source.id)
            && VoiceEngineLanguageCatalog.supports(addOn, languageID: target.id)
    }

    static func isDynamicPairingEnabled(settings: SettingsStore = .shared) -> Bool {
        settings.theaterDynamicPairing && self.dynamicPairingAvailable(settings: settings)
    }

    /// Home and Theater chrome. Distinct Translate pair. Whisper Small is the
    /// add-on that actually hears both languages.
    @MainActor
    static func showsEitherWayControl(settings: SettingsStore = .shared) -> Bool {
        guard self.dynamicPairingSupportsCurrentPair(settings: settings) else { return false }
        let source = self.sourceLanguage(settings: settings)
        let target = self.targetLanguage(settings: settings)
        let engine = AppleTranslationEngine.shared
        let addOn = SettingsStore.SpeechModel.eitherWayAddOn
        return EitherWayAvailability.isVisible(
            speechReady: SettingsStore.SpeechModel.availableModels.contains(addOn) && addOn.isInstalled,
            forward: engine.cachedPackAvailability(source: source, target: target),
            reverse: engine.cachedPackAvailability(source: target, target: source)
        )
    }

    /// I speak → Show as, unless Either way heard the Show-as language.
    static func pairForSpokenText(
        _ text: String,
        settings: SettingsStore = .shared
    ) -> (source: TranslationLanguage, target: TranslationLanguage) {
        let source = self.sourceLanguage(settings: settings)
        let target = self.targetLanguage(settings: settings)
        guard self.isDynamicPairingEnabled(settings: settings), source.id != target.id else {
            return (source, target)
        }
        let heard = self.listenLanguageID(for: text, settings: settings)
        if heard == target.id, let heardLanguage = TranslationLanguageCatalog.language(id: heard) {
            return (heardLanguage, source)
        }
        return (source, target)
    }

    static func listenLanguageID(for text: String, settings: SettingsStore = .shared) -> String {
        let configured = self.sourceLanguage(settings: settings).id
        let pairing = self.isDynamicPairingEnabled(settings: settings)
        guard settings.theaterAlsoHearOtherLanguages || pairing else { return configured }
        let target = self.targetLanguage(settings: settings).id
        let allowed = [configured, target]
        if let script = SpokenScriptDetector.languageID(in: text, among: allowed) {
            return script
        }
        if pairing, let detected = self.detectedLanguageID, allowed.contains(detected) {
            return detected
        }
        return configured
    }

    static func dynamicPairingControlCopy(settings: SettingsStore = .shared) -> String {
        let source = self.sourceLanguage(settings: settings)
        let target = self.targetLanguage(settings: settings)
        if source.id == target.id {
            return "Pick a Show as language that differs from I speak."
        }
        if !self.dynamicPairingSupportsCurrentPair(settings: settings) {
            return "Either way needs Whisper to hear both \(source.displayName) and \(target.displayName)."
        }
        let addOn = SettingsStore.SpeechModel.eitherWayAddOn
        if !addOn.isInstalled {
            return "Turn this on from Voice Engine. Apple Speech stays the default for one speaker."
        }
        if settings.selectedSpeechModel != addOn {
            return "Uses Whisper Small to hear both languages. Turning Either way off keeps this Voice Engine selected."
        }
        if SpokenScriptDetector.pairSharesOneScript(source.id, target.id) {
            return "Speak either language. Whisper names which one. If it does not, captions stay \(source.displayName) → \(target.displayName)."
        }
        return TheaterReadiness.dynamicPairingHint(isWhisper: true)
    }
}

enum SpokenScriptDetector {
    private enum Family: Hashable {
        case hangul, kana, han, thai, arabic, hebrew, devanagari, cyrillic, latin
    }

    static func languageID(in text: String, among allowed: [String]) -> String? {
        let allowedIDs = Set(allowed.compactMap { Self.normalized($0) })
        guard !allowedIDs.isEmpty else { return nil }
        var scores: [Family: Int] = [:]
        for scalar in text.unicodeScalars {
            guard let family = Self.family(of: scalar) else { continue }
            scores[family, default: 0] += 1
        }
        let ranked = scores.filter { $0.value >= 2 }.sorted { $0.value > $1.value }
        guard let top = ranked.first else { return nil }
        if let second = ranked.dropFirst().first, second.value * 2 >= top.value {
            return nil
        }
        if top.key == .han, (scores[.kana] ?? 0) >= 2, allowedIDs.contains("ja") {
            return "ja"
        }
        let matches = Self.languages(in: top.key, allowed: allowedIDs)
        guard matches.count == 1 else { return nil }
        return matches[0]
    }

    /// English–French and Russian–Ukrainian cannot be told apart by script.
    static func pairSharesOneScript(_ left: String, _ right: String) -> Bool {
        guard let a = Self.primaryFamily(left), let b = Self.primaryFamily(right), a == b else {
            return false
        }
        return a == .latin || a == .cyrillic || a == .han
    }

    private static func normalized(_ id: String) -> String? {
        let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return TranslationLanguageCatalog.language(id: trimmed)?.id ?? trimmed.lowercased()
    }

    private static func primaryFamily(_ languageID: String) -> Family? {
        switch Self.normalized(languageID) {
        case "ko": return .hangul
        case "th": return .thai
        case "ja", "zh": return .han
        case "ar": return .arabic
        case "he": return .hebrew
        case "hi": return .devanagari
        case "ru", "uk": return .cyrillic
        case .some: return .latin
        case .none: return nil
        }
    }

    private static func languages(in family: Family, allowed: Set<String>) -> [String] {
        switch family {
        case .hangul:
            return allowed.contains("ko") ? ["ko"] : []
        case .thai:
            return allowed.contains("th") ? ["th"] : []
        case .kana:
            return allowed.contains("ja") ? ["ja"] : []
        case .han:
            return ["zh", "ja"].filter { allowed.contains($0) }
        case .arabic:
            return allowed.contains("ar") ? ["ar"] : []
        case .hebrew:
            return allowed.contains("he") ? ["he"] : []
        case .devanagari:
            return allowed.contains("hi") ? ["hi"] : []
        case .cyrillic:
            return ["ru", "uk"].filter { allowed.contains($0) }
        case .latin:
            return allowed.filter { Self.primaryFamily($0) == .latin }.sorted()
        }
    }

    private static func family(of scalar: Unicode.Scalar) -> Family? {
        if Self.isHangul(scalar) { return .hangul }
        if Self.isThai(scalar) { return .thai }
        if Self.isKana(scalar) { return .kana }
        if Self.isHan(scalar) { return .han }
        if (0x0600 ... 0x06FF).contains(scalar.value) { return .arabic }
        if (0x0590 ... 0x05FF).contains(scalar.value) { return .hebrew }
        if (0x0900 ... 0x097F).contains(scalar.value) { return .devanagari }
        if (0x0400 ... 0x04FF).contains(scalar.value) { return .cyrillic }
        if Self.isLatinLetter(scalar) { return .latin }
        return nil
    }

    private static func isLatinLetter(_ scalar: Unicode.Scalar) -> Bool {
        CharacterSet.letters.contains(scalar) && scalar.value < 0x0250
    }

    private static func isHangul(_ scalar: Unicode.Scalar) -> Bool {
        (0x1100 ... 0x11FF).contains(scalar.value)
            || (0x3130 ... 0x318F).contains(scalar.value)
            || (0xAC00 ... 0xD7AF).contains(scalar.value)
    }

    private static func isKana(_ scalar: Unicode.Scalar) -> Bool {
        (0x3040 ... 0x30FF).contains(scalar.value)
            || (0x31F0 ... 0x31FF).contains(scalar.value)
            || (0xFF66 ... 0xFF9D).contains(scalar.value)
    }

    private static func isHan(_ scalar: Unicode.Scalar) -> Bool {
        (0x4E00 ... 0x9FFF).contains(scalar.value)
            || (0x3400 ... 0x4DBF).contains(scalar.value)
    }

    private static func isThai(_ scalar: Unicode.Scalar) -> Bool {
        (0x0E00 ... 0x0E7F).contains(scalar.value)
    }
}
