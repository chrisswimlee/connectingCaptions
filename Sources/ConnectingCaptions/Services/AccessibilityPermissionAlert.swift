import AppKit
import Combine

/// Accessibility permission is a manual System Settings toggle, not a system
/// dialog we can re-trigger. Once macOS has shown its one-time prompt, a
/// denial or dismissal leaves typing (dictation, Translate+Insert) and the
/// global hotkey silently doing nothing with no in-app explanation. This
/// surfaces that failure once, instead of only logging it to a debug console.
@MainActor
final class AccessibilityPermissionAlert: ObservableObject {
    static let shared = AccessibilityPermissionAlert()

    @Published private(set) var isPresented = false
    private var lastShown: Date?
    private let minimumInterval: TimeInterval = 30

    private init() {}

    func noteDenied() {
        guard !SettingsStore.isRunningTests else { return }
        guard !AXIsProcessTrusted() else { return }
        let now = Date()
        if let lastShown, now.timeIntervalSince(lastShown) < self.minimumInterval { return }
        self.lastShown = now
        self.isPresented = true
    }

    func dismiss() {
        self.isPresented = false
    }

    func openSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
        self.dismiss()
    }
}
