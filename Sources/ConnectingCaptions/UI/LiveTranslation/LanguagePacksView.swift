import Combine
import SwiftUI

/// Setup tab for Apple Translation packs. Lists one row per language.
struct LanguagePacksScreen: View {
    let theme: AppTheme

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LanguagePacksView(theme: self.theme)
                    .fluidPageContent()
                    .id(Self.pageTopID)
            }
            .defaultScrollAnchor(.top)
            .onAppear {
                proxy.scrollTo(Self.pageTopID, anchor: .top)
            }
        }
    }

    private static let pageTopID = "language-packs-page-top"
}

struct LanguagePacksView: View {
    let theme: AppTheme
    @ObservedObject private var settings = SettingsStore.shared
    @ObservedObject private var model = LanguagePacksViewModel.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            FluidPageHeader(
                systemImage: "arrow.down.circle",
                title: "Language packs",
                subtitle: "Most languages already translate using Apple Intelligence. " +
                    "Download the fast pack for a language to use it without Apple Intelligence, or to speed it up."
            )

            if let message = self.model.downloadError {
                Text(message)
                    .font(self.theme.typography.bodySmall)
                    .foregroundStyle(self.theme.palette.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if self.model.rows.isEmpty {
                ThemedCard(style: .standard, hoverEffect: false) {
                    Text("Checking packs on this Mac…")
                        .font(self.theme.typography.bodySmall)
                        .foregroundStyle(self.theme.palette.secondaryText)
                }
            } else {
                self.section(
                    title: "Ready to use",
                    systemImage: "checkmark.circle",
                    rows: self.model.readyRows,
                    emptyText: "No languages are ready yet."
                )
                self.section(
                    title: "Needs a download",
                    systemImage: "arrow.down.circle",
                    rows: self.model.needsDownloadRows,
                    emptyText: "Every language is ready."
                )
            }
        }
        .accessibilityIdentifier("languagePacks.list")
        .task {
            await self.model.refresh()
        }
        .onChange(of: self.settings.translationSourceLanguageID) { _, _ in
            Task { await self.model.refresh() }
        }
        .onChange(of: self.settings.translationTargetLanguageID) { _, _ in
            Task { await self.model.refresh() }
        }
    }

    private func section(
        title: String,
        systemImage: String,
        rows: [LanguagePacksViewModel.Row],
        emptyText: String
    ) -> some View {
        ThemedCard(style: .standard, hoverEffect: false) {
            VStack(alignment: .leading, spacing: 12) {
                FluidSectionHeader(title: title, systemImage: systemImage)
                if rows.isEmpty {
                    Text(emptyText)
                        .font(self.theme.typography.bodySmall)
                        .foregroundStyle(self.theme.palette.secondaryText)
                } else {
                    ForEach(rows) { row in
                        self.rowView(row)
                    }
                }
            }
        }
    }

    private func rowView(_ row: LanguagePacksViewModel.Row) -> some View {
        TheaterSideBySide(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(row.language.displayName)
                        .font(self.theme.typography.bodyStrong)
                        .foregroundStyle(self.theme.palette.primaryText)
                    ForEach(row.roles, id: \.self) { role in
                        Text(role)
                            .font(self.theme.typography.caption)
                            .foregroundStyle(self.theme.palette.accent)
                    }
                }
                Text(row.statusLine)
                    .font(self.theme.typography.bodySmall)
                    .foregroundStyle(row.isWarning ? self.theme.palette.warning : self.theme.palette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } trailing: {
            self.actions(for: row)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("languagePacks.\(row.language.id)")
    }

    @ViewBuilder
    private func actions(for row: LanguagePacksViewModel.Row) -> some View {
        if row.isDownloading {
            self.downloadProgress(started: self.model.downloadStartedAt ?? Date())
        } else {
            switch row.coverage {
            case .packDownloaded:
                Text("Pack downloaded")
                    .font(self.theme.typography.captionStrong)
                    .foregroundStyle(self.theme.palette.accent)
            case .appleIntelligence:
                VStack(alignment: .trailing, spacing: 4) {
                    Text("Ready")
                        .font(self.theme.typography.captionStrong)
                        .foregroundStyle(self.theme.palette.accent)
                    Button("Download pack") {
                        Task { await self.model.download(row) }
                    }
                    .buttonStyle(.theaterText)
                    .disabled(self.model.downloadingID != nil)
                    .accessibilityIdentifier("languagePacks.download.\(row.language.id)")
                }
            case .unsupported:
                Text("Not supported")
                    .font(self.theme.typography.caption)
                    .foregroundStyle(self.theme.palette.warning)
            case .needsDownload:
                Button("Download") {
                    Task { await self.model.download(row) }
                }
                .buttonStyle(.theaterTextProminent)
                .disabled(self.model.downloadingID != nil)
                .accessibilityIdentifier("languagePacks.download.\(row.language.id)")
            }
        }
    }

    /// Apple Translation reports no byte progress to apps, so the bar stays
    /// indeterminate and the label shows elapsed time against the timeout.
    private func downloadProgress(started: Date) -> some View {
        TimelineView(.periodic(from: started, by: 1)) { context in
            VStack(alignment: .trailing, spacing: 4) {
                ProgressView()
                    .progressViewStyle(.linear)
                    .frame(width: 140)
                Text(LanguagePackDownloadTiming.progressLabel(started: started, now: context.date))
                    .font(self.theme.typography.caption)
                    .foregroundStyle(self.theme.palette.secondaryText)
                    .monospacedDigit()
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("languagePacks.progress")
    }
}

@MainActor
final class LanguagePacksViewModel: ObservableObject {
    static let shared = LanguagePacksViewModel()

    struct Row: Identifiable, Equatable {
        let language: TranslationLanguage
        var coverage: LanguagePackCoverage
        var roles: [String]
        var isDownloading: Bool

        var id: String { self.language.id }

        var statusLine: String {
            if self.isDownloading {
                return "Downloading the \(self.language.displayName) pack. Keep the app open until it finishes."
            }
            switch self.coverage {
            case .packDownloaded:
                return "The fast pack for \(self.language.displayName) is on this Mac."
            case .appleIntelligence:
                return "\(self.language.displayName) translates now using Apple Intelligence."
            case .needsDownload:
                return "Download \(self.language.displayName) once to use it."
            case .unsupported:
                return "Apple Translation does not support \(self.language.displayName) yet."
            }
        }

        var isWarning: Bool {
            self.coverage == .unsupported
                || (!self.roles.isEmpty && self.coverage == .needsDownload && !self.isDownloading)
        }
    }

    typealias PairStatus = (TranslationLanguage, TranslationLanguage) async -> LanguagePackCoverage

    @Published private(set) var rows: [Row] = []
    @Published private(set) var downloadingID: String?
    @Published private(set) var downloadStartedAt: Date?
    @Published private(set) var downloadError: String?

    private var pollTask: Task<Void, Never>?

    var readyRows: [Row] { self.rows.filter { $0.coverage != .needsDownload && $0.coverage != .unsupported } }
    var needsDownloadRows: [Row] { self.rows.filter { $0.coverage == .needsDownload || $0.coverage == .unsupported } }

    func refresh() async {
        let source = SpokenLanguageResolver.sourceLanguage()
        let target = SpokenLanguageResolver.targetLanguage()
        let languages = TranslationLanguageCatalog.menuOrder
        let downloading = self.downloadingID
        var rows: [Row] = []
        for language in languages {
            let coverage: LanguagePackCoverage
            if language.id == source.id {
                coverage = await Self.coverage(
                    for: language,
                    pairedWith: target.id != source.id ? target : nil,
                    isSource: true
                )
            } else {
                coverage = await AppleTranslationEngine.shared.languagePackCoverage(source: source, target: language)
            }
            var roles: [String] = []
            if language.id == source.id { roles.append("I speak") }
            if language.id == target.id, source.id != target.id { roles.append("Show as") }
            rows.append(Row(
                language: language,
                coverage: coverage,
                roles: roles,
                isDownloading: language.id == downloading
            ))
        }
        self.rows = rows
    }

    /// `languagePackCoverage` needs a direction. For "I speak," pair it with
    /// "Show as" when the two differ, otherwise with English, so same-source
    /// languages still get a real answer instead of defaulting to "no pack."
    private static func coverage(
        for language: TranslationLanguage,
        pairedWith other: TranslationLanguage?,
        isSource: Bool
    ) async -> LanguagePackCoverage {
        let partner = other ?? TranslationLanguageCatalog.menuOrder.first { $0.id != language.id }
        guard let partner else { return .needsDownload }
        return await AppleTranslationEngine.shared.languagePackCoverage(source: language, target: partner)
    }

    /// Pair the new language with one already downloaded or Apple
    /// Intelligence-covered so Apple fetches only the missing pack.
    static func downloadPartner(
        for language: TranslationLanguage,
        ready: [TranslationLanguage],
        fallbacks: [TranslationLanguage]
    ) -> TranslationLanguage? {
        (ready + fallbacks).first { $0.id != language.id }
    }

    func download(_ row: Row) async {
        guard self.downloadingID == nil else { return }
        let fallbacks = [
            SpokenLanguageResolver.sourceLanguage(),
            SpokenLanguageResolver.targetLanguage(),
        ] + TranslationLanguageCatalog.menuOrder
        let ready = self.rows.filter { $0.coverage != .needsDownload && $0.coverage != .unsupported }.map(\.language)
        guard let partner = Self.downloadPartner(
            for: row.language,
            ready: ready,
            fallbacks: fallbacks
        ) else { return }
        self.downloadingID = row.id
        self.downloadStartedAt = Date()
        self.downloadError = nil
        self.updateDownloadingFlags()
        AppleTranslationEngine.shared.requestLanguagePackDownload(source: row.language, target: partner)
        self.pollTask?.cancel()
        self.pollTask = Task { [weak self] in
            await self?.poll(language: row.language, partner: partner)
        }
    }

    private func poll(language: TranslationLanguage, partner: TranslationLanguage) async {
        let started = Date()
        while !Task.isCancelled {
            if LanguagePackDownloadTiming.timedOut(started: started, now: Date()) {
                self.finishDownload(error: "Download timed out. Keep the app open and try again.")
                await self.refresh()
                return
            }
            let status = await AppleTranslationEngine.shared.fastPackAvailability(source: language, target: partner)
            guard !Task.isCancelled else { return }
            switch status {
            case .installed, .unsupported:
                self.finishDownload(error: nil)
                await self.refresh()
                return
            case .supported, .unknown:
                break
            }
            try? await Task.sleep(nanoseconds: UInt64(LanguagePackDownloadTiming.pollSeconds * 1_000_000_000))
        }
    }

    private func finishDownload(error: String?) {
        self.downloadingID = nil
        self.downloadStartedAt = nil
        self.downloadError = error
        self.updateDownloadingFlags()
    }

    private func updateDownloadingFlags() {
        let downloading = self.downloadingID
        self.rows = self.rows.map { row in
            var next = row
            next.isDownloading = row.id == downloading
            return next
        }
    }
}

enum LanguagePackDownloadTiming {
    static let pollSeconds: TimeInterval = 2
    static let timeoutSeconds: TimeInterval = 10 * 60

    static func timedOut(
        started: Date,
        now: Date,
        limit: TimeInterval = timeoutSeconds
    ) -> Bool {
        now.timeIntervalSince(started) >= limit
    }

    /// "Downloading · 1:05 of 10:00" — elapsed time against the timeout.
    static func progressLabel(
        started: Date,
        now: Date,
        limit: TimeInterval = timeoutSeconds
    ) -> String {
        let elapsed = min(max(0, now.timeIntervalSince(started)), limit)
        return "Downloading · \(self.clock(elapsed)) of \(self.clock(limit))"
    }

    private static func clock(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
