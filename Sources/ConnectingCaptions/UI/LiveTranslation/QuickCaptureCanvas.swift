import AppKit
import Combine
import SwiftUI

/// Borderless chip for a Caption Listen shortcut that should not open Theater.
/// It does not take the keyboard and does not type into another app.
@MainActor
final class QuickCaptureController {
    static let shared = QuickCaptureController()

    private var panel: NSPanel?
    private let model = QuickCaptureModel()
    private var cancellables = Set<AnyCancellable>()
    private var failureToken = UUID()
    private var suppressFailure = false
    private var didPlace = false

    private init() {
        let translation = LiveTranslationController.shared
        translation.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refresh()
            }
            .store(in: &self.cancellables)
        translation.subscriber.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refresh()
            }
            .store(in: &self.cancellables)
    }

    func arm() {
        self.suppressFailure = false
        self.refresh()
    }

    private func refresh() {
        let translation = LiveTranslationController.shared
        let subscriber = translation.subscriber
        var content = QuickCaptureChipContent.make(
            committedLast: subscriber.committedLines.last,
            overlay: translation.overlayText,
            statusText: subscriber.statusText,
            statusKind: subscriber.statusKind
        )
        if self.suppressFailure {
            content.failure = ""
        }
        let shown = QuickCaptureVisibility.isShown(
            presentation: translation.captionPresentation,
            listenKind: translation.listenKind,
            isSessionActive: translation.isSessionActive,
            isFinishing: translation.isFinishingSession,
            hasFailure: content.isFailure
        )
        self.model.content = content
        self.model.isShown = shown
        guard shown else {
            self.panel?.orderOut(nil)
            self.didPlace = false
            return
        }
        let panel = self.ensurePanel()
        if !self.didPlace || !panel.isVisible {
            self.place(panel)
            self.didPlace = true
            panel.orderFrontRegardless()
        }
        if content.isFailure, !translation.isSessionActive {
            self.scheduleFailureDismiss()
        }
    }

    private func scheduleFailureDismiss() {
        let token = UUID()
        self.failureToken = token
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard self.failureToken == token else { return }
            guard !LiveTranslationController.shared.isSessionActive else { return }
            self.suppressFailure = true
            self.refresh()
        }
    }

    private func ensurePanel() -> NSPanel {
        if let panel = self.panel {
            return panel
        }
        let root = AdaptiveAppTheme(accent: SettingsStore.shared.accentColor) {
            QuickCaptureChip(model: self.model)
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
        let frames = NSScreen.screens.map(\.frame)
        let saved = SettingsStore.shared.quickCaptureOrigin
        let origin = QuickCapturePlacement.origin(
            saved: saved,
            mouse: NSEvent.mouseLocation,
            panelSize: panel.frame.size,
            screenFrames: frames
        )
        panel.setFrameOrigin(origin)
        if saved == nil {
            SettingsStore.shared.quickCaptureOrigin = origin
        }
    }
}

enum QuickCapturePlacement {
    static func origin(
        saved: CGPoint?,
        mouse: CGPoint,
        panelSize: CGSize,
        screenFrames: [CGRect]
    ) -> CGPoint {
        if let saved, self.screen(containing: saved, in: screenFrames) != nil {
            return saved
        }
        let screen = self.screen(containing: mouse, in: screenFrames) ?? screenFrames.first
        let proposed = CGPoint(
            x: mouse.x - panelSize.width / 2,
            y: mouse.y - panelSize.height - 12
        )
        guard let screen else { return proposed }
        return self.clamp(proposed, into: screen, panelSize: panelSize)
    }

    private static func screen(containing point: CGPoint, in frames: [CGRect]) -> CGRect? {
        frames.first { $0.contains(point) }
    }

    private static func clamp(_ origin: CGPoint, into screen: CGRect, panelSize: CGSize) -> CGPoint {
        let maxX = max(screen.minX, screen.maxX - panelSize.width)
        let maxY = max(screen.minY, screen.maxY - panelSize.height)
        return CGPoint(
            x: min(max(origin.x, screen.minX), maxX),
            y: min(max(origin.y, screen.minY), maxY)
        )
    }
}

@MainActor
final class QuickCaptureModel: ObservableObject {
    @Published var content = QuickCaptureChipContent(finished: "", live: "", failure: "")
    @Published var isShown = false
}

private struct QuickCaptureChip: View {
    @ObservedObject var model: QuickCaptureModel

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if !self.model.content.finished.isEmpty, self.model.content.failure.isEmpty {
                Text(self.model.content.finished)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.55))
                    .lineLimit(1)
                    .truncationMode(.head)
            }
            Text(self.visibleLine)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.white)
                .lineLimit(2)
                .truncationMode(.head)
                .shadow(color: .black.opacity(0.9), radius: 2, y: 1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(width: 460, height: 84, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.black.opacity(0.82))
        }
        .padding(18)
        .frame(width: 496, height: 120)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("theater.quickCapture")
        .accessibilityLabel(AppLanguage.text("Quick capture"))
        .accessibilityValue(self.accessibilityValue)
    }

    private var visibleLine: String {
        if self.model.content.isFailure {
            return self.model.content.failure
        }
        if !self.model.content.live.isEmpty {
            return self.model.content.live
        }
        return AppLanguage.text("Listening")
    }

    private var accessibilityValue: String {
        if self.model.content.isFailure {
            return self.model.content.failure
        }
        let parts = [self.model.content.finished, self.visibleLine].filter { !$0.isEmpty }
        return parts.joined(separator: " ")
    }
}
