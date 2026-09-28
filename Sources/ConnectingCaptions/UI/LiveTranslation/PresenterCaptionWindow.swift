import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class PresenterCaptionController: NSObject, NSWindowDelegate {
    static let shared = PresenterCaptionController()

    private var panel: NSPanel?
    private let model = PresenterCaptionModel()
    private var lastExternalAppPID: pid_t?

    private var isDismissing = false
    private var settingsCancellables = Set<AnyCancellable>()
    private var appliedWindowStyle: (presentation: String, captionsOnly: Bool)?
    private var persistFrameWork: DispatchWorkItem?
    /// Polls the pointer while idle Overlay clicks through. SwiftUI hover cannot
    /// see the cursor until this window accepts events again.
    private var overlayHoverTimer: Timer?

    func setVisible(_ visible: Bool) {
        if visible {
            self.show()
        } else {
            self.hide()
        }
    }

    func show() {
        guard TheaterAvailability.isSupported else {
            SettingsStore.shared.theaterWindowEnabled = false
            LiveTranslationController.shared.reportListenFailure(TheaterAvailability.unsupportedCopy)
            return
        }
        SettingsStore.shared.theaterWindowEnabled = true
        LiveTranslationController.shared.restoreBoardIfNeeded()
        if self.panel == nil {
            self.panel = Self.makePanel(model: self.model)
            self.panel?.delegate = self
        }
        let wasMinimized = SettingsStore.shared.theaterMinimized
        SettingsStore.shared.theaterMinimized = false
        self.observeSettings()
        self.applyWindowSharing()
        self.applyPresentationStyle()
        if wasMinimized {
            self.applyMinimizedLayout()
        } else {
            self.restoreFrame()
        }
        self.rememberExternalApp()
        self.updateOverlayPlacementGate()
        self.applyOverlayPin()
        if TheaterMinimize.shouldOrderFront(minimized: SettingsStore.shared.theaterMinimized) {
            self.panel?.orderFront(nil)
        }
        LiveTranslationController.shared.syncTheater()
    }

    func hide() {
        self.panel?.orderOut(nil)
        self.dismissCaptions()
    }

    func orderOutIfClosed() {
        guard !SettingsStore.shared.theaterWindowEnabled else { return }
        self.panel?.orderOut(nil)
    }

    func clearDisplay() {
        self.model.board = TheaterBoardState()
        self.model.status = ""
        self.model.statusKind = .idle
        self.model.canRetryTranslation = false
        self.model.latencyReadout = ""
        self.model.compactLatencyReadout = ""
        self.model.paceCueLabel = ""
        self.model.paceCueCompactLabel = ""
        self.model.paceCueKind = ""
        self.model.inboxLines = []
    }

    func update(
        board: TheaterBoardState,
        pairLabel: String,
        status: String,
        statusKind: TheaterStatusKind = .idle,
        isListening: Bool,
        isPaused: Bool = false,
        canRetryTranslation: Bool = false,
        latencyReadout: String = "",
        compactLatencyReadout: String = "",
        paceCue: TheaterPaceCue.Snapshot? = nil,
        inboxLines: [String] = []
    ) {
        if self.model.board != board { self.model.board = board }
        if self.model.pairLabel != pairLabel { self.model.pairLabel = pairLabel }
        if self.model.status != status { self.model.status = status }
        if self.model.statusKind != statusKind { self.model.statusKind = statusKind }
        if self.model.isListening != isListening { self.model.isListening = isListening }
        if self.model.isPaused != isPaused { self.model.isPaused = isPaused }
        if self.model.canRetryTranslation != canRetryTranslation {
            self.model.canRetryTranslation = canRetryTranslation
        }
        if self.model.latencyReadout != latencyReadout {
            self.model.latencyReadout = latencyReadout
        }
        if self.model.compactLatencyReadout != compactLatencyReadout {
            self.model.compactLatencyReadout = compactLatencyReadout
        }
        let paceLabel = paceCue?.label ?? ""
        let paceCompact = paceCue?.compactLabel ?? ""
        let paceKind = paceCue?.kind.rawValue ?? ""
        if self.model.paceCueLabel != paceLabel {
            self.model.paceCueLabel = paceLabel
        }
        if self.model.paceCueCompactLabel != paceCompact {
            self.model.paceCueCompactLabel = paceCompact
        }
        if self.model.paceCueKind != paceKind {
            self.model.paceCueKind = paceKind
        }
        if self.model.inboxLines != inboxLines {
            self.model.inboxLines = inboxLines
        }
    }

    func documentTextForDelivery() -> String {
        Self.captionDocument(committed: self.model.board.translatedLines, draft: "")
    }

    /// Same answer as `documentTextForDelivery().isEmpty` without joining the board.
    var hasDeliverableText: Bool {
        !self.model.board.isEmpty
    }

    func makeKeyForInteraction() {
        self.rememberExternalApp()
        self.panel?.makeKeyAndOrderFront(nil)
    }

    func releaseKeyToExternalApp() {
        self.panel?.resignKey()
        if let pid = self.lastExternalAppPID {
            TypingService.activateApp(pid: pid)
        }
    }

    func performChromeAction(_ action: () -> Void) {
        self.makeKeyForInteraction()
        action()
        self.scheduleReleaseKeyToExternalApp()
    }

    func scheduleReleaseKeyToExternalApp() {
        DispatchQueue.main.async { [weak self] in
            self?.releaseKeyToExternalApp()
        }
    }

    func requestClose() {
        if self.shouldConfirmCloseWhileListening {
            self.model.showCloseConfirmation = true
            self.makeKeyForInteraction()
            return
        }
        self.setVisible(false)
    }

    func confirmCloseWhileListening() {
        self.model.showCloseConfirmation = false
        self.setVisible(false)
    }

    func cancelCloseWhileListening() {
        self.model.showCloseConfirmation = false
        self.scheduleReleaseKeyToExternalApp()
    }

    var shouldConfirmCloseWhileListening: Bool {
        LiveTranslationController.shared.isSessionActive
            && LiveTranslationController.shared.listenKind == .captions
    }

    func toggleMinimized() {
        let settings = SettingsStore.shared
        if let panel = self.panel, panel.isVisible, !settings.theaterMinimized {
            settings.theaterExpandedWindowFrame = NSStringFromRect(panel.frame)
            settings.theaterWindowFrame = NSStringFromRect(panel.frame)
        }
        settings.theaterMinimized.toggle()
        if TheaterOverlayPolicy.shouldClearPin(
            presentation: settings.theaterPresentation,
            minimized: settings.theaterMinimized,
            windowEnabled: settings.theaterWindowEnabled
        ) {
            self.model.overlayToolsPinned = false
        }
        self.applyMinimizedLayout()
        self.applyOverlayPin()
        if TheaterMinimize.shouldOrderFront(minimized: settings.theaterMinimized) {
            self.panel?.orderFront(nil)
        }
    }

    func preferredInsertTargetPID() -> pid_t? {
        if let pid = self.lastExternalAppPID, pid > 0 { return pid }
        let front = NSWorkspace.shared.frontmostApplication
        if front?.bundleIdentifier != Bundle.main.bundleIdentifier {
            return front?.processIdentifier
        }
        return nil
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if self.shouldConfirmCloseWhileListening {
            self.model.showCloseConfirmation = true
            self.makeKeyForInteraction()
            return false
        }
        return true
    }

    func windowWillClose(_ notification: Notification) {
        self.persistFrame()
        self.dismissCaptions()
    }

    func windowDidMove(_ notification: Notification) {
        self.refreshPlacementConfirmation()
        self.schedulePersistFrame()
    }

    func windowDidResize(_ notification: Notification) {
        self.refreshPlacementConfirmation()
        guard !(self.panel?.inLiveResize ?? false) else { return }
        self.schedulePersistFrame()
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        self.refreshPlacementConfirmation()
        self.schedulePersistFrame()
    }

    /// Drags fire many move events; write settings once the window settles.
    private func schedulePersistFrame() {
        self.persistFrameWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.persistFrame() }
        self.persistFrameWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }

    private func dismissCaptions() {
        guard !self.isDismissing else { return }
        self.isDismissing = true
        SettingsStore.shared.theaterWindowEnabled = false
        SettingsStore.shared.theaterMinimized = false
        self.model.overlayToolsPinned = false
        self.model.isPlacingOverlay = false
        self.model.canConfirmOverlayPlacement = false
        self.applyOverlayPin()
        LiveTranslationController.shared.theaterWasClosed()
        self.isDismissing = false
    }

    func windowDidBecomeKey(_ notification: Notification) {
        self.rememberExternalApp()
    }

    static func captionDocument(committed: [String], draft: String) -> String {
        var lines = committed
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let current = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        if !current.isEmpty, lines.last != current {
            lines.append(current)
        }
        return lines.joined(separator: "\n")
    }

    private func rememberExternalApp() {
        let front = NSWorkspace.shared.frontmostApplication
        if let pid = front?.processIdentifier,
           front?.bundleIdentifier != Bundle.main.bundleIdentifier
        {
            self.lastExternalAppPID = pid
        }
    }

    private func observeSettings() {
        guard self.settingsCancellables.isEmpty else { return }
        SettingsStore.shared.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    self?.applyWindowStyleIfChanged()
                }
            }
            .store(in: &self.settingsCancellables)
        NotificationCenter.default
            .publisher(for: NSApplication.didChangeScreenParametersNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refitAfterScreenChange()
            }
            .store(in: &self.settingsCancellables)
        NotificationCenter.default
            .publisher(for: NSApplication.didBecomeActiveNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.applyOverlayPin()
                self?.lowerPopupIfAppWindowBecameKey(NSApp.keyWindow)
            }
            .store(in: &self.settingsCancellables)
        NotificationCenter.default
            .publisher(for: NSApplication.didResignActiveNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.applyOverlayPin()
            }
            .store(in: &self.settingsCancellables)
        NotificationCenter.default
            .publisher(for: NSWindow.didBecomeKeyNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                self?.lowerPopupIfAppWindowBecameKey(notification.object as? NSWindow)
            }
            .store(in: &self.settingsCancellables)
        self.model.$overlayDockHeight
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    self?.refreshOverlayHoverCapture()
                }
            }
            .store(in: &self.settingsCancellables)
        self.model.$overlayDockHolding
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    self?.refreshOverlayHoverCapture()
                }
            }
            .store(in: &self.settingsCancellables)
    }

    /// Pop-up shares the normal window stack. When Home or Settings becomes
    /// key, send the board behind that window so it does not cover Setup.
    private func lowerPopupIfAppWindowBecameKey(_ window: NSWindow?) {
        guard let window,
              window !== self.panel,
              window.isVisible,
              SettingsStore.shared.theaterPresentation == .popup,
              let panel = self.panel,
              panel.isVisible
        else { return }
        panel.order(.below, relativeTo: window.windowNumber)
    }

    private func applyWindowStyleIfChanged() {
        let settings = SettingsStore.shared
        let current = (
            presentation: "\(settings.theaterPresentation)",
            captionsOnly: settings.theaterHideChrome
        )
        let presentationChanged = self.appliedWindowStyle?.presentation != current.presentation
        if let applied = self.appliedWindowStyle, applied == current { return }
        if settings.theaterPresentation == .popup {
            self.model.overlayToolsPinned = false
            self.model.isPlacingOverlay = false
            self.model.canConfirmOverlayPlacement = false
        }
        self.applyWindowSharing()
        self.applyPresentationStyle()
        if presentationChanged, self.panel?.isVisible == true, !settings.theaterMinimized {
            self.refitAfterPresentationChange()
        } else {
            self.updateOverlayPlacementGate()
            self.applyOverlayPin()
        }
    }

    /// Overlay and Pop-up resolve empty / leftover frames differently.
    private func refitAfterPresentationChange() {
        guard let panel = self.panel else { return }
        let screen = panel.screen ?? Self.preferredScreen()
        guard let screen else { return }
        Self.place(
            panel,
            stored: panel.frame,
            on: screen,
            placing: self.model.isPlacingOverlay
        )
        self.updateOverlayPlacementGate()
        self.applyOverlayPin()
    }

    var overlayToolsPinned: Bool { self.model.overlayToolsPinned }

    func toggleOverlayToolsPinned() {
        let settings = SettingsStore.shared
        guard settings.theaterWindowEnabled,
              settings.theaterPresentation == .transparent,
              !settings.theaterMinimized
        else { return }
        self.model.overlayToolsPinned.toggle()
        self.applyOverlayPin()
        if self.model.overlayToolsPinned {
            settings.theaterOverlayCoachSeen = true
            self.panel?.orderFront(nil)
        }
    }

    /// Saves the rectangle under the pointer and enters click-through Overlay.
    func confirmOverlayPlacement() {
        guard self.model.isPlacingOverlay, let panel = self.panel, panel.isVisible else { return }
        let screen = panel.screen ?? Self.preferredScreen()
        guard let screen else { return }
        guard !TheaterWindowPlacement.needsOverlayPlacement(
            stored: panel.frame,
            visible: screen.visibleFrame
        ) else {
            self.refreshPlacementConfirmation()
            return
        }
        self.model.isPlacingOverlay = false
        self.model.canConfirmOverlayPlacement = false
        self.persistFrame()
        self.applyOverlayPin()
    }

    private func updateOverlayPlacementGate() {
        let settings = SettingsStore.shared
        guard settings.theaterPresentation == .transparent,
              !settings.theaterMinimized,
              settings.theaterWindowEnabled,
              let panel = self.panel,
              let screen = panel.screen ?? Self.preferredScreen()
        else {
            if self.model.isPlacingOverlay {
                self.model.isPlacingOverlay = false
            }
            self.refreshPlacementConfirmation()
            return
        }
        if self.model.isPlacingOverlay {
            self.refreshPlacementConfirmation()
            return
        }
        let decision = TheaterWindowPlacement.overlayFrameDecision(
            stored: panel.frame,
            saved: Self.savedOverlayFrame(),
            visible: screen.visibleFrame,
            preset: settings.theaterPositionPreset,
            placing: false
        )
        if decision.needsPlacement {
            self.model.isPlacingOverlay = true
        }
        self.refreshPlacementConfirmation()
    }

    private func refreshPlacementConfirmation() {
        let next: Bool
        if self.model.isPlacingOverlay,
           let panel = self.panel,
           let screen = panel.screen ?? Self.preferredScreen()
        {
            next = !TheaterWindowPlacement.needsOverlayPlacement(
                stored: panel.frame,
                visible: screen.visibleFrame
            )
        } else {
            next = false
        }
        if self.model.canConfirmOverlayPlacement != next {
            self.model.canConfirmOverlayPlacement = next
        }
    }

    private static func savedOverlayFrame() -> CGRect? {
        let stored = SettingsStore.shared.theaterOverlayFrame
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !stored.isEmpty else { return nil }
        let rect = NSRectFromString(stored)
        guard rect.width > 200, rect.height > 80 else { return nil }
        return rect
    }

    /// Idle Overlay clicks through, so the tool bar cannot use SwiftUI hover.
    /// The pointer is sampled while that window is up, and only the bar's rect
    /// accepts clicks. A faded bar stays a thin strip so captions underneath
    /// still reach the slides.
    private func refreshOverlayHoverCapture() {
        guard let panel = self.panel else {
            self.updateOverlayHoverTimer(running: false)
            return
        }
        let settings = SettingsStore.shared
        let idle = panel.isVisible
            && !settings.theaterMinimized
            && TheaterOverlayPolicy.hidesAllChrome(
                presentation: settings.theaterPresentation,
                toolsPinned: self.model.overlayToolsPinned,
                placing: self.model.isPlacingOverlay
            )
        self.updateOverlayHoverTimer(running: idle)
        let inside = idle && self.overlayPointerInHoverDock(panel: panel)
        if self.model.overlayDockEngaged != inside {
            self.model.overlayDockEngaged = inside
            if inside, !settings.theaterOverlayCoachSeen {
                settings.theaterOverlayCoachSeen = true
            }
        }
        let ignore = TheaterOverlayPolicy.ignoresMouseEvents(
            presentation: settings.theaterPresentation,
            toolsPinned: self.model.overlayToolsPinned,
            minimized: settings.theaterMinimized,
            placing: self.model.isPlacingOverlay,
            pointerInHoverDock: inside
        )
        if panel.ignoresMouseEvents != ignore {
            panel.ignoresMouseEvents = ignore
        }
    }

    private func overlayPointerInHoverDock(panel: NSPanel) -> Bool {
        if self.model.overlayDockHolding { return true }
        if NSEvent.pressedMouseButtons != 0, self.model.overlayDockEngaged {
            return true
        }
        let open = TheaterOverlayPolicy.showsHoverDock(
            engaged: self.model.overlayDockEngaged,
            holding: self.model.overlayDockHolding
        )
        let height = open ? self.model.overlayDockHeight : 0
        return TheaterOverlayPolicy.hoverDockContains(
            NSEvent.mouseLocation,
            windowFrame: panel.frame,
            contentHeight: height
        )
    }

    private func updateOverlayHoverTimer(running: Bool) {
        if running {
            guard self.overlayHoverTimer == nil else { return }
            let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.refreshOverlayHoverCapture()
                }
            }
            RunLoop.main.add(timer, forMode: .common)
            self.overlayHoverTimer = timer
            return
        }
        self.overlayHoverTimer?.invalidate()
        self.overlayHoverTimer = nil
    }

    private func applyOverlayPin() {
        guard let panel = self.panel else { return }
        let settings = SettingsStore.shared
        let presentation = settings.theaterPresentation
        let pinned = self.model.overlayToolsPinned
        let minimized = settings.theaterMinimized
        let placing = self.model.isPlacingOverlay
        self.refreshOverlayHoverCapture()
        panel.isMovableByWindowBackground = TheaterOverlayPolicy.movableByBackground(
            presentation: presentation,
            toolsPinned: pinned,
            minimized: minimized,
            placing: placing
        )
        let hideButtons = TheaterOverlayPolicy.hidesTitlebarButtons(
            presentation: presentation,
            toolsPinned: pinned,
            hideChrome: settings.theaterHideChrome,
            placing: placing
        )
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            guard let control = panel.standardWindowButton(button) else { continue }
            control.isHidden = hideButtons
            control.alphaValue = hideButtons ? 0 : 1
        }
        panel.minSize = TheaterOverlayPolicy.minSize(for: presentation)
        let showShadow = placing || TheaterOverlayPolicy.showsWindowShadow(presentation: presentation)
        panel.hasShadow = showShadow
        if showShadow {
            panel.invalidateShadow()
        }
        let appIsActive = NSApp.isActive
        panel.level = TheaterOverlayPolicy.windowLevel(
            presentation: presentation,
            appIsActive: appIsActive
        )
        panel.isFloatingPanel = TheaterOverlayPolicy.isFloatingPanel(
            presentation: presentation,
            appIsActive: appIsActive
        )
    }

    /// A projector unplugged mid-talk must not strand captions off-screen.
    private func refitAfterScreenChange() {
        guard let panel = self.panel, panel.isVisible else { return }
        let onScreen = NSScreen.screens.contains { $0.visibleFrame.intersects(panel.frame) }
        let screen = onScreen ? (panel.screen ?? Self.preferredScreen()) : Self.preferredScreen()
        guard let screen else { return }
        let stored = onScreen ? panel.frame : nil
        let keepUserSize = onScreen && SettingsStore.shared.theaterPositionPreset == nil
        Self.place(
            panel,
            stored: stored,
            on: screen,
            keepUserSize: keepUserSize,
            placing: self.model.isPlacingOverlay
        )
        self.updateOverlayPlacementGate()
        self.applyOverlayPin()
    }

    private func applyWindowSharing() {
        guard let panel = self.panel else { return }
        TheaterWindowSharing.apply(panel)
        self.appliedWindowStyle = (
            presentation: "\(SettingsStore.shared.theaterPresentation)",
            captionsOnly: SettingsStore.shared.theaterHideChrome
        )
    }

    private func applyPresentationStyle() {
        guard let panel = self.panel else { return }
        self.appliedWindowStyle = (
            presentation: "\(SettingsStore.shared.theaterPresentation)",
            captionsOnly: SettingsStore.shared.theaterHideChrome
        )
        let presentation = SettingsStore.shared.theaterPresentation
        if presentation == .popup {
            self.model.overlayToolsPinned = false
            self.model.isPlacingOverlay = false
            self.model.canConfirmOverlayPlacement = false
        }
        let showShadow = self.model.isPlacingOverlay
            || TheaterOverlayPolicy.showsWindowShadow(presentation: presentation)
        panel.hasShadow = showShadow
        if showShadow {
            panel.invalidateShadow()
        }
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.minSize = TheaterOverlayPolicy.minSize(for: presentation)
        self.applyOverlayPin()
    }

    private final class TheaterCaptionPanel: NSPanel {
        override func miniaturize(_ sender: Any?) {
            PresenterCaptionController.shared.toggleMinimized()
        }
    }

    private static func makePanel(model: PresenterCaptionModel) -> NSPanel {
        let view = PresenterCaptionView(model: model)
        let hosting = NSHostingController(rootView: view)
        hosting.sizingOptions = []
        hosting.safeAreaRegions = []
        hosting.view.autoresizingMask = [.width, .height]
        let panel = TheaterCaptionPanel(
            contentRect: NSRect(x: 80, y: 80, width: 1100, height: 440),
            styleMask: [
                .titled,
                .closable,
                .miniaturizable,
                .resizable,
                .fullSizeContentView,
                .nonactivatingPanel,
            ],
            backing: .buffered,
            defer: false
        )
        panel.title = "\(ConnectingCaptionsProduct.displayName) Theater"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.hidesOnDeactivate = false
        let createdPresentation = SettingsStore.shared.theaterPresentation
        let appIsActive = NSApp.isActive
        panel.isFloatingPanel = TheaterOverlayPolicy.isFloatingPanel(
            presentation: createdPresentation,
            appIsActive: appIsActive
        )
        panel.level = TheaterOverlayPolicy.windowLevel(
            presentation: createdPresentation,
            appIsActive: appIsActive
        )
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.contentViewController = hosting
        panel.minSize = TheaterOverlayPolicy.minSize(for: SettingsStore.shared.theaterPresentation)
        TheaterWindowSharing.apply(panel)
        if let screen = Self.preferredScreen() {
            Self.place(panel, stored: nil, on: screen)
        } else {
            panel.setContentSize(TheaterWindowPlacement.legacyDefaultSize)
        }
        return panel
    }

    /// Pop-up opens as a lower third unless a position or a saved size is set.
    /// Overlay uses a kept rectangle, or stays put for placement.
    private static func place(
        _ panel: NSPanel,
        stored: CGRect?,
        on screen: NSScreen,
        keepUserSize: Bool = false,
        animate: Bool = false,
        placing: Bool = false
    ) {
        let presentation = SettingsStore.shared.theaterPresentation
        if presentation == .popup {
            panel.setFrame(
                TheaterWindowPlacement.resolvedPopupFrame(
                    stored: stored,
                    visible: screen.visibleFrame,
                    keepUserSize: keepUserSize,
                    preset: SettingsStore.shared.theaterPositionPreset
                ),
                display: true,
                animate: animate
            )
            return
        }
        let decision = TheaterWindowPlacement.overlayFrameDecision(
            stored: stored,
            saved: Self.savedOverlayFrame(),
            visible: screen.visibleFrame,
            preset: SettingsStore.shared.theaterPositionPreset,
            placing: placing
        )
        panel.setFrame(decision.frame, display: true, animate: animate)
    }

    private func persistFrame() {
        guard let panel = self.panel, panel.isVisible else { return }
        guard !self.model.isPlacingOverlay else { return }
        SettingsStore.shared.theaterScreenName = panel.screen.map(Self.screenKey) ?? ""
        if SettingsStore.shared.theaterMinimized {
            return
        }
        if let preset = SettingsStore.shared.theaterPositionPreset,
           let screen = panel.screen,
           !TheaterWindowPlacement.isClose(panel.frame, preset.frame(in: screen.visibleFrame))
        {
            SettingsStore.shared.theaterPositionPreset = nil
        }
        let frame = NSStringFromRect(panel.frame)
        SettingsStore.shared.theaterWindowFrame = frame
        SettingsStore.shared.theaterExpandedWindowFrame = frame
        if SettingsStore.shared.theaterPresentation == .transparent {
            SettingsStore.shared.theaterOverlayFrame = frame
        }
    }

    private func applyMinimizedLayout() {
        guard let panel = self.panel else { return }
        if SettingsStore.shared.theaterMinimized {
            if panel.isVisible {
                SettingsStore.shared.theaterExpandedWindowFrame = NSStringFromRect(panel.frame)
                SettingsStore.shared.theaterWindowFrame = NSStringFromRect(panel.frame)
            }
            panel.orderOut(nil)
            return
        }
        let presentation = SettingsStore.shared.theaterPresentation
        panel.minSize = TheaterOverlayPolicy.minSize(for: presentation)
        let screen = panel.screen ?? Self.preferredScreen()
        let stored = SettingsStore.shared.theaterExpandedWindowFrame
        let storedRect = stored.isEmpty ? nil : NSRectFromString(stored)
        if let screen {
            Self.place(
                panel,
                stored: storedRect,
                on: screen,
                keepUserSize: true,
                placing: self.model.isPlacingOverlay
            )
            return
        }
        var frame = panel.frame
        let minHeight = TheaterOverlayPolicy.minSize(for: presentation).height
        if frame.height < minHeight {
            let height = presentation == .transparent
                ? TheaterPositionPreset.captionBarHeight
                : TheaterWindowPlacement.legacyDefaultSize.height
            frame.origin.y -= height - frame.height
            frame.size.height = height
            panel.setFrame(frame, display: true)
        }
    }

    private func restoreFrame() {
        let stored = SettingsStore.shared.theaterWindowFrame
        let storedRect = stored.isEmpty ? nil : NSRectFromString(stored)
        let screen = Self.screen(named: SettingsStore.shared.theaterScreenName) ?? Self.preferredScreen()
        if let screen, let panel = self.panel {
            Self.place(panel, stored: storedRect, on: screen)
        } else if let storedRect, storedRect.width > 200, storedRect.height > 160 {
            self.panel?.setFrame(storedRect, display: true)
        }
    }

    private static func preferredScreen() -> NSScreen? {
        if let named = Self.screen(named: SettingsStore.shared.theaterScreenName) {
            return named
        }
        return NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) }
            ?? NSScreen.main
            ?? NSScreen.screens.first
    }

    /// Snap the board to a preset on the display it is on now.
    func applyPositionPreset(_ preset: TheaterPositionPreset) {
        guard let panel = self.panel else { return }
        guard let screen = panel.screen ?? Self.preferredScreen() else { return }
        let resolved = preset.resolved(for: SettingsStore.shared.theaterPresentation)
        SettingsStore.shared.theaterPositionPreset = resolved
        panel.setFrame(resolved.frame(in: screen.visibleFrame), display: true, animate: true)
        self.refreshPlacementConfirmation()
        self.schedulePersistFrame()
    }

    /// "Name|displayID" so two identical monitors stay distinct. Older
    /// values are a bare name and still match by name.
    private static func screenKey(_ screen: NSScreen) -> String {
        guard let id = Self.displayID(screen) else { return screen.localizedName }
        return "\(screen.localizedName)|\(id)"
    }

    private static func displayID(_ screen: NSScreen) -> UInt32? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }

    private static func screen(named key: String) -> NSScreen? {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let parts = trimmed.split(separator: "|", maxSplits: 1).map(String.init)
        if parts.count == 2, let id = UInt32(parts[1]),
           let match = NSScreen.screens.first(where: { Self.displayID($0) == id })
        {
            return match
        }
        let name = parts.first ?? trimmed
        return NSScreen.screens.first { $0.localizedName == name }
    }

    func exportCaptions(format: TheaterExportFormat) {
        let pairs = LiveTranslationController.shared.subscriber.exportCaptionPairs
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
        }
        guard !text.isEmpty else { return }
        self.makeKeyForInteraction()
        self.model.exportShowsSaved = true
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = TheaterCaptionExport.savePanelName(extension: ext)
        panel.begin { response in
            if response == .OK, let url = panel.url {
                try? text.write(to: url, atomically: true, encoding: .utf8)
            }
            PresenterCaptionController.shared.model.exportShowsSaved = false
            PresenterCaptionController.shared.scheduleReleaseKeyToExternalApp()
        }
    }
}
