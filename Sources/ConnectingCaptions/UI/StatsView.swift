import SwiftUI

// swiftlint:disable function_body_length cyclomatic_complexity type_body_length
// Tracked grandfather: existing FluidVoice-era file. New work belongs in a smaller file.

struct StatsView: View {
    @ObservedObject private var historyStore = TranscriptionHistoryStore.shared
    @ObservedObject private var settings = SettingsStore.shared
    @Environment(\.theme) private var theme

    @State private var showResetConfirmation: Bool = false
    @State private var showWPMEditor: Bool = false
    @State private var editingWPM: String = ""
    @State private var chartDays: Int = 7 // Toggle between 7 and 30
    @State private var hoveredActivityIndex: Int?

    private static let activityTooltipDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEE MMM d")
        return formatter
    }()

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 16) {
                self.todayHeaderCard

                Divider()
                    .opacity(0.4)

                // Header row: Time Saved + Total Words
                HStack(spacing: 16) {
                    self.timeSavedCard
                    self.totalWordsCard
                }

                // Second row: Streak + Transcriptions
                HStack(spacing: 16) {
                    self.streakCard
                    self.transcriptionsCard
                }

                // Activity Chart
                self.activityChartCard

                // Milestones
                self.milestonesCard

                // Insights
                self.insightsCard

                // Personal Records
                self.recordsCard

                // Reset Button
                self.resetSection
            }
            .padding(20)
        }
    }

    // MARK: - Today Header

    private var todayHeaderCard: some View {
        let summary = self.historyStore.todaySummary
        let wordsToday = summary.words
        let timeSavedToday = summary.formattedTimeSaved(typingWPM: self.settings.userTypingWPM)
        let sessionsToday = summary.transcriptions
        let streak = self.historyStore.currentStreak

        return ThemedCard(style: .prominent, padding: 20, hoverEffect: false) {
            VStack(alignment: .leading, spacing: 14) {
                // Greeting + streak badge
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        AppText("Today")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)

                        Text(self.motivationalMessage(
                            wordsToday: wordsToday,
                            streak: streak
                        ))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer()

                    if streak > 0 {
                        HStack(spacing: 4) {
                            Image(systemName: "flame.fill")
                                .font(.system(size: 11))
                            AppText("{0} day{1}", arguments: [String(describing: streak), String(describing: streak == 1 ? "" : "s")])
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                        }
                        .foregroundStyle(self.theme.palette.warning)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            Capsule()
                                .fill(self.theme.palette.warning.opacity(0.15))
                        )
                    }
                }

                // Today's metrics row
                HStack(spacing: 24) {
                    self.todayMetric(
                        icon: "text.word.spacing",
                        value: self.formatNumber(wordsToday),
                        label: "words"
                    )

                    Divider()
                        .frame(height: 32)

                    self.todayMetric(
                        icon: "clock.fill",
                        value: timeSavedToday,
                        label: "saved"
                    )

                    Divider()
                        .frame(height: 32)

                    self.todayMetric(
                        icon: "waveform",
                        value: "\(sessionsToday)",
                        label: "sessions"
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func todayMetric(icon: String, value: String, label: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(self.theme.palette.accent)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                AppText(label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Motivational message that scales with today's activity level.
    private func motivationalMessage(wordsToday: Int, streak: Int) -> String {
        if wordsToday == 0 {
            return streak > 0
                ? "Keep the streak alive — \(TheaterReadiness.openTheaterAndListen)."
                : "Ready when you are. \(TheaterReadiness.openTheaterAndListen)."
        }

        if wordsToday < 100 {
            return "Warming up. Every word counts."
        }

        if wordsToday < 500 {
            return "Solid pace — you're saving real time today."
        }

        if wordsToday < 1500 {
            return streak > 2 ? "On fire. The streak is paying off." : "Strong day. Your hands thank you."
        }

        return "Outstanding. You've reclaimed serious time today."
    }

    // MARK: - Time Saved Card

    private var timeSavedCard: some View {
        StatCard(title: AppLanguage.text("TIME SAVED"), icon: "clock.fill") {
            VStack(alignment: .leading, spacing: 8) {
                Text(self.historyStore.formattedTimeSaved(typingWPM: self.settings.userTypingWPM))
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)

                Button {
                    self.editingWPM = "\(self.settings.userTypingWPM)"
                    self.showWPMEditor = true
                } label: {
                    HStack(spacing: 4) {
                        AppText("Based on {0} WPM typing", arguments: [String(describing: self.settings.userTypingWPM)])
                            .font(.system(size: 11))
                        Image(systemName: "pencil")
                            .font(.system(size: 9))
                    }
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .popover(isPresented: self.$showWPMEditor) {
            self.wpmEditorPopover
        }
    }

    private var wpmEditorPopover: some View {
        VStack(alignment: .leading, spacing: 12) {
            AppText("Your Typing Speed")
                .font(.system(size: 13, weight: .semibold))

            HStack {
                TextField(AppLanguage.text("WPM"), text: self.$editingWPM)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 60)
                    .multilineTextAlignment(.center)

                AppText("words per minute")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            AppText("Average typing: 40 WPM\nProfessional: 65-75 WPM")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)

            HStack {
                AppButton("Cancel") {
                    self.showWPMEditor = false
                }
                .fluidButton(.compact, size: .small)

                AppButton("Save") {
                    if let wpm = Int(editingWPM), wpm > 0 {
                        self.settings.userTypingWPM = wpm
                    }
                    self.showWPMEditor = false
                }
                .fluidButton(.accent, size: .small)
            }
        }
        .padding(16)
        .frame(width: 220)
    }

    // MARK: - Total Words Card

    private var totalWordsCard: some View {
        StatCard(title: AppLanguage.text("TOTAL WORDS"), icon: "text.word.spacing") {
            VStack(alignment: .leading, spacing: 8) {
                Text(self.formatNumber(self.historyStore.totalWords))
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)

                let today = self.historyStore.wordsToday
                if today > 0 {
                    AppText("+{0} today", arguments: [String(describing: self.formatNumber(today))])
                        .font(.system(size: 11))
                        .foregroundStyle(self.theme.palette.success)
                } else {
                    AppText(TheaterReadiness.openTheaterAndListen)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Streak Card

    private var streakCard: some View {
        StatCard(title: AppLanguage.text("CURRENT STREAK"), icon: "flame.fill") {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    AppText("{0}", arguments: [String(describing: self.historyStore.currentStreak)])
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundStyle(self.historyStore.currentStreak > 0 ? self.theme.palette.warning : .primary)

                    Text(self.historyStore.currentStreak == 1 ? "day" : "days")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                AppText("Best: {0} days", arguments: [String(describing: self.historyStore.bestStreak)])
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Transcriptions Card

    private var transcriptionsCard: some View {
        StatCard(title: AppLanguage.text("SESSIONS"), icon: "doc.text.fill") {
            VStack(alignment: .leading, spacing: 8) {
                AppText("{0}", arguments: [String(describing: self.historyStore.totalEntryCount)])
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)

                AppText("Avg: {0} words each", arguments: [String(describing: self.historyStore.averageWordsPerTranscription)])
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Activity Chart Card

    private var activityChartCard: some View {
        ThemedCard(style: .standard, padding: 16, hoverEffect: false) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    AppLabel("ACTIVITY", systemImage: "chart.bar.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)

                    Spacer()

                    Picker("", selection: self.$chartDays) {
                        AppText("7 days").tag(7)
                        AppText("30 days").tag(30)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 140)
                }

                let data = self.historyStore.dailyWordCounts(days: self.chartDays)
                let maxWords = data.map { $0.words }.max() ?? 0

                if maxWords == 0 {
                    // Empty state
                    HStack {
                        Spacer()
                        VStack(spacing: 8) {
                            Image(systemName: "chart.bar")
                                .font(.system(size: 24))
                                .foregroundStyle(.tertiary)
                            AppText("No activity yet")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 30)
                        Spacer()
                    }
                } else {
                    // Bar chart
                    HStack(alignment: .bottom, spacing: self.chartDays == 7 ? 8 : 2) {
                        ForEach(Array(data.enumerated()), id: \.offset) { index, item in
                            VStack(spacing: 4) {
                                // Bar (avoid division by zero)
                                let height = (item.words > 0 && maxWords > 0) ? CGFloat(item.words) / CGFloat(maxWords) *
                                    80 : 2
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(item.words > 0 ? self.theme.palette.accent : Color.secondary.opacity(0.2))
                                    .frame(width: self.chartDays == 7 ? 30 : 8, height: max(2, height))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 3)
                                            .stroke(self.hoveredActivityIndex == index ? self.theme.palette.accent.opacity(0.65) : Color.clear, lineWidth: 1)
                                    )
                                    .overlay(alignment: .top) {
                                        if self.hoveredActivityIndex == index {
                                            self.activityTooltip(for: item)
                                                .offset(y: -48)
                                                .zIndex(1)
                                        }
                                    }

                                // Label (only for 7-day view)
                                if self.chartDays == 7 {
                                    Text(self.dayLabel(item.date))
                                        .font(.system(size: 9, weight: .medium))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .contentShape(Rectangle())
                            .onHover { hovering in
                                self.hoveredActivityIndex = hovering ? index : nil
                            }
                        }
                    }
                    .frame(height: 110)
                    .frame(maxWidth: .infinity)

                    // Summary
                    HStack {
                        let totalPeriod = data.reduce(0) { $0 + $1.words }
                        let activeDays = data.filter { $0.words > 0 }.count

                        AppText("{0} words", arguments: [String(describing: self.formatNumber(totalPeriod))])
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.primary)

                        AppText("across {0} active days", arguments: [String(describing: activeDays)])
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)

                        Spacer()
                    }
                }
            }
        }
    }

    private func activityTooltip(for item: (date: Date, words: Int)) -> some View {
        VStack(spacing: 2) {
            Text(Self.activityTooltipDateFormatter.string(from: item.date))
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            AppText("{0} {1}", arguments: [String(describing: self.formatNumber(item.words)), String(describing: item.words == 1 ? "word" : "words")])
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(self.theme.palette.cardBackground)
                .shadow(color: .black.opacity(0.18), radius: 8, y: 3)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(self.theme.palette.cardBorder.opacity(0.6), lineWidth: 1)
        )
        .fixedSize()
        .allowsHitTesting(false)
    }

    // MARK: - Milestones Card

    private var milestonesCard: some View {
        ThemedCard(style: .standard, padding: 16, hoverEffect: false) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    AppLabel("MILESTONES", systemImage: "flag.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)

                    Spacer()

                    AppText("{0}/{1}", arguments: [String(describing: self.historyStore.totalMilestonesAchieved), String(describing: self.historyStore.totalMilestonesPossible)])
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(self.theme.palette.accent)
                }

                VStack(alignment: .leading, spacing: 10) {
                    // Word milestones
                    self.milestoneRow(
                        title: AppLanguage.text("Words"),
                        milestones: self.historyStore.wordMilestones
                    )

                    // Transcription milestones
                    self.milestoneRow(
                        title: AppLanguage.text("Sessions"),
                        milestones: self.historyStore.transcriptionMilestones
                    )

                    // Streak milestones
                    self.milestoneRow(
                        title: AppLanguage.text("Streak"),
                        milestones: self.historyStore.streakMilestones
                    )
                }
            }
        }
    }

    private func milestoneRow(title: String, milestones: [(target: Int, achieved: Bool, label: String)]) -> some View {
        HStack(spacing: 8) {
            AppText(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .leading)

            ForEach(Array(milestones.enumerated()), id: \.offset) { _, milestone in
                HStack(spacing: 3) {
                    Image(systemName: milestone.achieved ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 10))
                        .foregroundStyle(milestone.achieved ? self.theme.palette.success : Color.secondary.opacity(0.4))

                    Text(milestone.label)
                        .font(.system(size: 10, weight: milestone.achieved ? .semibold : .regular))
                        .foregroundStyle(milestone.achieved ? .primary : .secondary)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(milestone.achieved ? self.theme.palette.success.opacity(0.1) : Color.clear)
                )
            }

            Spacer()
        }
    }

    // MARK: - Insights Card

    private var insightsCard: some View {
        ThemedCard(style: .standard, padding: 16, hoverEffect: false) {
            VStack(alignment: .leading, spacing: 12) {
                AppLabel("INSIGHTS", systemImage: "lightbulb.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)

                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12),
                ], spacing: 12) {
                    // Top Apps
                    self.insightItem(
                        icon: "app.fill",
                        title: AppLanguage.text("Top Apps"),
                        value: self.historyStore.topAppsFormatted(limit: 3).joined(separator: ", "),
                        fallback: "No data yet"
                    )

                    // AI Enhancement Rate
                    self.insightItem(
                        icon: "sparkles",
                        title: AppLanguage.text("AI Enhanced"),
                        value: "\(self.historyStore.aiEnhancementRate)%",
                        fallback: "0%"
                    )

                    // Peak Hours
                    self.insightItem(
                        icon: "clock.fill",
                        title: AppLanguage.text("Peak Time"),
                        value: self.historyStore.peakHourFormatted,
                        fallback: "N/A"
                    )

                    // Avg Length
                    self.insightItem(
                        icon: "ruler.fill",
                        title: AppLanguage.text("Avg Length"),
                        value: "\(self.historyStore.averageWordsPerTranscription) words",
                        fallback: "0 words"
                    )
                }
            }
        }
    }

    private func insightItem(icon: String, title: String, value: String, fallback: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                AppText(title)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)

                Text(value.isEmpty ? fallback : value)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }

            Spacer()
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8)
            .fill(.quaternary.opacity(0.3)))
    }

    // MARK: - Personal Records Card

    private var recordsCard: some View {
        ThemedCard(style: .standard, padding: 16, hoverEffect: false) {
            VStack(alignment: .leading, spacing: 12) {
                AppLabel("PERSONAL RECORDS", systemImage: "trophy.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)

                HStack(spacing: 12) {
                    self.recordItem(
                        title: AppLanguage.text("Longest Session"),
                        value: "\(self.historyStore.longestTranscriptionWords) words"
                    )

                    self.recordItem(
                        title: AppLanguage.text("Most Words in a Day"),
                        value: "\(self.formatNumber(self.historyStore.mostWordsInDay)) words"
                    )

                    self.recordItem(
                        title: AppLanguage.text("Most in a Day"),
                        value: "\(self.historyStore.mostTranscriptionsInDay) sessions"
                    )
                }
            }
        }
    }

    private func recordItem(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            AppText(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)

            Text(value)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(self.theme.palette.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(self.theme.palette.cardBorder.opacity(0.45), lineWidth: 1)
                )
        )
    }

    // MARK: - Reset Section

    private var resetSection: some View {
        HStack {
            Spacer()

            Button {
                self.showResetConfirmation = true
            } label: {
                AppLabel("Reset All Stats", systemImage: "trash")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .opacity(self.historyStore.hasHistory ? 0.7 : 0.3)
            .disabled(!self.historyStore.hasHistory)

            Spacer()
        }
        .padding(.top, 8)
        .alert(AppLanguage.text("Reset All Stats"), isPresented: self.$showResetConfirmation) {
            AppButton("Cancel", role: .cancel) {}
            AppButton("Reset Everything", role: .destructive) {
                self.historyStore.clearAllHistory()
            }
        } message: {
            AppText("This will permanently delete all {0} sessions and reset all statistics. This action cannot be undone.", arguments: [String(describing: self.historyStore.totalEntryCount)])
        }
    }

    // MARK: - Helpers

    private func formatNumber(_ number: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: number)) ?? "\(number)"
    }

    private func dayLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return formatter.string(from: date)
    }
}

// MARK: - Stat Card Component

private struct StatCard<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: Content

    var body: some View {
        ThemedCard(style: .standard, padding: 16, hoverEffect: false) {
            VStack(alignment: .leading, spacing: 10) {
                Label(self.title, systemImage: self.icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)

                self.content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

#Preview {
    StatsView()
        .frame(width: 600, height: 800)
        .environment(\.theme, AppTheme.dark)
}
