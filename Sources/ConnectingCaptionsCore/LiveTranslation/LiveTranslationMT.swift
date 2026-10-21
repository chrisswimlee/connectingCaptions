import Foundation

public enum LiveTranslationMTError: Error {
    case timedOut
}

/// Apple Translation runs one call at a time. A marked-context call that
/// loses its marks is followed by a second, isolated call, so every sentence
/// paid twice. After `missLimit` misses in a row for a pair this Listen, a
/// sentence goes straight to the isolated call.
@MainActor
public final class LiveTranslationContextStreak {
    public static let missLimit = 2
    private var misses: [String: Int] = [:]

    public init() {}

    public func reset() {
        self.misses = [:]
    }

    public func usesContext(source: TranslationLanguage, target: TranslationLanguage) -> Bool {
        (self.misses[Self.key(source, target)] ?? 0) < Self.missLimit
    }

    public func note(hit: Bool, source: TranslationLanguage, target: TranslationLanguage) {
        let key = Self.key(source, target)
        self.misses[key] = hit ? 0 : (self.misses[key] ?? 0) + 1
    }

    private static func key(_ source: TranslationLanguage, _ target: TranslationLanguage) -> String {
        "\(source.id)>\(target.id)"
    }
}

@MainActor
public enum LiveTranslationMT {
    /// Apple Translation is `session.translate(text)` with no prompt. Isolated
    /// Korean/Thai clauses lose zero-subject context, so commit sends the last
    /// 2–4 source clauses with the new one marked, then takes that span.
    public static func appleClause(
        _ text: String,
        source: TranslationLanguage,
        target: TranslationLanguage,
        terms: [String],
        kind: TranslationRequestKind,
        prior: (sources: [String], translations: [String]),
        translator: TranslationEngine,
        contextStreak: LiveTranslationContextStreak? = nil
    ) async throws -> String {
        // Do not pause the speech tick for this call. A commit used to skip
        // every recognition update until Apple returned, so a slow or repeated
        // translation left a hole and the next tick had to catch up. The
        // Apple mailbox still runs one session call at a time.
        if !prior.sources.isEmpty, contextStreak?.usesContext(source: source, target: target) ?? true {
            let payload = LiveTranslationCommitContext.markedContextPayload(
                priors: prior.sources,
                current: text,
                languageID: source.id
            )
            let contextual = try await self.translateProtected(
                payload,
                terms: terms,
                source: source,
                target: target,
                kind: kind,
                translator: translator
            )
            if let marked = LiveTranslationCommitContext.markedNewTranslation(contextual),
               LiveTranslationCommitContext.containsContextClauseMark(marked) == false,
               LiveTranslationCommitContext.isSanePeeledCaption(
                   marked,
                   isolatedSource: text,
                   targetID: target.id
               )
            {
                contextStreak?.note(hit: true, source: source, target: target)
                return marked
            }
            CoreLog.debug(
                "Contextual caption marks did not yield the new clause.",
                source: "LiveTranslation"
            )
            // A blob that still contains a mark has a broken boundary. Prefix
            // peel would keep that mark in the caption. Peel only when the
            // model dropped the marks and kept the prior caption in front.
            if LiveTranslationCommitContext.containsContextClauseMark(contextual) == false,
               let lined = LiveTranslationCommitContext.lineBoundNewTranslation(
                   contextual,
                   priorTranslations: prior.translations,
                   isolatedSource: text,
                   targetID: target.id
               )
            {
                contextStreak?.note(hit: true, source: source, target: target)
                return lined
            }
            if LiveTranslationCommitContext.containsContextClauseMark(contextual) == false,
               let peeled = LiveTranslationCommitContext.peeledNewTranslation(
                   contextual,
                   priorTranslations: prior.translations,
                   targetID: target.id
               ), LiveTranslationCommitContext.isSanePeeledCaption(
                   peeled,
                   isolatedSource: text,
                   targetID: target.id
               )
            {
                contextStreak?.note(hit: true, source: source, target: target)
                return peeled
            }
            contextStreak?.note(hit: false, source: source, target: target)
        }
        return try await self.translateProtected(
            text,
            terms: terms,
            source: source,
            target: target,
            kind: kind,
            translator: translator
        )
    }

    public static func translateProtected(
        _ text: String,
        terms: [String],
        source: TranslationLanguage,
        target: TranslationLanguage,
        kind: TranslationRequestKind,
        translator: TranslationEngine
    ) async throws -> String {
        let protected = TranslationGlossaryLock.protect(text, terms: terms)
        let translated = try await self.translateWithRetry(
            protected.text,
            source: source,
            target: target,
            engine: translator,
            kind: kind
        )
        return TranslationGlossaryLock.restore(translated, tokens: protected.tokens)
    }

    public static func translateWithRetry(
        _ text: String,
        source: TranslationLanguage,
        target: TranslationLanguage,
        engine: TranslationEngine,
        kind: TranslationRequestKind
    ) async throws -> String {
        // The Apple mailbox already runs one session call at a time and lets a
        // commit supersede a live prefetch. A second queue in front of it held
        // a grown sentence behind a call that had already been replaced.
        do {
            return try await engine.translate(text, source: source, target: target, kind: kind)
        } catch {
            if error is CancellationError { throw error }
            if let engineError = error as? TranslationEngineError,
               engineError.isSuperseded || engineError.isTimeout
            {
                throw error
            }
            CoreLog.debug(
                "Apple Translation retry after \(DiagnosticMetadata.error(error))",
                source: "LiveTranslation"
            )
            return try await engine.translate(text, source: source, target: target, kind: kind)
        }
    }
}
