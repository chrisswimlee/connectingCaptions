import AppKit
import Combine
import SwiftUI

enum TheaterExportFormat {
    case bilingualText
    case srt
    case vtt
}

@MainActor
final class PresenterCaptionModel: ObservableObject {
    @Published var board = TheaterBoardState()
    @Published var pairLabel: String = ""
    @Published var status: String = ""
    @Published var statusKind: TheaterStatusKind = .idle
    /// Heard lines that have not printed on the board yet.
    @Published var inboxLines: [String] = []
    /// The last inbox line is still open. The board does not draw it.
    @Published var inboxOpenTail = false
    @Published var isListening: Bool = false
    @Published var isPaused: Bool = false
    @Published var canRetryTranslation: Bool = false
    @Published var latencyReadout: String = ""
    @Published var compactLatencyReadout: String = ""
    @Published var paceCueLabel: String = ""
    @Published var paceCueCompactLabel: String = ""
    @Published var paceCueKind: String = ""
    @Published var showCloseConfirmation: Bool = false
    /// True while the export save panel is open. The Board menu reads Saved.
    @Published var exportShowsSaved: Bool = false
    /// Session-only. Overlay starts unpinned (text only). Pop-up, minimize, and close clear it.
    @Published var overlayToolsPinned: Bool = false
    /// True while Overlay is waiting for a caption rectangle. Clicks stay on the window.
    @Published var isPlacingOverlay: Bool = false
    /// The live frame would survive Overlay. Keep text here stays off until this is true.
    @Published var canConfirmOverlayPlacement: Bool = false
    /// Pointer is over the fading Overlay tool bar.
    @Published var overlayDockEngaged: Bool = false
    /// A menu, popover, or alert from that bar is open, so the bar stays up.
    @Published var overlayDockHolding: Bool = false
    /// Laid-out height of the Overlay tool bar, including its outer padding.
    @Published var overlayDockHeight: CGFloat = 64
}

enum TheaterTypeface: String, CaseIterable, Identifiable {
    case system
    case helveticaNeue = "Helvetica Neue"
    case avenirNext = "Avenir Next"
    case georgia = "Georgia"
    case palatino = "Palatino"
    case menlo = "Menlo"
    case gothicNeo = "Apple SD Gothic Neo"
    case thonburi = "Thonburi"

    var id: String { self.rawValue }

    var displayName: String {
        self == .system ? "System" : self.rawValue
    }

    static func resolved(_ stored: String) -> TheaterTypeface {
        Self(rawValue: stored.trimmingCharacters(in: .whitespacesAndNewlines)) ?? .system
    }

    var postScriptName: String? {
        switch self {
        case .system:
            return nil
        case .helveticaNeue:
            return "HelveticaNeue"
        case .avenirNext:
            return "AvenirNext-DemiBold"
        case .georgia:
            return "Georgia"
        case .palatino:
            return "Palatino-Roman"
        case .menlo:
            return "Menlo-Regular"
        case .gothicNeo:
            return "AppleSDGothicNeo-SemiBold"
        case .thonburi:
            return "Thonburi"
        }
    }

    func font(size: CGFloat, weight: Font.Weight) -> Font {
        if let name = self.postScriptName {
            return .custom(name, size: size)
        }
        return .system(size: size, weight: weight)
    }

    func nsFont(size: CGFloat, weight: NSFont.Weight) -> NSFont {
        if let name = self.postScriptName, let named = NSFont(name: name, size: size) {
            return named
        }
        if self != .system, let family = NSFontManager.shared.font(
            withFamily: self.rawValue,
            traits: [],
            weight: 7,
            size: size
        ) {
            return family
        }
        return .systemFont(ofSize: size, weight: weight)
    }
}

struct TheaterFlowLine: Equatable, Identifiable {
    let id: String
    let text: String
    let source: String
    let isCurrent: Bool
    let isDraft: Bool
    var failed: Bool = false
}

enum TheaterPresentationStyle: String, CaseIterable, Identifiable {
    case popup
    case transparent

    var id: String { self.rawValue }

    var displayName: String {
        switch self {
        case .popup: return "Pop-up"
        case .transparent: return "Overlay"
        }
    }

    var symbol: String {
        switch self {
        case .popup: return "rectangle.on.rectangle"
        case .transparent: return "rectangle.dashed"
        }
    }

    var help: String {
        switch self {
        case .popup: return TheaterReadiness.popupStyle
        case .transparent: return TheaterReadiness.transparentStyle
        }
    }

    var toggled: TheaterPresentationStyle {
        self == .popup ? .transparent : .popup
    }

    static func resolved(_ stored: String?) -> TheaterPresentationStyle {
        let trimmed = stored?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return Self(rawValue: trimmed) ?? .popup
    }
}

enum TheaterAppearance: String, CaseIterable, Identifiable {
    case dark
    case light

    var id: String { self.rawValue }

    var displayName: String {
        switch self {
        case .dark: return "Dark"
        case .light: return "Light"
        }
    }

    var toggleSymbol: String {
        switch self {
        case .dark: return "sun.max.fill"
        case .light: return "moon.fill"
        }
    }

    var toggleHelp: String {
        switch self {
        case .dark: return "Light mode"
        case .light: return "Dark mode"
        }
    }

    var colorScheme: ColorScheme {
        self == .light ? .light : .dark
    }

    var toggled: TheaterAppearance {
        self == .dark ? .light : .dark
    }

    static func resolved(_ stored: String?) -> TheaterAppearance {
        let trimmed = stored?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return Self(rawValue: trimmed) ?? .dark
    }
}
