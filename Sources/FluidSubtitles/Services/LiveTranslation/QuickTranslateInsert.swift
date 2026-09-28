import Foundation

/// What the Listen, then type bar shows.
/// The bar shows the line that will be typed. The keyboard stays in the app
/// captured at the start of the shortcut.
enum QuickTranslateInsertPhase: Equatable {
    case hidden
    case starting
    case listening
    case typing
}

struct QuickTranslateInsertChip: Equatable {
    var title: String
    var line: String
    /// The line is Show-as, or the same-language sentence, and is what Stop types.
    var lineIsReady: Bool
}

/// Armed means the shortcut fired and the microphone is not in the session yet.
/// Joined means this Listen reached the insert session, so a later idle state
/// must not leave the bar on Starting.
struct QuickTranslateInsertSession: Equatable {
    var armed = false
    var joined = false

    mutating func disarm() {
        self.armed = false
        self.joined = false
    }

    mutating func note(
        listenKind: TranslationListenKind?,
        isSessionActive: Bool,
        isFinishing: Bool
    ) -> QuickTranslateInsertPhase {
        // A stop that never became this Listen must not leave the bar on Starting.
        if isFinishing, listenKind != .insert {
            self.armed = false
            self.joined = false
        }
        let inInsert = listenKind == .insert && (isSessionActive || isFinishing)
        if inInsert {
            self.joined = true
        } else if self.joined || listenKind == .captions {
            self.joined = false
            self.armed = false
        }
        return QuickTranslateInsert.phase(
            armed: self.armed,
            listenKind: listenKind,
            isSessionActive: isSessionActive,
            isFinishing: isFinishing
        )
    }
}

enum QuickTranslateInsert {
    static let startingLine = "Starting…"
    static let typingLine = "Typing…"

    static func phase(
        armed: Bool,
        listenKind: TranslationListenKind?,
        isSessionActive: Bool,
        isFinishing: Bool
    ) -> QuickTranslateInsertPhase {
        if listenKind == .insert, isFinishing {
            return .typing
        }
        if listenKind == .insert, isSessionActive {
            return .listening
        }
        if armed, listenKind != .captions {
            return .starting
        }
        return .hidden
    }

    static func pairTitle(sourceName: String, targetName: String, sameLanguage: Bool) -> String {
        if sameLanguage || sourceName == targetName {
            return sourceName
        }
        return "\(sourceName) → \(targetName)"
    }

    static func idleLine(activation: HotkeyActivationMode) -> String {
        switch activation {
        case .hold:
            return "Speak. Release to type."
        case .toggle:
            return "Speak. Press the shortcut again to type."
        case .automatic:
            return "Speak. Release, or press again, to type."
        }
    }

    static func chip(
        phase: QuickTranslateInsertPhase,
        activation: HotkeyActivationMode,
        sourceName: String,
        targetName: String,
        sameLanguage: Bool,
        ready: String,
        showAs: String,
        spoken: String
    ) -> QuickTranslateInsertChip {
        let title = self.pairTitle(
            sourceName: sourceName,
            targetName: targetName,
            sameLanguage: sameLanguage
        )
        switch phase {
        case .hidden:
            return QuickTranslateInsertChip(title: title, line: "", lineIsReady: false)
        case .starting:
            return QuickTranslateInsertChip(title: title, line: self.startingLine, lineIsReady: false)
        case .typing, .listening:
            return self.liveChip(
                title: title,
                phase: phase,
                activation: activation,
                sameLanguage: sameLanguage,
                ready: ready,
                showAs: showAs,
                spoken: spoken
            )
        }
    }

    private static func liveChip(
        title: String,
        phase: QuickTranslateInsertPhase,
        activation: HotkeyActivationMode,
        sameLanguage: Bool,
        ready: String,
        showAs: String,
        spoken: String
    ) -> QuickTranslateInsertChip {
        let accepted = ready.trimmingCharacters(in: .whitespacesAndNewlines)
        let show = showAs.trimmingCharacters(in: .whitespacesAndNewlines)
        let said = spoken.trimmingCharacters(in: .whitespacesAndNewlines)
        if !accepted.isEmpty {
            let line = self.appended(accepted, show)
            return QuickTranslateInsertChip(title: title, line: line, lineIsReady: true)
        }
        if !show.isEmpty {
            return QuickTranslateInsertChip(title: title, line: show, lineIsReady: true)
        }
        if sameLanguage, !said.isEmpty {
            return QuickTranslateInsertChip(title: title, line: said, lineIsReady: true)
        }
        if !said.isEmpty {
            return QuickTranslateInsertChip(title: title, line: said, lineIsReady: false)
        }
        let idle = phase == .typing ? self.typingLine : self.idleLine(activation: activation)
        return QuickTranslateInsertChip(title: title, line: idle, lineIsReady: false)
    }

    /// Join the way the typed document does. A short Show-as line can end
    /// like the previous sentence ("good."), so a suffix check would drop it.
    private static func appended(_ accepted: String, _ show: String) -> String {
        guard !show.isEmpty else { return accepted }
        let last = accepted.split(whereSeparator: \.isNewline).last
            .map { $0.trimmingCharacters(in: .whitespaces) }
        if last == show {
            return accepted
        }
        return accepted + "\n" + show
    }
}
