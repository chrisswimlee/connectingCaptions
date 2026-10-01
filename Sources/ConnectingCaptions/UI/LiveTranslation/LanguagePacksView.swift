import Combine
import SwiftUI

/// Setup tab for Apple Translation packs. Lists I speak → each Show as.
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
                subtitle: "Apple Translation downloads a pack when I speak and Show as differ. Same language needs no pack."
            )

            ThemedCard(style: .standard, hoverEffect: false) {
                VStack(alignment: .leading, spacing: 12) {
                    FluidSectionHeader(title: "From \(self.model.source.displayName)", systemImage: "translate")
                    if let message = self.model.downloadError {
                        Text(message)
                            .font(self.theme.typography.bodySmall)
                            .foregroundStyle(self.theme.palette.warning)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if self.model.rows.isEmpty {
                        Text("Checking packs on this Mac…")
                            .font(self.theme.typography.bodySmall)
                            .foregroundStyle(self.theme.palette.secondaryText)
                    } else {
                        ForEach(self.model.rows) { row in
                            self.rowView(row)
                        }
                    }
                }
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

    private func rowView(_ row: LanguagePacksViewModel.Row) -> some View {
        TheaterSideBySide(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(row.target.displayName)
                        .font(self.theme.typography.bodyStrong)
                        .foregroundStyle(self.theme.palette.primaryText)
                    if row.isCurrent {
                        Text("Show as")
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
        .accessibilityIdentifier("languagePacks.\(row.target.id)")
    }

    @ViewBuilder
    private func actions(for row: LanguagePacksViewModel.Row) -> some View {
        if row.isDownloading {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Downloading…")
                    .font(self.theme.typography.caption)
                    .foregroundStyle(self.theme.palette.secondaryText)
            }
        } else if row.status == .installed {
            Text("Ready")
                .font(self.theme.typography.captionStrong)
                .foregroundStyle(self.theme.palette.accent)
        } else if row.status == .unsupported {
            Text("Not supported")
                .font(self.theme.typography.caption)
                .foregroundStyle(self.theme.palette.warning)
        } else {
            Button("Download") {
                Task { await self.model.download(row) }
            }
            .buttonStyle(.theaterTextProminent)
            .disabled(self.model.downloadingID != nil)
            .accessibilityIdentifier("languagePacks.download.\(row.target.id)")
        }
    }
}

@MainActor
final class LanguagePacksViewModel: ObservableObject {
    static let shared = LanguagePacksViewModel()

    struct Row: Identifiable, Equatable {
        let source: TranslationLanguage
        let target: TranslationLanguage
        var status: TranslationPackAvailability
        var isCurrent: Bool
        var isDownloading: Bool

        var id: String { "\(self.source.id)->\(self.target.id)" }

        var statusLine: String {
            if self.isDownloading {
                return "Downloading \(self.source.displayName) → \(self.target.displayName). Keep the app open until it finishes."
            }
            switch self.status {
            case .installed:
                return "Installed. \(self.source.displayName) → \(self.target.displayName) is ready."
            case .supported, .unknown:
                return "Not on this Mac yet. Download once for \(self.source.displayName) → \(self.target.displayName)."
            case .unsupported:
                return "Apple Translation does not support \(self.source.displayName) → \(self.target.displayName)."
            }
        }

        var isWarning: Bool {
            self.status == .unsupported || (self.isCurrent && self.status != .installed && !self.isDownloading)
        }
    }

    @Published private(set) var rows: [Row] = []
    @Published private(set) var downloadingID: String?
    @Published private(set) var downloadError: String?
    @Published private(set) var source = SpokenLanguageResolver.sourceLanguage()

    private var pollTask: Task<Void, Never>?

    func refresh() async {
        let source = SpokenLanguageResolver.sourceLanguage()
        let currentTarget = SpokenLanguageResolver.targetLanguage()
        self.source = source
        await AppleTranslationEngine.shared.refreshInstalledLanguages(
            fixed: source,
            candidates: TranslationLanguageCatalog.menuOrder,
            fixedIsSource: true
        )
        let downloading = self.downloadingID
        self.rows = TranslationLanguageCatalog.menuOrder
            .filter { $0.id != source.id }
            .map { target in
                Row(
                    source: source,
                    target: target,
                    status: AppleTranslationEngine.shared.cachedPackAvailability(source: source, target: target),
                    isCurrent: target.id == currentTarget.id,
                    isDownloading: downloading == AppleTranslationEngine.packCacheKey(source: source, target: target)
                )
            }
    }

    func download(_ row: Row) async {
        guard self.downloadingID == nil else { return }
        self.downloadingID = row.id
        self.downloadError = nil
        self.updateDownloadingFlags()
        AppleTranslationEngine.shared.requestLanguagePackDownload(source: row.source, target: row.target)
        self.pollTask?.cancel()
        self.pollTask = Task { [weak self] in
            await self?.poll(row)
        }
    }

    private func poll(_ row: Row) async {
        var isFirst = true
        let started = Date()
        while !Task.isCancelled {
            if LanguagePackDownloadTiming.timedOut(started: started, now: Date()) {
                self.downloadingID = nil
                self.downloadError =
                    "Download timed out. Keep the app open and try again."
                await self.refresh()
                return
            }
            let status = await AppleTranslationEngine.shared.packAvailability(source: row.source, target: row.target)
            guard !Task.isCancelled else { return }
            switch status {
            case .installed, .unsupported:
                self.downloadingID = nil
                self.downloadError = nil
                await self.refresh()
                return
            case .supported, .unknown:
                if !isFirst {
                    self.updateDownloadingFlags()
                }
            }
            isFirst = false
            try? await Task.sleep(nanoseconds: UInt64(LanguagePackDownloadTiming.pollSeconds * 1_000_000_000))
        }
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
}
