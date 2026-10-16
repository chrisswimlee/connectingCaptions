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
                title: AppLanguage.text("Language packs"),
                subtitle: AppLanguage.text("Translation pairs for the current I speak language. Unsupported pairs are hidden. Speech recognition languages and downloads are listed in Voice Engine.")
            )

            if !self.model.checkingRows.isEmpty {
                AppButton("Check again") { Task { await self.model.refresh() } }
                    .buttonStyle(.theaterText)
                    .disabled(self.model.isRefreshing)
            }

            if let message = self.model.downloadError {
                AppText(message)
                    .font(self.theme.typography.bodySmall)
                    .foregroundStyle(self.theme.palette.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if self.model.rows.isEmpty {
                ThemedCard(style: .standard, hoverEffect: false) {
                    AppText(self.model.isRefreshing ? AppLanguage.text("Checking packs on this Mac…") : AppLanguage.text("No supported translation packs for this I speak language."))
                        .font(self.theme.typography.bodySmall)
                        .foregroundStyle(self.theme.palette.secondaryText)
                }
            } else {
                self.section(
                    title: AppLanguage.text("Ready to use"),
                    systemImage: "checkmark.circle",
                    rows: self.model.readyRows,
                    emptyText: AppLanguage.text("No languages are ready yet.")
                )
                if !self.model.checkingRows.isEmpty {
                    self.section(title: AppLanguage.text("Checking availability…"), systemImage: "clock",
                                 rows: self.model.checkingRows, emptyText: "")
                }
                self.section(
                    title: AppLanguage.text("Needs a download"),
                    systemImage: "arrow.down.circle",
                    rows: self.model.needsDownloadRows,
                    emptyText: AppLanguage.text("No confirmed downloads needed.")
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
                    AppText(emptyText)
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
                    Text(AppLanguage.localizedName(for: row.language))
                        .font(self.theme.typography.bodyStrong)
                        .foregroundStyle(self.theme.palette.primaryText)
                    ForEach(row.roles, id: \.self) { role in
                        AppText(role)
                            .font(self.theme.typography.caption)
                            .foregroundStyle(self.theme.palette.accent)
                    }
                }
                Text(self.model.pairLabel(for: row))
                    .font(self.theme.typography.caption)
                    .foregroundStyle(self.theme.palette.secondaryText)
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
            case .checking:
                AppText("Checking availability…")
                    .font(self.theme.typography.caption)
            case .packDownloaded:
                AppText("Pack downloaded")
                    .font(self.theme.typography.captionStrong)
                    .foregroundStyle(self.theme.palette.accent)
            case .appleIntelligence:
                VStack(alignment: .trailing, spacing: 4) {
                    AppText("Ready")
                        .font(self.theme.typography.captionStrong)
                        .foregroundStyle(self.theme.palette.accent)
                    AppButton("Download pack") {
                        Task { await self.model.download(row) }
                    }
                    .buttonStyle(.theaterText)
                    .disabled(self.model.downloadingID != nil || self.model.isRefreshing)
                    .accessibilityIdentifier("languagePacks.download.\(row.language.id)")
                }
            case .unsupported:
                AppText("Not supported")
                    .font(self.theme.typography.caption)
                    .foregroundStyle(self.theme.palette.warning)
            case .needsDownload:
                AppButton("Download") {
                    Task { await self.model.download(row) }
                }
                .buttonStyle(.theaterTextProminent)
                .disabled(self.model.downloadingID != nil || self.model.isRefreshing)
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

        var id: String {
            self.language.id
        }

        var statusLine: String {
            if self.isDownloading {
                return AppLanguage.text("Downloading this translation pair. Keep the app open until it finishes.")
            }
            switch self.coverage {
            case .checking:
                return AppLanguage.text("Translation availability has not been confirmed. Try checking again.")
            case .packDownloaded:
                return AppLanguage.text("The translation pack for this direction is on this Mac.")
            case .appleIntelligence:
                return AppLanguage.text("This direction translates now using Apple Intelligence.")
            case .needsDownload:
                return AppLanguage.text("Download this translation pair once to use it.")
            case .unsupported:
                return AppLanguage.text("Apple Translation does not support this direction.")
            }
        }

        var canDownload: Bool {
            self.coverage == .needsDownload || self.coverage == .appleIntelligence
        }

        var isWarning: Bool {
            self.coverage == .unsupported
                || (!self.roles.isEmpty && self.coverage == .needsDownload && !self.isDownloading)
        }
    }

    typealias PairStatus = (TranslationLanguage, TranslationLanguage) async -> LanguagePackCoverage

    @Published private(set) var rows: [Row] = []
    @Published private(set) var isRefreshing = true
    @Published private(set) var downloadingID: String?
    @Published private(set) var downloadStartedAt: Date?
    @Published private(set) var downloadError: String?

    private var pollTask: Task<Void, Never>?
    private var refreshRevision: UInt64 = 0
    private var displayedPair: TranslationPairKey?

    static func visibleRows(_ rows: [Row]) -> [Row] {
        rows.filter { $0.coverage != .unsupported }
    }

    var readyRows: [Row] {
        self.rows.filter { $0.coverage == .packDownloaded || $0.coverage == .appleIntelligence }
    }

    var checkingRows: [Row] {
        self.rows.filter { $0.coverage == .checking }
    }

    func pairLabel(for row: Row) -> String {
        guard let pair = Self.downloadPair(for: row.language, source: SpokenLanguageResolver.sourceLanguage(),
                                          target: SpokenLanguageResolver.targetLanguage()) else { return "" }
        return AppLanguage.format("{0} → {1}", AppLanguage.localizedName(for: pair.source), AppLanguage.localizedName(for: pair.target))
    }

    var needsDownloadRows: [Row] {
        self.rows.filter { $0.coverage == .needsDownload }
    }

    func refresh() async {
        self.refreshRevision &+= 1
        let revision = self.refreshRevision
        self.isRefreshing = true
        defer { if revision == self.refreshRevision { self.isRefreshing = false } }
        let pair = TranslationPairKey.current()
        if pair != self.displayedPair {
            self.rows = []
            self.displayedPair = pair
        }
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
            guard coverage != .unsupported else { continue }
            var roles: [String] = []
            if language.id == source.id {
                roles.append("I speak")
            }
            if language.id == target.id, source.id != target.id {
                roles.append("Show as")
            }
            rows.append(Row(
                language: language,
                coverage: coverage,
                roles: roles,
                isDownloading: language.id == downloading
            ))
        }
        guard !Task.isCancelled, revision == self.refreshRevision, pair == .current() else { return }
        self.rows = Self.visibleRows(rows).map { row in
            var updated = row
            updated.isDownloading = row.id == self.downloadingID
            return updated
        }
        // Download completion and Check again must update Listen and the shared menus too.
        await LiveTranslationController.shared.refreshPackAvailability()
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

    static func downloadPair(
        for language: TranslationLanguage,
        source: TranslationLanguage,
        target: TranslationLanguage
    ) -> (source: TranslationLanguage, target: TranslationLanguage)? {
        if language.id != source.id { return (source, language) }
        let partner = source.id != target.id ? target : TranslationLanguageCatalog.menuOrder.first { $0.id != source.id }
        guard let partner else { return nil }
        return (source, partner)
    }

    func download(_ row: Row) async {
        guard self.downloadingID == nil, !self.isRefreshing, self.displayedPair == .current(), row.canDownload else { return }
        let source = SpokenLanguageResolver.sourceLanguage()
        let target = SpokenLanguageResolver.targetLanguage()
        guard let pair = Self.downloadPair(for: row.language, source: source, target: target) else { return }
        self.downloadingID = row.id
        self.downloadStartedAt = Date()
        self.downloadError = nil
        self.updateDownloadingFlags()
        AppleTranslationEngine.shared.requestLanguagePackDownload(source: pair.source, target: pair.target)
        self.pollTask?.cancel()
        self.pollTask = Task { [weak self] in
            await self?.poll(language: pair.source, partner: pair.target)
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
