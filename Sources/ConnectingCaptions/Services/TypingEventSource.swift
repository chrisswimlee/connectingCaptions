import CoreGraphics
import Foundation

/// Keystrokes Speak and type posts into another app.
/// The default event source mutes the physical keyboard for 0.25s after every
/// synthetic key, so the field stays dead once the line has been typed.
enum TypingEventSource {
    static let hardwareSuppressionSeconds: CFTimeInterval = 0

    private static let source: CGEventSource? = {
        let source = CGEventSource(stateID: .combinedSessionState)
        source?.localEventsSuppressionInterval = hardwareSuppressionSeconds
        return source
    }()

    static func pair(
        virtualKey: CGKeyCode,
        flags: CGEventFlags = []
    ) -> (down: CGEvent, up: CGEvent)? {
        guard let source = self.source,
              let down = CGEvent(keyboardEventSource: source, virtualKey: virtualKey, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: virtualKey, keyDown: false)
        else { return nil }
        down.flags = flags
        up.flags = flags
        let marker = TypingService.synthesizedEventUserData
        down.setIntegerValueField(.eventSourceUserData, value: marker)
        up.setIntegerValueField(.eventSourceUserData, value: marker)
        return (down, up)
    }
}
