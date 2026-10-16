import Foundation

/// Decides whether a translated string may print on the Theater board.
///
/// This is a text gate, not a translation engine: it never produces a
/// translation, it only rejects bad ones. It runs on Apple Translation's
/// output and rejects malformed error/status responses. A successful result may
/// legitimately equal its source: names, numbers, and acronyms often do.
///
/// The local MLX / LM Studio caption engine this gate once also served was
/// removed. The gate stayed because Apple output needs it too.
enum LiveTranslationCaptionGate {
    /// Empty or provider-error text must never become a Theater line.
    static func captionSafeForBoard(_ candidate: String, sourceText: String) -> String? {
        let cleaned = Self.strippingCaptionPrefix(
            candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        if cleaned.isEmpty { return nil }
        if Self.looksLikeEngineError(cleaned) { return nil }
        if LiveTranslationCommitContext.containsContextClauseMark(cleaned),
           !LiveTranslationCommitContext.containsContextClauseMark(sourceText)
        {
            return nil
        }
        return cleaned
    }

    static func looksLikeEngineError(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let folded = trimmed.folding(
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
            locale: .current
        )
        if folded.hasPrefix("error:") || folded.hasPrefix("error -") || folded.hasPrefix("error—") {
            return true
        }
        if folded.hasPrefix("exception:") || folded.hasPrefix("failed:") { return true }
        return Self.engineErrorKeys.contains(Self.echoKey(trimmed))
    }

    static func strippingCaptionPrefix(_ text: String) -> String {
        var current = Self.strippingWrappingQuotes(
            text.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        for _ in 0..<2 {
            let next = Self.stripOneLabelPrefix(current)
            if next == current { break }
            current = Self.strippingWrappingQuotes(next)
        }
        return current
    }

    /// Printed verbatim, these would tell the audience the engine failed
    /// rather than what the speaker said. The Apple Translation status lines
    /// are pulled from `TheaterEngineCopy` instead of copy-pasted, so editing
    /// that wording can't silently desync this gate from what it's matching.
    private static let engineErrorKeys: [String] = [
        "quota exceeded",
        "rate limit",
        "rate limit exceeded",
        "invalid api key",
        "invalid api",
        "unauthorized",
        "connection refused",
        "econnrefused",
    ] + Self.appleTranslationStatusErrorKeys

    private static let appleTranslationStatusErrorKeys: [String] = [
        TheaterEngineCopy.translationRunningLine(mode: .translation, sameLanguage: false, pack: .unsupported),
        TheaterEngineCopy.translationRunningLine(mode: .translation, sameLanguage: false, pack: .unknown),
    ].map(Self.echoKey)

    /// Best-effort label words across every `TranslationLanguageCatalog.all`
    /// target, not just the four this gate originally shipped with. Apple
    /// Translation can echo a localized "Original:"/"Translation:" style
    /// prefix in the target language; missing an entry here just means that
    /// prefix prints verbatim instead of being stripped, so approximate
    /// translations are an acceptable trade for covering every language.
    private static let captionLabels: Set<String> = [
        "original", "translation", "translated", "source", "caption",
        "output", "input", "english", "korean", "japanese", "thai",
        // Korean
        "원문", "번역", "번역문", "원본", "자막", "출력", "입력",
        // Japanese
        "原文", "訳文", "翻訳", "出力", "入力", "字幕",
        // Chinese
        "译文", "翻译", "输出", "输入",
        // Thai
        "แปล", "ต้นฉบับ", "คำแปล", "คำบรรยาย",
        // Arabic
        "الأصل", "الترجمة", "المصدر",
        // French
        "traduction", "traduit", "sous-titre", "sortie", "entrée",
        // German
        "übersetzung", "übersetzt", "quelle", "untertitel", "ausgabe", "eingabe",
        // Spanish
        "traducción", "traducido", "fuente", "subtítulo", "salida", "entrada",
        // Italian
        "originale", "traduzione", "tradotto", "fonte", "sottotitolo", "uscita", "ingresso",
        // Portuguese
        "tradução", "traduzido", "fonte", "legenda", "saída", "entrada",
        // Dutch
        "origineel", "vertaling", "vertaald", "bron", "ondertitel", "uitvoer", "invoer",
        // Russian
        "оригинал", "перевод", "переведено", "источник", "субтитр", "вывод", "ввод",
        // Polish
        "oryginał", "tłumaczenie", "przetłumaczone", "źródło", "napis", "wyjście", "wejście",
        // Turkish
        "orijinal", "çeviri", "çevrildi", "kaynak", "altyazı", "çıktı", "giriş",
        // Ukrainian
        "оригінал", "переклад", "перекладено", "джерело", "ввід",
        // Vietnamese
        "bản gốc", "bản dịch", "đã dịch", "nguồn", "phụ đề", "đầu ra", "đầu vào",
        // Indonesian
        "asli", "terjemahan", "diterjemahkan", "sumber", "teks", "keluaran", "masukan",
        // Hindi
        "मूल", "अनुवाद", "अनूदित", "स्रोत", "कैप्शन", "आउटपुट", "इनपुट",
    ]

    private static func echoKey(_ text: String) -> String {
        TranslationClauseSegmenter.foldedKey(text)
    }

    private static func stripOneLabelPrefix(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(
            in: CharacterSet(charactersIn: "*#_").union(.whitespacesAndNewlines)
        )
        guard let separator = trimmed.firstIndex(where: { $0 == ":" || $0 == "：" }) else {
            return trimmed
        }
        let label = String(trimmed[..<separator])
            .trimmingCharacters(in: CharacterSet(charactersIn: "*#_ ").union(.whitespacesAndNewlines))
        let foldedLabel = Self.echoKey(label)
        guard Self.captionLabels.contains(where: { Self.echoKey($0) == foldedLabel }),
              !foldedLabel.isEmpty
        else {
            return trimmed
        }
        let after = trimmed[trimmed.index(after: separator)...]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return after.isEmpty ? trimmed : after
    }

    private static func strippingWrappingQuotes(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return trimmed }
        let pairs: [(Character, Character)] = [
            ("\"", "\""), ("“", "”"), ("'", "'"), ("「", "」"), ("『", "』"),
        ]
        for (open, close) in pairs where trimmed.first == open && trimmed.last == close {
            return String(trimmed.dropFirst().dropLast())
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return trimmed
    }
}
