import Foundation

extension SettingsStore {
    /// This Mac was signed in before the paid release and already had the app after that. Listen stays on.
    var keepsEarlierCopy: Bool {
        EarlyInstallAccess.currentDecision()
    }
}
