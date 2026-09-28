import AppKit
import Combine
import SwiftUI

/// Bottom bar for Listen, then type.
/// It shows the line that will be typed and does not take the keyboard,
/// so the app captured at the start of the shortcut stays focused.
@MainActor
final class QuickTranslateInsertController {
    private static var existing: QuickTranslateInsertController?

    private var panel: NSPanel?
    private var session = QuickTranslateInsertSession()
    private let model = QuickTranslateInsertModel()
    private var cancellables = Set<AnyCancellable>()
    private var noticeToken = UUID()

    static func arm() {
        let controller = Self.controller
        controller.noticeToken = UUID()
        controller.model.notice = ""
        controller.session.armed = true
        controller.refresh()
    }

    /// Keep a start failure on the bar. Hiding immediately leaves the other app
    /// with no explanation.
    static func presentNotice(_ message: String) {
        let controller = Self.controller
        controller.session.disarm()
        let text = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            controller.model.notice = ""
            controller.refresh()
            return
        }
        let token = UUID()
        controller.noticeToken = token
        controller.model.notice = text
        controller.apply(.starting)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard controller.noticeToken == token else { return }
            controller.model.notice = ""
            controller.refresh()
        }
    }

    static func disarmIfNeeded() {
        guard let existing = Self.existing else { return }
        existing.noticeToken = UUID()
        existing.model.notice = ""
        existing.session.disarm()
        existing.refresh()
    }

    private static var controller: QuickTranslateInsertController {
        if let existing = Self.existing {
            return existing
        }
        let created = QuickTranslateInsertController()
        Self.existing = created
        return created
    }

    private init() {
        let translation = LiveTranslationController.shared
        translation.$isSessionActive
            .combineLatest(translation.$listenKind, translation.$isFinishingSession)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _, _, _ in
                self?.refresh()
            }
            .store(in: &self.cancellables)
    }

    private func refresh() {
        if !self.model.notice.isEmpty {
            self.apply(.starting)
            return
        }
        let translation = LiveTranslationController.shared
        let phase = self.session.note(
            listenKind: translation.listenKind,
            isSessionActive: translation.isSessionActive,
            isFinishing: translation.isFinishingSession
        )
        self.apply(phase)
    }

    private func apply(_ phase: QuickTranslateInsertPhase) {
        let wasHidden = self.model.phase == .hidden
        self.model.phase = phase
        guard phase != .hidden else {
            self.panel?.orderOut(nil)
            return
        }
        let panel = self.ensurePanel()
        if wasHidden || !panel.isVisible {
            self.place(panel)
            panel.orderFrontRegardless()
        }
    }

    private func ensurePanel() -> NSPanel {
        if let panel = self.panel {
            return panel
        }
        let root = AdaptiveAppTheme(accent: SettingsStore.shared.accentColor) {
            QuickTranslateInsertPill(model: self.model)
        }
        let hosting = NSHostingView(rootView: root)
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = .clear
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 496, height: 120),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.isMovable = false
        panel.ignoresMouseEvents = true
        panel.contentView = hosting
        TheaterWindowSharing.apply(panel)
        self.panel = panel
        return panel
    }

    private func place(_ panel: NSPanel) {
        guard let screen = OverlayScreenResolver.screenForCurrentPointer() else { return }
        let visible = screen.visibleFrame
        let size = panel.frame.size
        let origin = NSPoint(
            x: visible.midX - size.width / 2,
            y: visible.minY + 28
        )
        panel.setFrameOrigin(origin)
    }
}

@MainActor
final class QuickTranslateInsertModel: ObservableObject {
    @Published var phase: QuickTranslateInsertPhase = .hidden
    @Published var notice = ""
}

private struct QuickTranslateInsertPill: View {
    @ObservedObject var model: QuickTranslateInsertModel
    /// The subscriber, not the session flag. Stop clears the session before
    /// the last Show-as line lands, and the bar still has to show that line.
    @ObservedObject private var subscriber = LiveTranslationController.shared.subscriber
    @ObservedObject private var settings = SettingsStore.shared
    @State private var bars: [CGFloat] = Array(repeating: 0.16, count: 7)

    var body: some View {
        let chip = self.chip
        HStack(alignment: .center, spacing: 14) {
            self.waveform
            VStack(alignment: .leading, spacing: 3) {
                Text(chip.title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.62))
                    .lineLimit(1)
                Text(chip.line)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(chip.lineIsReady ? Color.white : Color.white.opacity(0.72))
                    .lineLimit(2)
                    .truncationMode(.head)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(width: 460, height: 84, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.black.opacity(0.86))
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(self.settings.accentColor.opacity(0.85), lineWidth: 1.5)
                }
        }
        .padding(18)
        .shadow(color: .black.opacity(0.28), radius: 16, y: 8)
        .frame(width: 496, height: 120)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("theater.quickInsert")
        .accessibilityLabel(chip.title)
        .accessibilityValue(chip.line)
        .onReceive(AppServices.shared.asr.audioLevelPublisher) { level in
            guard self.model.phase == .listening else { return }
            self.push(level)
        }
        .onChange(of: self.model.phase) { _, phase in
            if phase != .listening {
                self.bars = Array(repeating: 0.16, count: 7)
            }
        }
    }

    private func barHeight(_ index: Int) -> CGFloat {
        guard self.bars.indices.contains(index) else { return 4 }
        return max(4, self.bars[index] * 28)
    }

    private var chip: QuickTranslateInsertChip {
        let source = SpokenLanguageResolver.sourceLanguage()
        let target = SpokenLanguageResolver.targetLanguage()
        if !self.model.notice.isEmpty {
            return QuickTranslateInsertChip(
                title: QuickTranslateInsert.pairTitle(
                    sourceName: source.displayName,
                    targetName: target.displayName,
                    sameLanguage: SpokenLanguageResolver.isSameLanguagePair()
                ),
                line: self.model.notice,
                lineIsReady: false
            )
        }
        return QuickTranslateInsert.chip(
            phase: self.model.phase,
            activation: self.settings.hotkeyMode,
            sourceName: source.displayName,
            targetName: target.displayName,
            sameLanguage: SpokenLanguageResolver.isSameLanguagePair(),
            ready: self.subscriber.pendingInsertDocument(),
            showAs: self.subscriber.liveCaptionText,
            spoken: self.subscriber.liveSpokenText
        )
    }

    private var waveform: some View {
        HStack(alignment: .center, spacing: 3) {
            ForEach(0..<7, id: \.self) { index in
                Capsule()
                    .fill(self.settings.accentColor)
                    .frame(width: 3, height: self.barHeight(index))
            }
        }
        .frame(width: 42, height: 28)
        .accessibilityHidden(true)
    }

    private func push(_ level: CGFloat) {
        let clamped = min(1, max(0, level))
        var next = self.bars
        if !next.isEmpty {
            next.removeFirst()
        }
        next.append(max(0.16, clamped))
        self.bars = next
    }
}
