import Foundation

/// Home, the menu bar, and the Theater menu always open Theater.
/// Only the Caption Listen shortcut may open the quick-capture chip.
enum CaptionListenRoute {
    static func presentation(
        invokedFromShortcut: Bool,
        setting: CaptionPresentation
    ) -> CaptionPresentation {
        invokedFromShortcut ? setting : .theater
    }

    static func showsTheaterWindow(_ presentation: CaptionPresentation) -> Bool {
        presentation == .theater
    }

    /// Mirrors the `beginSession` gate that reopens a hidden or minimized Theater.
    static func shouldOpenTheaterOnBegin(
        kind: TranslationListenKind,
        presentation: CaptionPresentation,
        windowEnabled: Bool,
        minimized: Bool
    ) -> Bool {
        kind == .captions
            && self.showsTheaterWindow(presentation)
            && (!windowEnabled || minimized)
    }
}

struct QuickCaptureChipContent: Equatable {
    var finished: String
    var live: String
    var failure: String

    var isFailure: Bool { !self.failure.isEmpty }

    static func make(
        committedLast: String?,
        overlay: String,
        statusText: String,
        statusKind: TheaterStatusKind
    ) -> QuickCaptureChipContent {
        if statusKind == .failure {
            let failure = statusText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !failure.isEmpty {
                return QuickCaptureChipContent(finished: "", live: "", failure: failure)
            }
        }
        let finished = committedLast?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return QuickCaptureChipContent(
            finished: finished,
            live: overlay.trimmingCharacters(in: .whitespacesAndNewlines),
            failure: ""
        )
    }
}

enum QuickCaptureVisibility {
    static func isShown(
        presentation: CaptionPresentation,
        listenKind: TranslationListenKind?,
        isSessionActive: Bool,
        isFinishing: Bool,
        hasFailure: Bool
    ) -> Bool {
        guard presentation == .quickCapture else { return false }
        if hasFailure { return true }
        return listenKind == .captions && (isSessionActive || isFinishing)
    }
}
