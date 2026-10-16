import AppKit
import SwiftUI
import UniformTypeIdentifiers

// swiftlint:disable function_body_length cyclomatic_complexity type_body_length
// Tracked grandfather: existing FluidVoice-era file. New work belongs in a smaller file.

struct TranscriptionHistoryView: View {
    @ObservedObject private var historyStore = TranscriptionHistoryStore.shared
    @ObservedObject private var settings = SettingsStore.shared
    @Environment(\.theme) private var theme

    @State private var searchQuery: String = ""
    @State private var showClearConfirmation: Bool = false
    @State private var showReportConfirmation: Bool = false
    @State private var selectedReportEntry: TranscriptionHistoryEntry?
    @State private var selectedEntryID: UUID?
    @State private var entryPendingDeletion: TranscriptionHistoryEntry?

    private var filteredEntries: [TranscriptionHistoryEntry] {
        self.historyStore.entries
    }

    private var selectedEntry: TranscriptionHistoryEntry? {
        guard let id = selectedEntryID else { return self.filteredEntries.first }
        return self.filteredEntries.first(where: { $0.id == id })
    }

    var body: some View {
        HSplitView {
            // MARK: - Left Panel: Entry List

            VStack(spacing: 0) {
                // Search Bar
                self.searchBar
                    .padding(12)

                if self.historyStore.isLoading {
                    ProgressView("Loading history…")
                        .padding(12)
                } else if let error = self.historyStore.persistenceError {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(error)
                            .font(.caption)
                        AppButton("Retry saving history") {
                            self.historyStore.retryPersistence()
                        }
                    }
                    .padding(12)
                }

                Divider()
                    .opacity(0.3)

                // Entry List
                if self.filteredEntries.isEmpty {
                    self.emptyStateView
                } else {
                    self.entryListView
                }

                // Footer with stats and clear button
                self.footerView
                    .disabled(self.historyStore.isLoading)
            }
            .frame(minWidth: 280, idealWidth: 320, maxWidth: 400)
            .background(self.theme.palette.contentBackground)

            // MARK: - Right Panel: Entry Detail

            if let entry = selectedEntry {
                self.entryDetailView(entry)
                    .frame(minWidth: 400)
            } else {
                self.noSelectionView
                    .frame(minWidth: 400)
            }
        }
        .onAppear {
            self.historyStore.applySearchQuery(self.searchQuery)
            if self.selectedEntryID == nil {
                self.selectedEntryID = self.filteredEntries.first?.id
            }
        }
        .onChange(of: self.searchQuery) { _, query in
            self.historyStore.applySearchQuery(query)
        }
        .onChange(of: self.filteredEntries.map(\.id)) { _, ids in
            self.selectedEntryID = HistorySelection.resolve(self.selectedEntryID, availableIDs: ids)
        }
        .alert(AppLanguage.text("Delete transcript?"), isPresented: Binding(
            get: { self.entryPendingDeletion != nil },
            set: {
                if !$0 {
                    self.entryPendingDeletion = nil
                }
            }
        ), presenting: self.entryPendingDeletion) { entry in
            AppButton("Cancel", role: .cancel) {}
            AppButton("Delete", role: .destructive) {
                self.historyStore.deleteEntry(id: entry.id)
                self.selectedEntryID = HistorySelection.resolve(
                    self.selectedEntryID,
                    availableIDs: self.filteredEntries.map(\.id)
                )
            }
        } message: { _ in
            AppText("This permanently deletes this transcript and any saved audio. This cannot be undone.")
        }
        .alert(AppLanguage.text("Clear All History"), isPresented: self.$showClearConfirmation) {
            AppButton("Cancel", role: .cancel) {}
            AppButton("Clear All", role: .destructive) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    self.historyStore.clearAllHistory()
                    self.selectedEntryID = nil
                }
            }
        } message: {
            AppText("This will permanently delete all {0} transcription entries. This action cannot be undone.", arguments: [String(describing: self.historyStore.totalEntryCount)])
        }
        .alert(AppLanguage.text("Draft saved on this Mac"), isPresented: self.$showReportConfirmation) {
            AppButton("OK", role: .cancel) {}
        } message: {
            AppText("The example stays on this Mac. Nothing was sent.")
        }
        .sheet(item: self.$selectedReportEntry) { entry in
            TranscriptionFeedbackReportSheet(entry: entry) {
                self.selectedReportEntry = nil
                self.showReportConfirmation = true
            }
            .environment(\.theme, self.theme)
        }
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)

            TextField(AppLanguage.text("Search captions..."), text: self.$searchQuery)
                .textFieldStyle(.plain)
                .font(.system(size: 13))

            if !self.searchQuery.isEmpty {
                Button {
                    self.searchQuery = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 8)
            .fill(self.theme.palette.cardBackground)
            .overlay(RoundedRectangle(cornerRadius: 8)
                .stroke(self.theme.palette.cardBorder.opacity(0.6), lineWidth: 1)))
    }

    // MARK: - Entry List

    private var entryListView: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                ForEach(self.filteredEntries) { entry in
                    self.entryRow(entry)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
    }

    private func historySourceName(_ entry: TranscriptionHistoryEntry) -> String {
        let name = entry.appName.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasCaptions = entry.captionPairs?.isEmpty == false
        if name.isEmpty || ((name == "Unknown" || name == "Unknown App") && hasCaptions) {
            return "Theater"
        }
        return name
    }

    private func historyWindowName(_ entry: TranscriptionHistoryEntry) -> String {
        let window = entry.windowTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !window.isEmpty, window != "Unknown" {
            return window
        }
        if self.historySourceName(entry) == "Theater" {
            return "Captions"
        }
        return window.isEmpty ? "Unknown" : window
    }

    private func entryRow(_ entry: TranscriptionHistoryEntry) -> some View {
        let isSelected = self.selectedEntryID == entry.id

        return Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                self.selectedEntryID = entry.id
            }
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                // Top row: App name and time
                HStack(spacing: 6) {
                    Text(self.historySourceName(entry))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(isSelected ? .white : .secondary)
                        .lineLimit(1)

                    if self.settings.showHistoryPerformanceMetrics,
                       let duration = entry.transcriptionDurationMilliseconds
                    {
                        self.processingBadge(
                            text: "ASR \(TranscriptionHistoryEntry.formattedDuration(milliseconds: duration))",
                            isSelected: isSelected,
                            isAccent: false
                        )
                    }

                    if self.settings.showHistoryPerformanceMetrics,
                       entry.wasAIProcessed || entry.aiProcessingError != nil
                    {
                        self.processingBadge(
                            text: entry.aiProcessingDurationMilliseconds.map {
                                "AI \(TranscriptionHistoryEntry.formattedDuration(milliseconds: $0))"
                            } ?? "AI",
                            isSelected: isSelected,
                            isAccent: true
                        )
                    } else if entry.wasAIProcessed {
                        self.processingBadge(text: "AI", isSelected: isSelected, isAccent: true)
                    }

                    if self.settings.showHistoryPerformanceMetrics,
                       let tokensPerSecond = entry.aiTokensPerSecond
                    {
                        self.processingBadge(
                            text: TranscriptionHistoryEntry.formattedTokensPerSecond(tokensPerSecond, compact: true),
                            isSelected: isSelected,
                            isAccent: true
                        )
                    }

                    if self.hasAudio(entry) {
                        Image(systemName: "waveform")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(isSelected ? .white.opacity(0.8) : self.theme.palette.accent)
                            .help(AppLanguage.text("Saved local dictation audio"))
                    }

                    if entry.aiProcessingError != nil {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(isSelected ? .white : Color.orange)
                            .help(entry.aiProcessingError ?? "")
                    }

                    Spacer()

                    Text(entry.relativeTimeString)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(isSelected ? .white.opacity(0.7) : Color.secondary.opacity(0.6))
                }

                // Preview text
                Text(entry.previewText)
                    .font(.system(size: 12))
                    .foregroundStyle(isSelected ? .white.opacity(0.9) : .primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? self.theme.palette.accent : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                self.copyToClipboard(entry.processedText)
            } label: {
                Label(entry.wasAIProcessed ? "Copy AI Text" : "Copy Text", systemImage: "doc.on.doc")
            }

            if entry.wasAIProcessed {
                Button {
                    self.copyToClipboard(entry.rawText)
                } label: {
                    AppLabel("Copy Raw Text", systemImage: "doc.on.doc.fill")
                }

                Button {
                    self.copyToClipboard(self.combinedText(for: entry))
                } label: {
                    AppLabel("Copy Both", systemImage: "doc.on.doc")
                }
            }

            if self.hasAudio(entry) {
                Divider()

                Button {
                    self.exportPair(entry)
                } label: {
                    AppLabel("Export Pair...", systemImage: "square.and.arrow.up")
                }

                Button {
                    self.revealAudio(entry)
                } label: {
                    AppLabel("Reveal Audio", systemImage: "waveform")
                }
            }

            Divider()

            Button {
                self.openFeedbackReport(for: entry)
            } label: {
                AppLabel("Report Bad Result...", systemImage: "hand.thumbsup.slash")
            }

            Divider()

            Button(role: .destructive) {
                self.entryPendingDeletion = entry
            } label: {
                AppLabel("Delete", systemImage: "trash")
            }
        }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: self.searchQuery.isEmpty ? "clock.arrow.circlepath" : "magnifyingglass")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(.tertiary)

            VStack(spacing: 4) {
                Text(self.searchQuery.isEmpty ? "No captions yet" : "No Results")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)

                Text(self.searchQuery.isEmpty
                    ? TheaterReadiness.historyEmpty
                    : "Try a different search term")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }

            if self.searchQuery.isEmpty {
                HStack(spacing: 8) {
                    OpenTheaterButton()
                    TheaterListenButton()
                }
            }

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding()
    }

    // MARK: - Footer

    private var footerView: some View {
        VStack(spacing: 0) {
            Divider()
                .opacity(0.3)

            HStack {
                // Stats
                AppText("{0} entries", arguments: [String(describing: self.historyStore.totalEntryCount)])
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.tertiary)

                Spacer()

                // Clear All Button
                if self.historyStore.hasHistory {
                    Button {
                        self.showClearConfirmation = true
                    } label: {
                        AppText("Clear All")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .opacity(0.8)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
    }

    // MARK: - Entry Detail View

    private func entryDetailView(_ entry: TranscriptionHistoryEntry) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        AppText("Transcription Details")
                            .font(.system(size: 18, weight: .semibold))

                        Spacer()

                        Button {
                            self.copyToClipboard(entry.processedText)
                        } label: {
                            Label(entry.wasAIProcessed ? "Copy AI" : "Copy", systemImage: "doc.on.doc")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                        if self.hasAudio(entry) {
                            Button {
                                self.exportPair(entry)
                            } label: {
                                AppLabel("Export Pair", systemImage: "square.and.arrow.up")
                                    .font(.system(size: 12, weight: .medium))
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)

                            Button {
                                self.revealAudio(entry)
                            } label: {
                                AppLabel("Audio", systemImage: "waveform")
                                    .font(.system(size: 12, weight: .medium))
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }

                        Button {
                            self.openFeedbackReport(for: entry)
                        } label: {
                            AppLabel("Report", systemImage: "hand.thumbsup.slash")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .help(AppLanguage.format("Review and send this example to {0}", String(describing: ConnectingCaptionsProduct.displayName)))

                        if entry.wasAIProcessed {
                            Button {
                                self.copyToClipboard(entry.rawText)
                            } label: {
                                AppLabel("Raw", systemImage: "doc.on.doc.fill")
                                    .font(.system(size: 12, weight: .medium))
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)

                            Button {
                                self.copyToClipboard(self.combinedText(for: entry))
                            } label: {
                                AppLabel("Both", systemImage: "doc.on.doc")
                                    .font(.system(size: 12, weight: .medium))
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }

                    Text(entry.fullDateString)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }

                Divider()
                    .opacity(0.3)

                if let aiError = entry.aiProcessingError {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(Color.orange)
                        VStack(alignment: .leading, spacing: 2) {
                            AppText("AI Enhancement failed - raw transcription was typed instead")
                                .font(.system(size: 12, weight: .semibold))
                            Text(aiError)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.orange.opacity(0.08))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .stroke(Color.orange.opacity(0.3), lineWidth: 1)
                            )
                    )
                }

                if let pairs = entry.captionPairs, !pairs.isEmpty {
                    self.captionPairsSection(pairs)
                    HStack(spacing: 8) {
                        AppButton("Export bilingual") {
                            self.exportCaptionPairs(pairs, format: .bilingualText)
                        }
                        AppButton("Export SRT") {
                            self.exportCaptionPairs(pairs, format: .srt)
                        }
                        AppButton("Export VTT") {
                            self.exportCaptionPairs(pairs, format: .vtt)
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    AppText(TheaterReadiness.timedExportHonesty)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                // Final Text Section
                self.detailSection(
                    title: AppLanguage.text("Final Text"),
                    content: entry.processedText,
                    badge: entry.wasAIProcessed ? "AI Enhanced" : nil
                )

                // Raw Text Section (only if different)
                if entry.wasAIProcessed {
                    self.detailSection(
                        title: AppLanguage.text("Original Transcription"),
                        content: entry.rawText,
                        badge: nil,
                        isSecondary: true
                    )
                }

                Divider()
                    .opacity(0.3)

                // Metadata Grid
                self.metadataGrid(entry)

                Spacer(minLength: 20)

                // Delete Button
                HStack {
                    Spacer()
                    Button(role: .destructive) {
                        self.entryPendingDeletion = entry
                    } label: {
                        AppLabel("Delete Entry", systemImage: "trash")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                    .controlSize(.small)
                }
            }
            .padding(24)
        }
        .background(self.theme.palette.contentBackground)
    }

    private func detailSection(
        title: String,
        content: String,
        badge: String?,
        isSecondary: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                AppText(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.5)

                if let badge = badge {
                    Text(badge)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(self.theme.palette.accent)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(self.theme.palette.accent.opacity(0.15))
                        )
                }
            }

            Text(content)
                .font(.system(size: 14, design: .default))
                .foregroundStyle(isSecondary ? .secondary : .primary)
                .textSelection(.enabled)
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 10)
                    .fill(self.theme.palette.cardBackground)
                    .overlay(RoundedRectangle(cornerRadius: 10)
                        .stroke(self.theme.palette.cardBorder.opacity(isSecondary ? 0.35 : 0.5), lineWidth: 1)))
        }
    }

    private func metadataGrid(_ entry: TranscriptionHistoryEntry) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            AppText("Details")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.5)

            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 16),
                GridItem(.flexible(), spacing: 16),
            ], spacing: 12) {
                self.metadataItem(icon: "app.fill", label: "Application", value: self.historySourceName(entry))
                self.metadataItem(icon: "macwindow", label: "Window", value: self.historyWindowName(entry))
                self.metadataItem(icon: "character.cursor.ibeam", label: "Characters", value: "\(entry.characterCount)")
                self.metadataItem(icon: "sparkles", label: "AI Processed", value: entry.wasAIProcessed ? "Yes" : "No")
                if self.settings.showHistoryPerformanceMetrics,
                   let duration = entry.transcriptionDurationMilliseconds
                {
                    self.metadataItem(
                        icon: "waveform",
                        label: "Transcription Time",
                        value: TranscriptionHistoryEntry.formattedDuration(milliseconds: duration)
                    )
                }
                if self.settings.showHistoryPerformanceMetrics,
                   let duration = entry.aiProcessingDurationMilliseconds
                {
                    self.metadataItem(
                        icon: "sparkles",
                        label: "Cleanup Time",
                        value: TranscriptionHistoryEntry.formattedDuration(milliseconds: duration)
                    )
                }
                if self.settings.showHistoryPerformanceMetrics,
                   let tokensPerSecond = entry.aiTokensPerSecond
                {
                    self.metadataItem(
                        icon: "speedometer",
                        label: "AI Speed",
                        value: TranscriptionHistoryEntry.formattedTokensPerSecond(tokensPerSecond)
                    )
                }
                self.metadataItem(icon: "waveform", label: "Audio", value: self.audioMetadataText(for: entry))
            }
        }
    }

    private func metadataItem(icon: String, label: String, value: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.tertiary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                AppText(label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.tertiary)

                Text(value)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }

            Spacer()
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8)
            .fill(self.theme.palette.cardBackground.opacity(0.9)))
    }

    private func processingBadge(
        text: String,
        isSelected: Bool,
        isAccent: Bool
    ) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(
                isSelected ? .white.opacity(0.8) : (isAccent ? self.theme.palette.accent : Color.secondary)
            )
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(
                RoundedRectangle(cornerRadius: 3)
                    .fill(
                        isSelected
                            ? .white.opacity(0.2)
                            : (isAccent ? self.theme.palette.accent.opacity(0.15) : Color.secondary.opacity(0.12))
                    )
            )
    }

    private func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func openFeedbackReport(for entry: TranscriptionHistoryEntry) {
        self.selectedReportEntry = entry
    }

    private func combinedText(for entry: TranscriptionHistoryEntry) -> String {
        "\(entry.rawText)\n\n\(entry.processedText)"
    }

    private func hasAudio(_ entry: TranscriptionHistoryEntry) -> Bool {
        DictationAudioHistoryStore.shared.audioFileExists(for: entry)
    }

    private func audioMetadataText(for entry: TranscriptionHistoryEntry) -> String {
        guard let audio = entry.audio, self.hasAudio(entry) else { return "No" }
        let seconds = Double(audio.durationMilliseconds) / 1000.0
        let size = ByteCountFormatter.string(fromByteCount: Int64(audio.byteCount), countStyle: .file)
        return "\(String(format: "%.1f", seconds))s, \(size)"
    }

    private func revealAudio(_ entry: TranscriptionHistoryEntry) {
        guard let url = DictationAudioHistoryStore.shared.audioFileURL(for: entry),
              FileManager.default.fileExists(atPath: url.path)
        else {
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    /// Runs off the main thread: zipping a pair is a child process, and
    /// doing it inline would beachball the window until `zip` returned.
    private func exportPair(_ entry: TranscriptionHistoryEntry) {
        Task { @MainActor in
            do {
                guard self.hasAudio(entry) else { throw DictationAudioHistoryError.audioMissing }
                let panel = NSSavePanel()
                panel.canCreateDirectories = true
                panel.allowedContentTypes = [.zip]
                panel.nameFieldStringValue = DictationAudioHistoryStore.shared.suggestedPairExportFilename(for: entry)

                guard panel.runModal() == .OK, let url = panel.url else { return }
                try await DictationAudioHistoryStore.shared.exportPair(entry: entry, to: url)
            } catch {
                let alert = NSAlert()
                alert.messageText = "Pair Export Failed"
                alert.informativeText = error.localizedDescription
                alert.alertStyle = .critical
                alert.addButton(withTitle: "OK")
                alert.runModal()
            }
        }
    }

    private func captionPairsSection(_ pairs: [CaptionHistoryPair]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            AppText("Captions")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.5)

            ForEach(Array(pairs.enumerated()), id: \.offset) { _, pair in
                VStack(alignment: .leading, spacing: 4) {
                    Text(pair.translated)
                        .font(.system(size: 14, weight: .medium))
                        .textSelection(.enabled)
                    if !pair.source.isEmpty, pair.source != pair.translated {
                        Text(pair.source)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private func exportCaptionPairs(_ pairs: [CaptionHistoryPair], format: TheaterExportFormat) {
        let text: String
        let ext: String
        switch format {
        case .bilingualText:
            text = TheaterCaptionExport.bilingualText(pairs: pairs)
            ext = "txt"
        case .srt:
            text = TheaterCaptionExport.srt(pairs: pairs)
            ext = "srt"
        case .vtt:
            text = TheaterCaptionExport.vtt(pairs: pairs)
            ext = "vtt"
        case .qualityReview:
            text = TheaterCaptionExport.qualityReview(pairs: pairs)
            ext = "jsonl"
        }
        guard !text.isEmpty else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: ext, conformingTo: .plainText) ?? .plainText]
        panel.nameFieldStringValue = TheaterCaptionExport.savePanelName(extension: ext)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? text.write(to: url, atomically: true, encoding: .utf8)
    }

    // MARK: - No Selection View

    private var noSelectionView: some View {
        VStack(spacing: 16) {
            Image(systemName: "text.quote")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.tertiary)

            AppText("Select a transcription")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(self.theme.palette.contentBackground)
    }
}

private struct TranscriptionFeedbackReportSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme

    @State private var inputText: String
    @State private var outputText: String
    @State private var processingModel: String
    @State private var comment: String
    @State private var isSending: Bool = false
    @State private var errorMessage: String?

    let onSent: () -> Void

    init(entry: TranscriptionHistoryEntry, onSent: @escaping () -> Void) {
        _inputText = State(initialValue: entry.rawText)
        _outputText = State(initialValue: entry.processedText)
        _processingModel = State(initialValue: Self.reportModel(for: entry))
        _comment = State(initialValue: "")
        self.onSent = onSent
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                AppText("Save a local example")
                    .font(.system(size: 18, weight: .semibold))
                AppText("Speech stays on this Mac. A draft is copied so you can attach it to a GitHub issue.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            self.feedbackField(title: AppLanguage.text("Raw Text"), text: self.$inputText, height: 88)
            self.feedbackField(title: AppLanguage.text("Processed Text"), text: self.$outputText, height: 88)
            self.feedbackField(title: AppLanguage.text("Processing Model"), text: self.$processingModel, height: 40)
            self.feedbackField(title: AppLanguage.text("Comment optional"), text: self.$comment, height: 72)

            if let errorMessage {
                AppText(errorMessage)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()
                AppButton("Cancel") {
                    self.dismiss()
                }
                .keyboardShortcut(.cancelAction)
                .disabled(self.isSending)

                Button {
                    Task {
                        await self.sendReport()
                    }
                } label: {
                    HStack(spacing: 8) {
                        if self.isSending {
                            ProgressView()
                                .controlSize(.small)
                                .fixedSize()
                        }
                        Text(self.isSending ? "Saving..." : "Save Local Example")
                    }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(self.isSendDisabled)
            }
        }
        .padding(20)
        .frame(width: 520)
        .background(self.theme.palette.contentBackground)
    }

    private var isSendDisabled: Bool {
        self.isSending ||
            (self.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                self.outputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) ||
            self.processingModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func sendReport() async {
        let payload = TranscriptionFeedbackReporter.Payload(
            rawText: self.inputText.trimmingCharacters(in: .whitespacesAndNewlines),
            processedText: self.outputText.trimmingCharacters(in: .whitespacesAndNewlines),
            processingModel: self.processingModel.trimmingCharacters(in: .whitespacesAndNewlines),
            comments: self.comment.trimmingCharacters(in: .whitespacesAndNewlines)
        )

        self.isSending = true
        self.errorMessage = nil
        do {
            try TranscriptionFeedbackReporter.submit(payload)
            self.isSending = false
            self.onSent()
        } catch {
            self.errorMessage = error.localizedDescription
            self.isSending = false
        }
    }

    private func feedbackField(title: String, text: Binding<String>, height: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            AppText(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            TextEditor(text: text)
                .font(.system(size: 13))
                .scrollContentBackground(.hidden)
                .padding(8)
                .frame(height: height)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(self.theme.palette.cardBackground)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(self.theme.palette.cardBorder.opacity(0.55), lineWidth: 1)
                        )
                )
        }
    }

    private static func reportModel(for entry: TranscriptionHistoryEntry) -> String {
        let model = entry.processingModel?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return model.isEmpty ? "unknown" : model
    }
}

#Preview {
    TranscriptionHistoryView()
        .frame(width: 800, height: 600)
        .environment(\.theme, AppTheme.dark)
}
