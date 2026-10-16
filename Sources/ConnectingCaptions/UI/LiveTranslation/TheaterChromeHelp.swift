import Combine
import SwiftUI

/// Hover tags for Theater chrome: Name — what it does. Shortcut if any.
enum TheaterChromeHelp {
    static func tag(_ name: String, does: String, shortcut: String? = nil) -> String {
        if let shortcut {
            return AppLanguage.format("{0} — {1} {2}.", AppLanguage.text(name), AppLanguage.text(does), shortcut)
        }
        return AppLanguage.format("{0} — {1}", AppLanguage.text(name), AppLanguage.text(does))
    }

    static var listen: String { tag(
        "Listen",
        does: AppLanguage.text("Start the microphone. Each sentence appears when it is ready."),
        shortcut: "Control-Option-L"
    ) }
    static var stop: String { tag(
        "Stop",
        does: TheaterReadiness.stopHelp,
        shortcut: "Control-Option-L"
    ) }
    static var pause: String { tag(
        "Pause",
        does: TheaterReadiness.pauseHelp,
        shortcut: "Control-Option-P"
    ) }
    static var resume: String { tag(
        "Resume",
        does: TheaterReadiness.resumeHelp,
        shortcut: "Control-Option-P"
    ) }
    static var iSpeak: String { tag(
        "I speak",
        does: AppLanguage.text("Language you talk in. Voice Engine follows this.")
    ) }
    static var showAs: String { tag(
        "Show as",
        does: AppLanguage.text("Language printed as the caption title.")
    ) }
    static var swapLanguages: String { tag(
        "Swap languages",
        does: AppLanguage.text("Swap I speak and Show as. Stops Listen.")
    ) }
    static var mode: String { tag(
        "Theater mode",
        does: AppLanguage.text("Voice writes what you say. Translate captions into a supported language. Switching stops Listen.")
    ) }
    static var retry: String { tag(
        "Retry",
        does: AppLanguage.text("Retry the last failed translation."),
        shortcut: "Control-Option-R"
    ) }
    static var downloadPack: String { tag(
        "Download pack",
        does: AppLanguage.text("Download the Apple Translation pack for this pair.")
    ) }
    static var captionsOnly: String { tag(
        "Captions only",
        does: AppLanguage.text("Hide the tool bar and the window bar. Move the pointer to show Listen and the other controls.")
    ) }
    static var showAllControls: String { tag(
        "Show all controls",
        does: AppLanguage.text("Show the tool bar again.")
    ) }
    static var minimize: String { tag(
        "Minimize Theater",
        does: TheaterReadiness.minimizeHelp,
        shortcut: "Control-Option-H"
    ) }
    static var expand: String { tag(
        "Expand Theater",
        does: AppLanguage.text("Show the caption board again."),
        shortcut: "Control-Option-H"
    ) }
    static var paceCue: String { tag(
        "Pace cue",
        does: AppLanguage.text("Behind means talk slower. Caught up means the last sentence is on screen.")
    ) }
    static var latency: String { tag(
        "Latency",
        does: AppLanguage.text("Time until the caption. mic is Listen to first audio. e2e is speech-start to the printed caption. ASR is the speech engine. MT is Apple Translation.")
    ) }
    static var theme: String { tag(
        "Theater theme",
        does: AppLanguage.text("Dark or Light for this window, independent of the main window.")
    ) }
    static var captionFont: String { tag(
        "Caption font",
        does: AppLanguage.text("Typeface for spoken and Show-as.")
    ) }
    static var smaller: String { tag(
        "Smaller captions",
        does: AppLanguage.text("Shrink spoken and Show-as."),
        shortcut: "Control-Option-Minus"
    ) }
    static var larger: String { tag(
        "Larger captions",
        does: AppLanguage.text("Grow spoken and Show-as."),
        shortcut: "Control-Option-Equals"
    ) }
    static var captionSize: String { tag(
        "Size",
        does: AppLanguage.text("Caption size. Type a point size, or use smaller and larger. Both change spoken and Show-as.")
    ) }
    static var copyAll: String { tag(
        "Copy all",
        does: AppLanguage.text("Copy every caption on the board."),
        shortcut: "Control-Option-C"
    ) }
    static var insert: String { tag(
        "Type the board",
        does: TheaterReadiness.insertHelp
    ) }
    static var undo: String { tag(
        "Undo last caption",
        does: AppLanguage.text("Remove the last printed line. Listen can keep going."),
        shortcut: "Control-Option-Z"
    ) }
    static var clear: String { tag(
        "Clear captions",
        does: TheaterReadiness.clearCaptions,
        shortcut: "Control-Option-K"
    ) }
    static var board: String { tag(
        "Settings",
        does: AppLanguage.text("Copy, type, undo, minimize, theme, Overlay or Pop-up, how lines print, position, export, and close. If Listen is on, Close asks before it stops.")
    ) }
    static var popup: String { tag(
        "Pop-up",
        does: AppLanguage.text("Solid floating box you can place over slides or a second display.")
    ) }
    static var overlay: String { tag(
        "Overlay",
        does: AppLanguage.text("Only the caption text, in the rectangle you keep. Hover the Tools bar for Listen and the other controls. It fades when you move away. Slides stay clickable."),
        shortcut: "Control-Option-T pins the tools"
    ) }
    static var screenShare: String { tag(
        TheaterReadiness.screenShareTitle,
        does: TheaterReadiness.screenShare
    ) }
    static var captionPlate: String { tag(
        "Caption plate",
        does: AppLanguage.text("Dark box behind each Overlay line so white slides stay readable.")
    ) }
    static var highContrast: String { tag(
        "High contrast",
        does: AppLanguage.text("Stronger board fill and a halo on caption text.")
    ) }
    static var spokenLine: String { tag(
        "Spoken line",
        does: TheaterReadiness.spokenLineTranslate
    ) }
    static var exportBilingual: String { tag(
        "Bilingual text",
        does: AppLanguage.text("Save spoken and translated lines as a text file.")
    ) }
    static var exportSRT: String { tag(
        "SRT",
        does: AppLanguage.text("Save captions with speech timestamps when available; older or unmatched captions use estimated timing.")
    ) }
    static var exportVTT: String { tag(
        "VTT",
        does: AppLanguage.text("Save captions with speech timestamps when available; older or unmatched captions use estimated timing.")
    ) }
    static var closeTheater: String { tag(
        "Close Theater",
        does: AppLanguage.text("Hides Theater. If the microphone is on, this asks before it stops. Printed lines come back when you open it again. Talk notes stay.")
    ) }
    static var talkNotes: String { tag(
        "Talk notes",
        does: AppLanguage.text("Names locked from notes or a deck. They stay on this Mac.")
    ) }
    static var clearTalkNotes: String { tag(
        "Clear talk notes",
        does: AppLanguage.text("Remove these names so they do not carry into the next talk.")
    ) }
    static var status: String { tag(
        "Status",
        does: AppLanguage.text("Listen, pack, or engine messages for this board.")
    ) }
    static var inbox: String { tag(
        "Incoming",
        does: AppLanguage.text("The last few things you said. Each line leaves this bar when it prints on the board once.")
    ) }
    static var overlayTools: String { tag(
        "Overlay tools",
        does: AppLanguage.text("Show Overlay Listen and board tools."),
        shortcut: "Control-Option-T"
    ) }
    static var keepOverlayText: String { tag(
        "Lock text area",
        does: AppLanguage.text("Save this position and size. Captions stay inside this area, and dragging or resizing is disabled until you unlock it.")
    ) }
    static var unlockOverlayText: String { tag(
        "Unlock text area",
        does: AppLanguage.text("Drag the text area to move it and drag its edges or corners to resize it. Lock text area when it fits.")
    ) }
    static var fillScreen: String { tag(
        "Fill screen",
        does: AppLanguage.text("Cover this display so captions have the whole board.")
    ) }
    static var lowerThird: String { tag(
        "Lower third",
        does: AppLanguage.text("Place the board on the bottom third of this display.")
    ) }
    static var topBand: String { tag(
        "Top band",
        does: AppLanguage.text("Place the board on the top third of this display.")
    ) }
    static var sideColumn: String { tag(
        "Side column",
        does: AppLanguage.text("Place the board as a column on the right of this display.")
    ) }
    static var captionBar: String { tag(
        "Caption bar",
        does: AppLanguage.text("Last few lines along the bottom, like TV captions. Drag the bar to put it somewhere else.")
    ) }

    static func position(_ preset: TheaterPositionPreset) -> String {
        switch preset {
        case .fillScreen: return Self.fillScreen
        case .lowerThird: return Self.lowerThird
        case .topBand: return Self.topBand
        case .sideColumn: return Self.sideColumn
        case .captionBar: return Self.captionBar
        }
    }

    static var linePrint: String { tag(
        "Line print",
        does: AppLanguage.text("How a finished caption arrives. At once, by word, by letter, or fade.")
    ) }
    static var printGap: String { tag(
        "Print gap",
        does: AppLanguage.text("The pause between each word or letter. Fade uses this as how long the line takes to arrive. At once has no gap.")
    ) }

    static func captionFont(current: String) -> String {
        tag("Caption font", does: "Typeface for spoken and Show-as. Now \(current).")
    }

}

struct TheaterHoverHelpValue: Equatable {
    var text: String
    var anchor: CGRect
}

@MainActor
final class TheaterHoverHelpBroker: ObservableObject {
    @Published private(set) var value: TheaterHoverHelpValue?

    func show(_ value: TheaterHoverHelpValue) {
        guard self.value != value else { return }
        self.value = value
    }

    func hide(text: String) {
        guard self.value?.text == text else { return }
        self.value = nil
    }

    func clear() {
        guard self.value != nil else { return }
        self.value = nil
    }
}

private struct TheaterHoverHelpBrokerKey: EnvironmentKey {
    static let defaultValue: TheaterHoverHelpBroker? = nil
}

extension EnvironmentValues {
    var theaterHoverHelp: TheaterHoverHelpBroker? {
        get { self[TheaterHoverHelpBrokerKey.self] }
        set { self[TheaterHoverHelpBrokerKey.self] = newValue }
    }
}

enum TheaterHoverHelp {
    static let space = "theater.hoverHelp"
    static let maxBubbleWidth: CGFloat = 280
    static let margin: CGFloat = 12
    static let gap: CGFloat = 8
    static let revealDelayNanoseconds: UInt64 = 220_000_000

    static func bubbleWidth(containerWidth: CGFloat) -> CGFloat {
        max(0, min(Self.maxBubbleWidth, containerWidth - Self.margin * 2))
    }

    static func bubbleOrigin(
        anchor: CGRect,
        container: CGSize,
        bubbleSize: CGSize
    ) -> CGPoint {
        let maxX = max(Self.margin, container.width - bubbleSize.width - Self.margin)
        let x = min(max(anchor.minX, Self.margin), maxX)
        let below = anchor.maxY + Self.gap
        let above = anchor.minY - Self.gap - bubbleSize.height
        let minY = Self.margin
        let maxY = max(minY, container.height - bubbleSize.height - Self.margin)
        if below <= maxY {
            return CGPoint(x: x, y: below)
        }
        if above >= minY {
            return CGPoint(x: x, y: above)
        }
        return CGPoint(x: x, y: min(max(below, minY), maxY))
    }
}

struct TheaterHoverHelpBubble: View {
    var text: String
    var anchor: CGRect
    var container: CGSize
    @State private var bubbleSize = CGSize(width: 240, height: 44)

    var body: some View {
        let width = TheaterHoverHelp.bubbleWidth(containerWidth: self.container.width)
        let fitted = CGSize(
            width: min(self.bubbleSize.width, width),
            height: self.bubbleSize.height
        )
        let origin = TheaterHoverHelp.bubbleOrigin(
            anchor: self.anchor,
            container: self.container,
            bubbleSize: fitted
        )
        Text(self.text)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Color.white.opacity(0.94))
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: width, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.black.opacity(0.88))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.white.opacity(0.14), lineWidth: 1)
                    }
            }
            .shadow(color: .black.opacity(0.35), radius: 8, y: 2)
            .background {
                GeometryReader { bubble in
                    Color.clear
                        .onAppear { self.adoptBubbleSize(bubble.size) }
                        .onChange(of: bubble.size) { _, size in
                            self.adoptBubbleSize(size)
                        }
                }
            }
            .offset(x: origin.x, y: origin.y)
            .onChange(of: self.text) { _, _ in
                self.bubbleSize = CGSize(width: 240, height: 44)
            }
            .accessibilityIdentifier("theater.window.hoverHelp")
    }

    private func adoptBubbleSize(_ size: CGSize) {
        guard size != .zero, size != self.bubbleSize else { return }
        self.bubbleSize = size
    }
}

private struct TheaterHoverTagModifier: ViewModifier {
    let text: String
    @Environment(\.theaterHoverHelp) private var broker
    @State private var hovering = false
    @State private var revealed = false
    @State private var revealTask: Task<Void, Never>?
    @State private var anchor = CGRect.zero

    func body(content: Content) -> some View {
        content
            .accessibilityHint(self.text)
            .background {
                GeometryReader { proxy in
                    let frame = proxy.frame(in: .named(TheaterHoverHelp.space))
                    Color.clear
                        .onAppear { self.adoptAnchor(frame) }
                        .onChange(of: frame.origin) { _, _ in self.adoptAnchor(frame) }
                        .onChange(of: frame.size) { _, _ in self.adoptAnchor(frame) }
                }
            }
            .onHover { hovering in
                self.hovering = hovering
                self.revealTask?.cancel()
                if hovering {
                    self.revealTask = Task { @MainActor in
                        try? await Task.sleep(nanoseconds: TheaterHoverHelp.revealDelayNanoseconds)
                        guard !Task.isCancelled, self.hovering else { return }
                        self.revealed = true
                        self.publish()
                    }
                } else {
                    self.revealed = false
                    self.broker?.hide(text: self.text)
                }
            }
            .onChange(of: self.text) { _, _ in
                guard self.revealed else { return }
                self.publish()
            }
            .onDisappear {
                self.revealTask?.cancel()
                if self.revealed {
                    self.broker?.hide(text: self.text)
                }
                self.revealed = false
            }
    }

    private func adoptAnchor(_ frame: CGRect) {
        let next = frame.integral
        guard next != self.anchor else { return }
        self.anchor = next
        guard self.revealed else { return }
        self.publish()
    }

    private func publish() {
        guard !self.text.isEmpty else { return }
        self.broker?.show(TheaterHoverHelpValue(text: self.text, anchor: self.anchor))
    }
}

extension View {
    /// Theater paints this on hover. Home and menus still use `.help`.
    @ViewBuilder
    func theaterTag(_ text: String, paints: Bool = true) -> some View {
        if paints {
            self.modifier(TheaterHoverTagModifier(text: text))
        } else {
            self.help(text)
        }
    }
}
