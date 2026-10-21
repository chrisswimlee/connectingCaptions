import Foundation

/// ASR feeds this bus. Theater Listen on macOS still uses `ASRService`;
/// iOS implements its own capture and calls `handlePartial`.
@MainActor
public protocol PartialTranscriptSink: AnyObject {
    func handlePartial(_ text: String)
    func handleEndOfUtterance()
}

/// Presenter chords shared by macOS Control-Option and iOS hardware shortcuts.
public enum TheaterPresenterAction: String, Equatable, Sendable, CaseIterable {
    case toggleVisible
    case togglePause
    case clear
    case copy
    case undo
    case fontLarger
    case fontSmaller
    case toggleTools
    case listen
    case retry

    public var repeats: Bool {
        self == .fontLarger || self == .fontSmaller
    }

    public var keyEquivalent: String {
        switch self {
        case .toggleVisible: return "h"
        case .togglePause: return "p"
        case .clear: return "k"
        case .copy: return "c"
        case .undo: return "z"
        case .fontLarger: return "="
        case .fontSmaller: return "-"
        case .toggleTools: return "t"
        case .listen: return "l"
        case .retry: return "r"
        }
    }

    public static let fontStep = 2
}
