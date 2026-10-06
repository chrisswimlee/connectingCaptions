import Foundation

/// Protects custom-dictionary terms so Apple Translation does not rewrite names.
enum TranslationGlossary {
    struct ProtectedText: Equatable {
        let text: String
        let tokens: [String: String]
    }

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
        guard !text.isEmpty, !terms.isEmpty else {
            return ProtectedText(text: text, tokens: [:])
        }

        var result = text
        var tokens: [String: String] = [:]
        var index = 0
        for term in self.orderedTerms(terms) {
            guard self.containsTerm(term, in: result) else { continue }
            let token = Self.lockToken(index)
            index += 1
            tokens[token] = term
            result = self.replaceTerm(term, with: token, in: result)
        }
        return ProtectedText(text: result, tokens: tokens)
    }

    static func restore(_ text: String, tokens: [String: String]) -> String {
        var result = text
        for (token, original) in tokens {
            result = result.replacingOccurrences(of: token, with: original)
        }
        return result
    }

    /// Terms that appear in the source but vanished from a polished caption.
    static func lostProtectedTerms(source: String, polished: String, terms: [String]) -> [String] {
        self.orderedTerms(terms).filter { term in
            self.containsTerm(term, in: source) && !self.containsTerm(term, in: polished)
        }
    }

    static func containsTerm(_ term: String, in text: String) -> Bool {
        let needle = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard needle.count >= 2, !text.isEmpty else { return false }
        return text.range(of: self.termPattern(needle), options: self.termOptions(for: needle)) != nil
    }

    /// Short all-caps tokens match as written so IT does not eat "it" and AI does not eat Thai.
    private static func termOptions(for term: String) -> String.CompareOptions {
        if self.requiresExactCase(term) {
            return [.regularExpression]
        }
        return [.regularExpression, .caseInsensitive, .diacriticInsensitive]
    }

    private static func requiresExactCase(_ term: String) -> Bool {
        let letters = term.filter(\.isLetter)
        return letters.count >= 2 && letters.count <= 3 && letters.allSatisfy(\.isUppercase)
    }

    private static func orderedTerms(_ terms: [String]) -> [String] {
        var seen = Set<String>()
        var unique: [String] = []
        for term in terms
            .map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) })
            .filter({ $0.count >= 2 })
            .sorted(by: { $0.count > $1.count })
        {
            if seen.insert(term.lowercased()).inserted {
                unique.append(term)
            }
        }
        return unique
    }

    private static func replaceTerm(_ term: String, with token: String, in text: String) -> String {
        text.replacingOccurrences(of: self.termPattern(term), with: token, options: self.termOptions(for: term))
    }

    private static func termPattern(_ term: String) -> String {
        let escaped = NSRegularExpression.escapedPattern(for: term)
        if self.usesWordBoundary(term) {
            return "\\b\(escaped)\\b"
        }
        return escaped
    }

    private static func usesWordBoundary(_ term: String) -> Bool {
        !term.unicodeScalars.contains { scalar in
            (0xAC00...0xD7AF).contains(scalar.value)
                || (0x3040...0x30FF).contains(scalar.value)
                || (0x4E00...0x9FFF).contains(scalar.value)
                || (0x0E00...0x0E7F).contains(scalar.value)
        }
    }

    /// Private-use wrappers so a later term like FT cannot smash a lock token.
    private static func lockToken(_ index: Int) -> String {
        "\u{FFF9}\(index)\u{FFFA}"
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
            return "\(settings.selectedSpeechModel.displayName) does not hear \(source.displayName). Switch Voice Engine to Apple Speech or Whisper."
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
        if let mismatch = self.voiceEngineMismatchMessage(settings: settings) {
            return mismatch
        }
        let source = self.sourceLanguage(settings: settings)
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

    static func isDynamicPairingEnabled(settings: SettingsStore = .shared) -> Bool {
        settings.theaterDynamicPairing && self.dynamicPairingAvailable(settings: settings)
    }

    /// Home and Theater chrome. Distinct Translate pair. Whisper Small is the
    /// add-on that actually hears both languages.
    static func showsEitherWayControl(settings: SettingsStore = .shared) -> Bool {
        guard settings.theaterSessionMode == .translation else { return false }
        guard !self.isSameLanguagePair(settings: settings) else { return false }
        return SettingsStore.SpeechModel.availableModels.contains(SettingsStore.SpeechModel.eitherWayAddOn)
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
        let addOn = SettingsStore.SpeechModel.eitherWayAddOn
        if settings.selectedSpeechModel != addOn {
            return "Uses Whisper Small (\(addOn.downloadSize)) so both languages of this pair are heard. Apple Speech stays the default for one speaker."
        }
        if !self.dynamicPairingAvailable(settings: settings) {
            return "Either way needs Whisper to hear both \(source.displayName) and \(target.displayName)."
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

nonisolated enum LiveTranslationTiming {
    /// English confirm after a finished ending.
    static let completeSettleNanoseconds: UInt64 = 500_000_000
    /// English open-thought silence before a forced cut. The room is already
    /// quiet for the 400 ms silence hold and the 400 ms end-of-utterance hold
    /// before this starts, so this is the extra wait the audience feels.
    static let openSettleNanoseconds: UInt64 = 1_200_000_000
    /// A local sharpen that is slower than this loses. The Apple line prints.
    static let firstPrintSharpenNanoseconds: UInt64 = 700_000_000
    /// Brief hold after end-of-utterance so the last ASR tick can land.
    static let eouHoldNanoseconds: UInt64 = 400_000_000
    /// Quiet gap after the last wording of a lone finished sentence. A revision
    /// restarts it. The sentence prints when this gap passes, without waiting
    /// for the next sentence.
    static let loneSentencePrintNanoseconds: UInt64 = 220_000_000
    /// Partials are de-duplicated, so a quiet gap only means the engine re-heard
    /// the same text once it outlasts that engine's own update cadence (0.2–1 s).
    static let loneSentenceCadenceFactor = 1.5
    static let loneSentenceMaxNanoseconds: UInt64 = 1_500_000_000
    /// A gap longer than this is a pause, not the engine's update cadence.
    static let partialCadenceMaxSeconds: TimeInterval = 2.0

    static func loneSentenceSettleNanoseconds(partialCadence: TimeInterval) -> UInt64 {
        guard partialCadence > 0 else { return self.loneSentencePrintNanoseconds }
        let scaled = UInt64(partialCadence * self.loneSentenceCadenceFactor * 1_000_000_000)
        return min(max(scaled, self.loneSentencePrintNanoseconds), self.loneSentenceMaxNanoseconds)
    }
    static let minPauseFinalizeCharacters = 22
    static let minPauseFinalizeWords = 4
    /// Thai needs a real clause, not a few syllables.
    static let minPauseFinalizeCharactersThai = 22
    /// Korean/Japanese pause-cut. Same character floor as other languages,
    /// so a real leftover does not wait for a long run-on.
    static let minPauseFinalizeCharactersVerbFinal = 22
    static let maxDraftCharacters = 240
    /// Floor for a pause-cut so a leftover is a clause, not two words.
    static let followAlongWords = 8
    /// Pause-finalize only this much so a long unpunctuated talk is not one dump.
    static let maxLineWords = 12
    static let maxLineCharacters = 80
    static let contextSentenceCount = 4
    /// Recent lines the board can still show. A tall window fills from this
    /// list and the presenter can scroll back a few minutes. Older lines stay
    /// in the session record for History and export.
    static let visibleTheaterLines = 48
    static let maxCommittedLines = visibleTheaterLines
    /// Leftover peel runs on every speech update. It uses this recent
    /// suffix, not the whole board, so a full-screen talk stays inside one tick.
    static let peelWindowLines = 12
    /// Leftover peel and last-4 MT priors. Older clauses drop as new ones commit.
    /// Sized off `peelWindowLines`, not the Theater board, since `listenHistory`
    /// never needs more than the largest suffix its consumers take.
    static let maxListenHistory = contextSentenceCount + peelWindowLines
    /// After this much silence, skip ASR ticks and start a new e2e measurement.
    static let silenceHoldNanoseconds: UInt64 = 400_000_000
    static let silenceHoldSeconds: TimeInterval = 0.4
    static let polishPriorCaptionCount = 4
    static let polishTemperature = 0.2
    static let polishMaxTokens = 256
    /// A commit MT call must fail, not hang. Warmup runs before the first
    /// Listen, so the first caption uses the same mailbox timeout as the rest.
    /// A hung call must not hold later sentences.
    static let translateClauseTimeoutNanoseconds: UInt64 = 7_000_000_000
    /// A hung commit fails here instead of blocking the board.
    static let commitMailboxTimeoutNanoseconds: UInt64 = 7_000_000_000
    static let liveMailboxTimeoutNanoseconds: UInt64 = 1_500_000_000
    /// Visually separates captions that finished behind one slow ordered slot.
    /// A normal next caption still publishes as soon as its translation lands.
    static let orderedCatchUpGapNanoseconds: UInt64 = 180_000_000

    static func mailboxTimeoutNanoseconds(for kind: TranslationRequestKind) -> UInt64 {
        switch kind {
        case .live:
            return Self.liveMailboxTimeoutNanoseconds
        case .firstCommit, .commit:
            return Self.commitMailboxTimeoutNanoseconds
        }
    }
    /// Local first-print polish and Apple-failure MT must lose to Apple if slower than a clause.
    static let commitTranslationTimeoutNanoseconds: UInt64 = 4_000_000_000
    /// After this many local attempts, an 80% miss rate disables local MT for the listen.
    static let localEchoFailMinimumAttempts = 5
    static let localEchoFailRatio = 0.80

    static func completeSettleNanoseconds(languageID: String) -> UInt64 {
        switch TranslationClauseSegmenter.languageCode(from: languageID) {
        case "ko", "ja":
            return 1_000_000_000
        case "th":
            return 800_000_000
        default:
            return Self.completeSettleNanoseconds
        }
    }

    static func openSettleNanoseconds(languageID: String) -> UInt64 {
        switch TranslationClauseSegmenter.languageCode(from: languageID) {
        case "ko", "ja":
            return 2_000_000_000
        case "th":
            return 1_500_000_000
        default:
            return Self.openSettleNanoseconds
        }
    }
}
