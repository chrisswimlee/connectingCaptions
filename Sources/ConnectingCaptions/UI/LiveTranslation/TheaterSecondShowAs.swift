import AppKit
import Combine
import SwiftUI
import Translation

/// A stored second language that is already I speak or Show as stays off.
enum TheaterSecondShowAsChoice {
    static func resolved(stored: String, sourceID: String, targetID: String) -> String {
        let trimmed = stored.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let language = TranslationLanguageCatalog.language(id: trimmed) else { return "" }
        if language.id == sourceID || language.id == targetID { return "" }
        return language.id
    }
}

/// One more Show-as language, on its own window, from the same Listen.
@MainActor
final class TheaterSecondShowAs: NSObject, NSWindowDelegate, ObservableObject {
    static let shared = TheaterSecondShowAs()

    struct Line: Identifiable, Equatable {
        var id: UInt64
        var text: String
    }

    @Published private(set) var lines: [Line] = []
    @Published private(set) var listening = false
    @Published private(set) var failure: String?
    @Published private(set) var languageName = ""
    @Published var configuration: TranslationSession.Configuration?

    private let engine = TheaterSecondShowAsEngine()
    private let context = LiveTranslationContextStreak()
    private var panel: NSPanel?
    private var closing = false
    private var source = SpokenLanguageResolver.sourceLanguage()
    private var target = SpokenLanguageResolver.targetLanguage()
    private var pendingRows: [TheaterBoardRow] = []
    private var renderedKey = ""
    private var cache: [UInt64: String] = [:]
    private var cacheSource: [UInt64: String] = [:]
    private var pumping = false
    private var generation: UInt64 = 0

    private override init() {
        super.init()
    }

    func refresh() {
        guard !SettingsStore.isRunningTests else { return }
        let settings = SettingsStore.shared
        guard settings.theaterSessionMode.showsTranslation else {
            self.orderOut()
            return
        }
        let source = SpokenLanguageResolver.sourceLanguage()
        let targetID = settings.theaterSecondShowAsLanguageID
        guard let target = TranslationLanguageCatalog.language(id: targetID), target.id != source.id else {
            SettingsStore.shared.clearCollidingSecondShowAs()
            self.orderOut()
            return
        }
        self.ensureWindow(languageName: target.displayName)
        self.languageName = target.displayName
        let listening = LiveTranslationController.shared.isSessionActive && !LiveTranslationController.shared.isPaused
        if self.listening != listening { self.listening = listening }
        self.note(
            rows: LiveTranslationController.shared.subscriber.boardState.rows,
            source: source,
            target: target
        )
    }

    func serve(_ session: TranslationSession) async {
        self.engine.session = session
        while !Task.isCancelled {
            await self.pump()
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        self.engine.session = nil
    }

    func tryAgain() {
        self.renderedKey = ""
        self.failure = nil
    }

    func downloadPack() {
        AppleTranslationEngine.shared.requestLanguagePackDownload(source: self.source, target: self.target)
        self.tryAgain()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard !self.closing else { return true }
        self.closing = true
        SettingsStore.shared.theaterSecondShowAsLanguageID = ""
        self.closing = false
        return true
    }

    func windowDidMove(_ notification: Notification) {
        self.rememberFrame()
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        self.rememberFrame()
    }

    private func note(rows: [TheaterBoardRow], source: TranslationLanguage, target: TranslationLanguage) {
        let pairChanged = source.id != self.source.id || target.id != self.target.id
        self.pendingRows = rows
        self.source = source
        self.target = target
        if pairChanged {
            self.generation &+= 1
            self.cache.removeAll()
            self.cacheSource.removeAll()
            self.lines = []
            self.renderedKey = ""
            self.failure = nil
            self.context.reset()
            self.configuration = AppleTranslationStrategy.makeLowLatencyConfiguration(
                source: source.localeLanguage,
                target: target.localeLanguage
            )
        }
        self.engine.sourceID = source.id
        self.engine.targetID = target.id
    }

    private func pump() async {
        guard !self.pumping else { return }
        let key = self.pendingRows.map { "\($0.id)\u{1}\($0.source)" }.joined(separator: "\n")
            + "\n\(self.source.id)>\(self.target.id)"
        guard key != self.renderedKey else { return }
        self.pumping = true
        defer { self.pumping = false }
        let generation = self.generation
        var shown: [Line] = []
        var priors: [String] = []
        var priorTranslations: [String] = []
        let terms = TranslationGlossary.protectedTerms()
        for row in self.pendingRows {
            if Task.isCancelled || generation != self.generation { return }
            let sourceText = row.source.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !sourceText.isEmpty else { continue }
            if self.cacheSource[row.id] == sourceText, let cached = self.cache[row.id] {
                shown.append(Line(id: row.id, text: cached))
                priors.append(sourceText)
                priorTranslations.append(cached)
                self.lines = shown
                continue
            }
            do {
                let spoken = row.sourceLanguageID.flatMap {
                    TranslationLanguageCatalog.language(id: $0)
                } ?? self.source
                let text = try await LiveTranslationMT.appleClause(
                    sourceText,
                    source: spoken,
                    target: self.target,
                    terms: terms,
                    kind: .commit,
                    prior: (Array(priors.suffix(4)), Array(priorTranslations.suffix(4))),
                    translator: self.engine,
                    contextStreak: self.context
                )
                guard !Task.isCancelled, generation == self.generation else { return }
                self.cache[row.id] = text
                self.cacheSource[row.id] = sourceText
                shown.append(Line(id: row.id, text: text))
                priors.append(sourceText)
                priorTranslations.append(text)
                self.lines = shown
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
        let live = Set(self.pendingRows.map(\.id))
        self.cache = self.cache.filter { live.contains($0.key) }
        self.cacheSource = self.cacheSource.filter { live.contains($0.key) }
        self.lines = shown
        self.renderedKey = key
        self.failure = nil
    }

    private func ensureWindow(languageName: String) {
        if self.panel == nil {
            self.panel = Self.makePanel(model: self, frame: self.restoredFrame())
        }
        self.panel?.title = languageName
        guard self.panel?.isVisible != true else { return }
        self.panel?.orderFrontRegardless()
    }

    private func orderOut() {
        guard self.panel != nil || self.configuration != nil || !self.lines.isEmpty else { return }
        self.pendingRows = []
        self.lines = []
        self.failure = nil
        self.renderedKey = ""
        self.configuration = nil
        self.panel?.orderOut(nil)
    }

    private func restoredFrame() -> CGRect? {
        let parts = SettingsStore.shared.theaterSecondShowAsFrame.split(separator: ",").compactMap { Double($0) }
        guard parts.count == 4 else { return nil }
        let rect = CGRect(x: parts[0], y: parts[1], width: parts[2], height: parts[3])
        guard rect.width >= 320, rect.height >= 140 else { return nil }
        guard NSScreen.screens.contains(where: { $0.visibleFrame.intersects(rect) }) else { return nil }
        return rect
    }

    private func rememberFrame() {
        guard let frame = self.panel?.frame else { return }
        let values = [frame.origin.x, frame.origin.y, frame.width, frame.height].map { String(Double($0)) }
        SettingsStore.shared.theaterSecondShowAsFrame = values.joined(separator: ",")
    }

    private static func makePanel(model: TheaterSecondShowAs, frame: CGRect?) -> NSPanel {
        let hosting = NSHostingController(rootView: TheaterSecondShowAsRoot(model: model))
        hosting.sizingOptions = []
        let panel = NSPanel(
            contentRect: frame ?? Self.defaultFrame(),
            styleMask: [.titled, .closable, .resizable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.delegate = model
        panel.title = model.languageName
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isMovableByWindowBackground = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.minSize = NSSize(width: 320, height: 140)
        panel.backgroundColor = .black
        panel.isOpaque = false
        panel.contentViewController = hosting
        TheaterWindowSharing.apply(panel)
        return panel
    }

    private static func defaultFrame() -> CGRect {
        let screen = NSScreen.screens.first { $0 != NSScreen.main } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? CGRect(x: 80, y: 80, width: 900, height: 280)
        let size = CGSize(width: min(900, visible.width - 48), height: min(280, max(180, visible.height * 0.28)))
        return CGRect(
            x: visible.midX - size.width / 2,
            y: visible.minY + 28,
            width: size.width,
            height: size.height
        )
    }
}

@MainActor
private final class TheaterSecondShowAsEngine: TranslationEngine {
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

private struct TheaterSecondShowAsRoot: View {
    @ObservedObject var model: TheaterSecondShowAs

    var body: some View {
        TheaterSecondShowAsBoard(model: self.model)
            .translationTask(self.model.configuration) { session in
                await self.model.serve(session)
            }
    }
}

private struct TheaterSecondShowAsBoard: View {
    @ObservedObject var model: TheaterSecondShowAs
    @ObservedObject private var settings = SettingsStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if self.model.lines.isEmpty {
                Text(self.model.listening ? TheaterReadiness.boardListeningTitle : self.model.languageName)
                    .font(self.captionFont)
                    .foregroundStyle(.white)
                    .accessibilityLabel(
                        self.model.listening ? TheaterReadiness.boardListening : self.model.languageName
                    )
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(self.visibleLines) { line in
                                Text(line.text)
                                    .font(self.captionFont)
                                    .foregroundStyle(.white)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .id(line.id)
                            }
                        }
                    }
                    .onChange(of: self.model.lines) { _, lines in
                        if let last = lines.last?.id {
                            proxy.scrollTo(last, anchor: .bottom)
                        }
                    }
                }
            }
            if self.model.failure != nil {
                AppText(TheaterReadiness.secondShowAsPack)
                    .font(.body)
                    .foregroundStyle(.white.opacity(0.85))
                HStack(spacing: 8) {
                    AppButton(TheaterReadiness.secondShowAsPackButton) {
                        self.model.downloadPack()
                    }
                    AppButton(TheaterReadiness.secondShowAsTryAgain) {
                        self.model.tryAgain()
                    }
                }
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        .background(Color.black.opacity(0.88))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("theater.secondShowAs")
    }

    private var visibleLines: [TheaterSecondShowAs.Line] {
        Array(self.model.lines.suffix(8))
    }

    private var captionFont: Font {
        let size = TheaterCaptionScale.translatedSize(setting: CGFloat(self.settings.presenterFontSize))
        return .system(size: size, weight: .semibold)
    }
}

struct TheaterSecondShowAsMenu: View {
    var compact = false
    @ObservedObject private var settings = SettingsStore.shared

    var body: some View {
        if self.settings.theaterSessionMode.showsTranslation {
            Menu {
                Picker(TheaterReadiness.secondShowAsTitle, selection: self.selection) {
                    AppText("Off").tag("")
                    ForEach(self.languages) { language in
                        Text(AppLanguage.localizedName(for: language, languageID: self.settings.appLanguageID))
                            .tag(language.id)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } label: {
                self.label
            }
            .help(TheaterReadiness.secondShowAsHelp)
            .accessibilityLabel(TheaterReadiness.secondShowAsTitle)
            .accessibilityValue(self.valueName)
            .accessibilityIdentifier(self.compact ? "theater.window.alsoShow" : "theater.alsoShow")
            .onChange(of: self.settings.translationSourceLanguageID) { _, _ in
                TheaterSecondShowAs.shared.refresh()
            }
            .onChange(of: self.settings.translationTargetLanguageID) { _, _ in
                TheaterSecondShowAs.shared.refresh()
            }
            .onChange(of: self.settings.theaterSessionMode) { _, _ in
                TheaterSecondShowAs.shared.refresh()
            }
        }
    }

    private var label: some View {
        HStack(spacing: self.compact ? 5 : 6) {
            Text(AppLanguage.text(TheaterReadiness.secondShowAsTitle))
                .font(.system(size: self.compact ? 10 : 12, weight: .semibold))
                .opacity(0.58)
                .lineLimit(1)
            Text(self.valueName)
                .lineLimit(1)
            Image(systemName: "chevron.down")
                .font(.system(size: self.compact ? 8 : 9, weight: .bold))
                .opacity(0.72)
                .accessibilityHidden(true)
        }
        .theaterButtonFace(compact: self.compact)
    }

    private var valueName: String {
        guard let language = TranslationLanguageCatalog.language(id: self.settings.theaterSecondShowAsLanguageID) else {
            return AppLanguage.text("Off")
        }
        return AppLanguage.localizedName(for: language, languageID: self.settings.appLanguageID)
    }

    private var languages: [TranslationLanguage] {
        let source = SpokenLanguageResolver.sourceLanguage()
        let target = SpokenLanguageResolver.targetLanguage()
        return LanguageChoicePolicy.targetLanguages().filter { $0.id != source.id && $0.id != target.id }
    }

    private var selection: Binding<String> {
        Binding(
            get: { self.settings.theaterSecondShowAsLanguageID },
            set: { value in
                self.settings.theaterSecondShowAsLanguageID = value
                TheaterSecondShowAs.shared.refresh()
            }
        )
    }
}
