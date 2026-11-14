import AppKit
import Combine
import SwiftUI
import Translation

private struct PasteTranslateAppearanceBridge: NSViewRepresentable {
    var appearance: TheaterAppearance

    func makeNSView(context: Context) -> PasteTranslateAppearanceHostView {
        let view = PasteTranslateAppearanceHostView()
        view.apply(self.appearance)
        return view
    }

    func updateNSView(_ view: PasteTranslateAppearanceHostView, context: Context) {
        view.apply(self.appearance)
    }
}

private final class PasteTranslateAppearanceHostView: NSView {
    private var appearanceName: NSAppearance.Name = .darkAqua

    func apply(_ appearance: TheaterAppearance) {
        self.appearanceName = appearance == .light ? .aqua : .darkAqua
        self.window?.appearance = NSAppearance(named: self.appearanceName)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        self.window?.appearance = NSAppearance(named: self.appearanceName)
    }
}

/// Separate window to paste or type text and translate it with on-device Apple Translation.
@MainActor
final class TheaterPasteTranslate: NSObject, NSWindowDelegate, ObservableObject {
    static let shared = TheaterPasteTranslate()

    struct TranslatedLine: Identifiable, Equatable {
        var id: Int
        var source: String
        var translated: String
        var sourceLanguageID: String
        var targetLanguageID: String
        var isReversePair: Bool
    }

    @Published var inputText = "" {
        didSet {
            guard self.inputText != oldValue else { return }
            self.scheduleTranslation()
        }
    }

    @Published var sourceLanguageID: String
    @Published var targetLanguageID: String

    @Published private(set) var translatedText = ""
    @Published private(set) var translatedLines: [TranslatedLine] = []
    @Published private(set) var isTranslating = false
    @Published private(set) var failure: String?
    @Published private(set) var activeSourceID = ""
    @Published private(set) var activeTargetID = ""
    @Published private(set) var copyConfirmed = false
    @Published private(set) var focusRequestToken: UInt64 = 0
    @Published var forwardConfiguration: TranslationSession.Configuration?
    @Published var reverseConfiguration: TranslationSession.Configuration?

    private let forwardEngine = TheaterPasteTranslateEngine()
    private let reverseEngine = TheaterPasteTranslateEngine()
    private var panel: NSPanel?
    private var debounceTask: Task<Void, Never>?
    private var copyFlashTask: Task<Void, Never>?
    private var pendingSourceText = ""
    private var renderedKey = ""
    private var lineCache: [String: String] = [:]
    private var pumping = false
    private var generation: UInt64 = 0

    private override init() {
        let settings = SettingsStore.shared
        let source = SpokenLanguageResolver.sourceLanguage(settings: settings)
        let target = SpokenLanguageResolver.targetLanguage(settings: settings)
        self.sourceLanguageID = source.id
        self.targetLanguageID = target.id
        self.activeSourceID = source.id
        self.activeTargetID = target.id
        super.init()
    }

    var sourceLanguage: TranslationLanguage {
        TranslationLanguageCatalog.language(id: self.sourceLanguageID)
            ?? SpokenLanguageResolver.sourceLanguage()
    }

    var targetLanguage: TranslationLanguage {
        TranslationLanguageCatalog.language(id: self.targetLanguageID)
            ?? SpokenLanguageResolver.targetLanguage()
    }

    var isReverseDirectionActive: Bool {
        TheaterCaptionVisibility.usesReversePairColor(
            sourceLanguageID: self.activeSourceID,
            targetLanguageID: self.activeTargetID,
            configuredSourceID: self.sourceLanguage.id
        )
    }

    var activePairLabel: String {
        let source = TranslationLanguageCatalog.language(id: self.activeSourceID) ?? self.sourceLanguage
        let target = TranslationLanguageCatalog.language(id: self.activeTargetID) ?? self.targetLanguage
        return "\(source.displayName) → \(target.displayName)"
    }

    func open(pasteClipboard: Bool = false) {
        if self.panel?.isVisible != true, self.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let settings = SettingsStore.shared
            self.sourceLanguageID = SpokenLanguageResolver.sourceLanguage(settings: settings).id
            self.targetLanguageID = SpokenLanguageResolver.targetLanguage(settings: settings).id
        }
        self.ensureWindow()
        self.focusRequestToken &+= 1
        if pasteClipboard {
            self.pasteFromClipboard()
        } else {
            self.requestTranslationNow()
        }
    }

    func pasteFromClipboard() {
        guard let pasted = NSPasteboard.general.string(forType: .string) else { return }
        let trimmed = pasted.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        self.debounceTask?.cancel()
        self.inputText = pasted
        self.requestTranslationNow()
    }

    func copyTranslation(bilingual: Bool = false) {
        let content: String
        if bilingual {
            let pairs = self.translatedLines.compactMap { line -> String? in
                let source = line.source.trimmingCharacters(in: .whitespacesAndNewlines)
                let translated = line.translated.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !translated.isEmpty else { return nil }
                if source.isEmpty || source == translated {
                    return translated
                }
                return "\(translated)\n\(source)"
            }
            content = pairs.joined(separator: "\n\n")
        } else {
            content = self.translatedText.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard !content.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(content, forType: .string)
        self.copyConfirmed = true
        self.copyFlashTask?.cancel()
        self.copyFlashTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 900_000_000)
            guard !Task.isCancelled else { return }
            self?.copyConfirmed = false
        }
    }

    func clear() {
        self.debounceTask?.cancel()
        self.generation &+= 1
        self.inputText = ""
        self.pendingSourceText = ""
        self.translatedText = ""
        self.translatedLines = []
        self.failure = nil
        self.isTranslating = false
        self.renderedKey = ""
        self.activeSourceID = self.sourceLanguage.id
        self.activeTargetID = self.targetLanguage.id
        self.focusRequestToken &+= 1
    }

    func swapLanguages() {
        let previousSource = self.sourceLanguageID
        self.sourceLanguageID = self.targetLanguageID
        self.targetLanguageID = previousSource
        self.renderedKey = ""
        self.requestTranslationNow()
    }

    func setSourceLanguage(_ id: String) {
        guard self.sourceLanguageID != id else { return }
        self.sourceLanguageID = id
        self.renderedKey = ""
        self.requestTranslationNow()
    }

    func setTargetLanguage(_ id: String) {
        guard self.targetLanguageID != id else { return }
        self.targetLanguageID = id
        self.renderedKey = ""
        self.requestTranslationNow()
    }

    func requestTranslationNow() {
        self.debounceTask?.cancel()
        self.prepareSessionForCurrentInput()
    }

    func downloadPack() {
        let pair = self.resolvedPair(for: self.inputText)
        AppleTranslationEngine.shared.requestLanguagePackDownload(source: pair.source, target: pair.target)
        self.renderedKey = ""
        self.failure = nil
        self.requestTranslationNow()
    }

    func windowDidMove(_ notification: Notification) {
        self.rememberFrame()
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        self.rememberFrame()
    }

    /// Resolves which direction to translate `text` when Either way is on.
    /// The switch is the same one Theater Listen uses.
    func resolvedPair(for text: String) -> (source: TranslationLanguage, target: TranslationLanguage) {
        let source = self.sourceLanguage
        let target = self.targetLanguage
        guard SpokenLanguageResolver.isDynamicPairingEnabled(), source.id != target.id else {
            return (source, target)
        }
        if let detectedID = SpokenScriptDetector.languageID(in: text, among: [source.id, target.id]),
           detectedID == target.id
        {
            return (target, source)
        }
        return (source, target)
    }

    func serveForward(_ session: TranslationSession) async {
        self.forwardEngine.session = session
        while !Task.isCancelled {
            await self.pump()
            try? await Task.sleep(nanoseconds: 150_000_000)
        }
        self.forwardEngine.session = nil
    }

    func serveReverse(_ session: TranslationSession) async {
        self.reverseEngine.session = session
        while !Task.isCancelled {
            await self.pump()
            try? await Task.sleep(nanoseconds: 150_000_000)
        }
        self.reverseEngine.session = nil
    }

    private func scheduleTranslation() {
        self.debounceTask?.cancel()
        let trimmed = self.inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            self.generation &+= 1
            self.pendingSourceText = ""
            self.translatedText = ""
            self.translatedLines = []
            self.failure = nil
            self.isTranslating = false
            self.renderedKey = ""
            self.activeSourceID = self.sourceLanguage.id
            self.activeTargetID = self.targetLanguage.id
            return
        }
        self.debounceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 220_000_000)
            guard !Task.isCancelled else { return }
            self?.prepareSessionForCurrentInput()
        }
    }

    private func prepareSessionForCurrentInput() {
        let trimmed = self.inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        self.pendingSourceText = trimmed
        let configuredSource = self.sourceLanguage
        let configuredTarget = self.targetLanguage
        let overallPair = self.resolvedPair(for: trimmed)
        self.activeSourceID = overallPair.source.id
        self.activeTargetID = overallPair.target.id

        guard !trimmed.isEmpty else {
            self.translatedText = ""
            self.translatedLines = []
            self.failure = nil
            self.isTranslating = false
            self.renderedKey = ""
            return
        }

        if configuredSource.id == configuredTarget.id {
            let lines = trimmed.components(separatedBy: .newlines)
            self.translatedLines = lines.enumerated().map { index, line in
                TranslatedLine(
                    id: index,
                    source: line,
                    translated: line,
                    sourceLanguageID: configuredSource.id,
                    targetLanguageID: configuredTarget.id,
                    isReversePair: false
                )
            }
            self.translatedText = trimmed
            self.failure = nil
            self.isTranslating = false
            self.renderedKey = "\(trimmed)\n\(configuredSource.id)>\(configuredTarget.id)"
            return
        }

        let rawLines = trimmed.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        var needsForward = false
        var needsReverse = false
        for line in rawLines {
            let pair = self.resolvedPair(for: line)
            if pair.source.id == configuredTarget.id, pair.target.id == configuredSource.id {
                needsReverse = true
            } else {
                needsForward = true
            }
        }

        let forwardPairChanged = self.forwardEngine.sourceID != configuredSource.id
            || self.forwardEngine.targetID != configuredTarget.id
        let reversePairChanged = self.reverseEngine.sourceID != configuredTarget.id
            || self.reverseEngine.targetID != configuredSource.id

        self.generation &+= 1
        self.renderedKey = ""
        self.failure = nil

        if needsForward {
            self.forwardEngine.sourceID = configuredSource.id
            self.forwardEngine.targetID = configuredTarget.id
            if forwardPairChanged || self.forwardConfiguration == nil {
                self.forwardConfiguration = AppleTranslationStrategy.makeLowLatencyConfiguration(
                    source: configuredSource.localeLanguage,
                    target: configuredTarget.localeLanguage
                )
            } else {
                self.forwardConfiguration?.invalidate()
            }
        }

        if needsReverse {
            self.reverseEngine.sourceID = configuredTarget.id
            self.reverseEngine.targetID = configuredSource.id
            if reversePairChanged || self.reverseConfiguration == nil {
                self.reverseConfiguration = AppleTranslationStrategy.makeLowLatencyConfiguration(
                    source: configuredTarget.localeLanguage,
                    target: configuredSource.localeLanguage
                )
            } else {
                self.reverseConfiguration?.invalidate()
            }
        }
    }

    private func pump() async {
        guard !self.pumping else { return }
        let text = self.pendingSourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let configuredSource = self.sourceLanguage
        let configuredTarget = self.targetLanguage
        guard configuredSource.id != configuredTarget.id else { return }

        let key = "\(text)\n\(configuredSource.id)>\(configuredTarget.id)\n\(SpokenLanguageResolver.isDynamicPairingEnabled())"
        guard key != self.renderedKey else { return }
        self.pumping = true
        self.isTranslating = true
        defer {
            self.pumping = false
            self.isTranslating = false
        }
        let generation = self.generation
        let terms = TranslationGlossary.protectedTerms()
        let lines = text.components(separatedBy: .newlines)
        var outputLines: [String] = []
        var structuredLines: [TranslatedLine] = []
        outputLines.reserveCapacity(lines.count)
        structuredLines.reserveCapacity(lines.count)

        for (index, line) in lines.enumerated() {
            if Task.isCancelled || generation != self.generation { return }
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedLine.isEmpty {
                outputLines.append("")
                structuredLines.append(
                    TranslatedLine(
                        id: index,
                        source: "",
                        translated: "",
                        sourceLanguageID: configuredSource.id,
                        targetLanguageID: configuredTarget.id,
                        isReversePair: false
                    )
                )
                continue
            }
            let pair = self.resolvedPair(for: trimmedLine)
            let isReverse = TheaterCaptionVisibility.usesReversePairColor(
                sourceLanguageID: pair.source.id,
                targetLanguageID: pair.target.id,
                configuredSourceID: configuredSource.id
            )
            let cacheKey = "\(pair.source.id)>\(pair.target.id)\u{1}\(trimmedLine)"
            if let cached = self.lineCache[cacheKey] {
                outputLines.append(cached)
                structuredLines.append(
                    TranslatedLine(
                        id: index,
                        source: trimmedLine,
                        translated: cached,
                        sourceLanguageID: pair.source.id,
                        targetLanguageID: pair.target.id,
                        isReversePair: isReverse
                    )
                )
                self.translatedLines = structuredLines
                self.translatedText = outputLines.joined(separator: "\n")
                continue
            }
            let engine = isReverse ? self.reverseEngine : self.forwardEngine
            do {
                let protectedInput = TranslationGlossary.protect(trimmedLine, terms: terms)
                let rawTranslated = try await engine.translate(
                    protectedInput.text,
                    source: pair.source,
                    target: pair.target,
                    kind: .commit
                )
                guard !Task.isCancelled, generation == self.generation else { return }
                let restoredFromLock = TranslationGlossary.restore(
                    rawTranslated,
                    tokens: protectedInput.tokens
                )
                let restored: String
                if TranslationGlossaryLock.needsUnlockedFallback(
                    source: trimmedLine,
                    rawTranslated: rawTranslated,
                    restored: restoredFromLock,
                    tokens: protectedInput.tokens
                ) {
                    restored = try await LiveTranslationMT.translateWithRetry(
                        trimmedLine,
                        source: pair.source,
                        target: pair.target,
                        engine: engine,
                        kind: .commit
                    )
                } else {
                    restored = restoredFromLock
                }
                if self.lineCache.count > 256 {
                    self.lineCache.removeAll(keepingCapacity: true)
                }
                self.lineCache[cacheKey] = restored
                outputLines.append(restored)
                structuredLines.append(
                    TranslatedLine(
                        id: index,
                        source: trimmedLine,
                        translated: restored,
                        sourceLanguageID: pair.source.id,
                        targetLanguageID: pair.target.id,
                        isReversePair: isReverse
                    )
                )
                self.translatedLines = structuredLines
                self.translatedText = outputLines.joined(separator: "\n")
                self.failure = nil
            } catch {
                if error is CancellationError || generation != self.generation { return }
                if (error as? TranslationEngineError)?.errorDescription == "Apple Translation is not ready." {
                    return
                }
                self.failure = TheaterReadiness.secondShowAsPack
                self.renderedKey = key
                return
            }
        }
        self.translatedLines = structuredLines
        self.translatedText = outputLines.joined(separator: "\n")
        self.renderedKey = key
        self.failure = nil
    }

    private func ensureWindow() {
        if self.panel == nil {
            self.panel = Self.makePanel(model: self, frame: self.restoredFrame())
        }
        self.panel?.title = AppLanguage.text("Paste & Translate")
        NSApp.activate(ignoringOtherApps: true)
        self.panel?.makeKeyAndOrderFront(nil)
    }

    private func restoredFrame() -> CGRect? {
        let parts = SettingsStore.shared.theaterPasteTranslateFrame.split(separator: ",").compactMap { Double($0) }
        guard parts.count == 4 else { return nil }
        let rect = CGRect(x: parts[0], y: parts[1], width: parts[2], height: parts[3])
        guard rect.width >= 480, rect.height >= 340 else { return nil }
        guard NSScreen.screens.contains(where: { $0.visibleFrame.intersects(rect) }) else { return nil }
        return rect
    }

    private func rememberFrame() {
        guard let frame = self.panel?.frame else { return }
        let values = [frame.origin.x, frame.origin.y, frame.width, frame.height].map { String(Double($0)) }
        SettingsStore.shared.theaterPasteTranslateFrame = values.joined(separator: ",")
    }

    private static func makePanel(model: TheaterPasteTranslate, frame: CGRect?) -> NSPanel {
        let hosting = NSHostingController(rootView: TheaterPasteTranslateRoot(model: model))
        hosting.sizingOptions = []
        let panel = NSPanel(
            contentRect: frame ?? Self.defaultFrame(),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        panel.delegate = model
        panel.title = AppLanguage.text("Paste & Translate")
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.minSize = NSSize(width: 480, height: 340)
        panel.contentViewController = hosting
        TheaterWindowSharing.apply(panel)
        return panel
    }

    private static func defaultFrame() -> CGRect {
        let screen = NSScreen.main ?? NSScreen.screens.first
        let visible = screen?.visibleFrame ?? CGRect(x: 120, y: 120, width: 640, height: 460)
        let size = CGSize(width: min(640, visible.width - 80), height: min(460, visible.height - 100))
        return CGRect(
            x: visible.midX - size.width / 2,
            y: visible.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
    }
}

@MainActor
private final class TheaterPasteTranslateEngine: TranslationEngine {
    let name = "Apple Translation"
    var session: TranslationSession?
    var sourceID = ""
    var targetID = ""

    func translate(
        _ text: String,
        source: TranslationLanguage,
        target: TranslationLanguage
    ) async throws -> String {
        try await self.translate(text, source: source, target: target, kind: .commit)
    }

    func translate(
        _ text: String,
        source: TranslationLanguage,
        target: TranslationLanguage,
        kind: TranslationRequestKind
    ) async throws -> String {
        guard source.id == self.sourceID, target.id == self.targetID, let session = self.session else {
            throw TranslationEngineError(message: "Apple Translation is not ready.")
        }
        let response = try await session.translate(text)
        let translated = response.targetText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !translated.isEmpty else { throw TranslationEngineError.captionRejected }
        return translated
    }
}

private struct ForwardTranslationSessionHost: View {
    @ObservedObject var model: TheaterPasteTranslate

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
            .translationTask(self.model.forwardConfiguration) { session in
                await self.model.serveForward(session)
            }
    }
}

private struct ReverseTranslationSessionHost: View {
    @ObservedObject var model: TheaterPasteTranslate

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
            .translationTask(self.model.reverseConfiguration) { session in
                await self.model.serveReverse(session)
            }
    }
}

private struct TheaterPasteTranslateRoot: View {
    @ObservedObject var model: TheaterPasteTranslate

    var body: some View {
        TheaterPasteTranslateView(model: self.model)
            .background {
                ForwardTranslationSessionHost(model: self.model)
                ReverseTranslationSessionHost(model: self.model)
            }
    }
}

private struct TheaterPasteTranslateView: View {
    @ObservedObject var model: TheaterPasteTranslate
    @ObservedObject private var settings = SettingsStore.shared
    @FocusState private var isInputFocused: Bool

    private var appearance: TheaterAppearance {
        TheaterAppearance.resolved(self.settings.theaterAppearance)
    }

    private var theme: AppTheme {
        AppTheme.adaptive(accent: self.settings.accentColor, colorScheme: self.appearance.colorScheme)
    }

    private var typeface: TheaterTypeface {
        TheaterTypeface.resolved(self.settings.presenterFontFamily)
    }

    private var captionColors: TheaterCaptionVisibility.Colors {
        TheaterCaptionVisibility.colors(
            appearance: self.appearance,
            presentation: .popup,
            highContrast: self.settings.theaterHighContrast
        )
    }

    private var forwardColor: Color {
        Color(nsColor: self.captionColors.lineColors(reversePair: false).translated)
    }

    private var reverseColor: Color {
        Color(nsColor: self.captionColors.lineColors(reversePair: true).translated)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            self.toolbarRow
            Divider()
            self.panes
            if self.model.failure != nil {
                self.failureRow
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(self.theme.palette.windowBackground)
        .background(PasteTranslateAppearanceBridge(appearance: self.appearance))
        .appTheme(self.theme)
        .preferredColorScheme(self.appearance.colorScheme)
        .tint(self.theme.palette.accent)
        .onAppear {
            self.isInputFocused = true
        }
        .onChange(of: self.model.focusRequestToken) { _, _ in
            self.isInputFocused = true
        }
        .onChange(of: self.settings.theaterDynamicPairing) { _, _ in
            self.model.requestTranslationNow()
        }
        .onChange(of: self.settings.selectedSpeechModel) { _, _ in
            self.model.requestTranslationNow()
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("theater.pasteTranslate")
    }

    private var toolbarRow: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                self.languageControls
                Spacer(minLength: 8)
                self.actionControls
            }
            VStack(alignment: .leading, spacing: 8) {
                self.languageControls
                HStack(spacing: 8) {
                    Spacer(minLength: 8)
                    self.actionControls
                }
            }
        }
    }

    private var languageControls: some View {
        HStack(spacing: 6) {
            TheaterLanguageMenu(
                title: AppLanguage.text("I speak"),
                selection: Binding(
                    get: { self.model.sourceLanguageID },
                    set: { self.model.setSourceLanguage($0) }
                ),
                languages: LanguageChoicePolicy.spokenLanguages(),
                compactChrome: true,
                accessibilityIdentifier: "theater.pasteTranslate.source"
            )

            Button {
                self.model.swapLanguages()
            } label: {
                Image(systemName: "arrow.left.arrow.right")
                    .font(.system(size: 11, weight: .semibold))
                    .accessibilityHidden(true)
            }
            .buttonStyle(.theaterTextCompactIcon)
            .help(AppLanguage.text("Swap languages"))
            .accessibilityLabel(AppLanguage.text("Swap languages"))
            .accessibilityIdentifier("theater.pasteTranslate.swap")

            TheaterLanguageMenu(
                title: AppLanguage.text("Show as"),
                selection: Binding(
                    get: { self.model.targetLanguageID },
                    set: { self.model.setTargetLanguage($0) }
                ),
                languages: LanguageChoicePolicy.targetLanguages(),
                compactChrome: true,
                accessibilityIdentifier: "theater.pasteTranslate.target"
            )

            TheaterEitherWaySection(
                accessibilityIdentifier: "theater.pasteTranslate.eitherWay",
                compact: true,
                apply: { enabled in
                    LiveTranslationController.shared.applyDynamicPairing(enabled)
                    self.model.requestTranslationNow()
                }
            )
        }
    }

    private var actionControls: some View {
        HStack(spacing: 6) {
            Button {
                self.model.pasteFromClipboard()
            } label: {
                Label(AppLanguage.text("Paste"), systemImage: "doc.on.clipboard")
            }
            .buttonStyle(.theaterTextCompact)
            .help(AppLanguage.text("Paste text from the clipboard and translate it."))
            .accessibilityIdentifier("theater.pasteTranslate.paste")

            Button {
                self.model.clear()
            } label: {
                AppText("Clear")
            }
            .buttonStyle(.theaterTextCompact)
            .disabled(self.model.inputText.isEmpty && self.model.translatedText.isEmpty)
            .accessibilityIdentifier("theater.pasteTranslate.clear")
        }
    }

    private var panes: some View {
        VSplitView {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    AppText("Original text")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    if SpokenLanguageResolver.isDynamicPairingEnabled(settings: self.settings),
                       self.model.sourceLanguageID != self.model.targetLanguageID
                    {
                        self.directionLegend
                    }
                }
                TextEditor(text: self.$model.inputText)
                    .focused(self.$isInputFocused)
                    .font(self.typeface.font(size: 16, weight: .regular))
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.primary.opacity(0.06))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
                    )
                    .accessibilityLabel(AppLanguage.text("Original text"))
                    .accessibilityIdentifier("theater.pasteTranslate.input")
            }
            .frame(minHeight: 110, maxHeight: .infinity)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    AppText("Translation")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    if self.model.isTranslating {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Spacer()
                    Button {
                        self.model.copyTranslation(bilingual: false)
                    } label: {
                        Label(
                            self.model.copyConfirmed ? AppLanguage.text("Copied") : AppLanguage.text("Copy"),
                            systemImage: self.model.copyConfirmed ? "checkmark" : "doc.on.doc"
                        )
                    }
                    .buttonStyle(.theaterTextCompact)
                    .disabled(self.model.translatedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("theater.pasteTranslate.copy")

                    Button {
                        self.model.copyTranslation(bilingual: true)
                    } label: {
                        AppText("Copy bilingual")
                    }
                    .buttonStyle(.theaterTextCompact)
                    .disabled(self.model.translatedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("theater.pasteTranslate.copyBilingual")
                }
                ScrollView {
                    if self.model.translatedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(AppLanguage.text("Paste or type text above to translate."))
                            .font(self.typeface.font(size: 16, weight: .regular))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(self.model.translatedLines) { line in
                                if line.translated.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                    Spacer()
                                        .frame(height: 6)
                                } else {
                                    Text(line.translated)
                                        .font(self.typeface.font(size: 20, weight: .semibold))
                                        .foregroundStyle(line.isReversePair ? self.reverseColor : self.forwardColor)
                                        .textSelection(.enabled)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel(self.model.translatedText)
                        .accessibilityIdentifier("theater.pasteTranslate.output")
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(0.06))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
                )
            }
            .frame(minHeight: 130, maxHeight: .infinity)
        }
    }

    private var directionLegend: some View {
        let source = self.model.sourceLanguage
        let target = self.model.targetLanguage
        return HStack(spacing: 10) {
            HStack(spacing: 4) {
                Circle()
                    .fill(self.forwardColor)
                    .frame(width: 6, height: 6)
                    .accessibilityHidden(true)
                Text("\(source.displayName) → \(target.displayName)")
                    .foregroundStyle(self.forwardColor)
            }
            HStack(spacing: 4) {
                Circle()
                    .fill(self.reverseColor)
                    .frame(width: 6, height: 6)
                    .accessibilityHidden(true)
                Text("\(target.displayName) → \(source.displayName)")
                    .foregroundStyle(self.reverseColor)
            }
        }
        .font(.caption.weight(.medium))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(source.displayName) ↔ \(target.displayName)")
        .accessibilityIdentifier("theater.pasteTranslate.direction")
    }

    private var failureRow: some View {
        HStack(spacing: 8) {
            AppText(TheaterReadiness.secondShowAsPack)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            AppButton(TheaterReadiness.secondShowAsPackButton) {
                self.model.downloadPack()
            }
            .buttonStyle(.theaterTextCompact)
            AppButton(TheaterReadiness.secondShowAsTryAgain) {
                self.model.requestTranslationNow()
            }
            .buttonStyle(.theaterTextCompact)
        }
    }
}

struct OpenPasteTranslateButton: View {
    var body: some View {
        Button {
            TheaterPasteTranslate.shared.open()
        } label: {
            TheaterActionLabel(
                title: AppLanguage.text("Paste & Translate"),
                systemImage: "doc.on.clipboard"
            )
        }
        .buttonStyle(.theaterText)
        .disabled(!TheaterAvailability.isSupported)
        .help(AppLanguage.text("Open a separate window to paste or type text and translate it."))
        .accessibilityIdentifier("theater.openPasteTranslate")
    }
}
