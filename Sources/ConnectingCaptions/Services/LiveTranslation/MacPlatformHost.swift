import AppKit
import AVFoundation

/// macOS windows, pasteboard, trackpad click, and microphone permission.
final class MacPlatformHost: ConnectingCaptionsPlatformHost {
    func performAlignmentHaptic() {
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }

    func copyToPasteboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    var isOpenedFromDownload: Bool {
        Bundle.main.bundlePath.contains("/AppTranslocation/")
    }

    func revealDownloadedApp() {
        NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
        NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications"))
    }

    func microphoneAuthorizationRawValue() -> Int {
        Int(AVCaptureDevice.authorizationStatus(for: .audio).rawValue)
    }

    func requestMicrophoneAccess() async -> Bool? {
        await MicrophoneAccess.requestAccessOffMain()
    }
}
