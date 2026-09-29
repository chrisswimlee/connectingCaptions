import AppKit
import AVFoundation
import Foundation

/// Theater asks for the microphone. Voice and Translate both use it.
enum MicrophoneAccess {
    static let deniedCopy =
        "Allow the microphone in System Settings."

    /// Shown when macOS has already refused the microphone, so Allow will not ask again.
    static let deniedSettingsCopy =
        "Denied. Open Settings and turn the microphone on."

    /// Shown when the privacy prompt or status read does not answer. This is not a denial.
    static let promptTimedOutCopy =
        "The microphone prompt did not finish. Open Settings and turn the microphone on."

    static let moveToApplicationsCopy =
        "Move Connecting Captions into Applications, then open that copy. Allow cannot stick while the app is still the downloaded copy."

    /// A notarized app opened from the zip runs from a temporary path.
    /// Microphone Allow is granted to that path, then the next launch asks again.
    static var isOpenedFromDownload: Bool {
        Bundle.main.bundlePath.contains("/AppTranslocation/")
    }

    @MainActor
    static func revealDownloadedApp() {
        NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
        NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications"))
    }

    static func status() -> AVAuthorizationStatus {
        AVCaptureDevice.authorizationStatus(for: .audio)
    }

    /// `authorizationStatus` and `requestAccess` can sit inside Core Audio or
    /// the privacy service. Keep that wait off the main thread so setup and
    /// Quit still run. Nil means the read did not answer. Callers keep the
    /// last real status instead of pretending the user was never asked.
    static func statusOffMain() async -> AVAuthorizationStatus? {
        await withCheckedContinuation { continuation in
            let gate = StatusReply()
            DispatchQueue.global(qos: .userInitiated).async {
                gate.finish(continuation, AVCaptureDevice.authorizationStatus(for: .audio))
            }
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 5) {
                gate.finish(continuation, nil)
            }
        }
    }

    /// Nil means the system prompt did not answer. The caller should send the
    /// user to System Settings instead of waiting.
    static func requestAccessOffMain(timeoutNanoseconds: UInt64 = 20_000_000_000) async -> Bool? {
        await withCheckedContinuation { continuation in
            let gate = PromptReply()
            DispatchQueue.global(qos: .userInitiated).async {
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    gate.finish(continuation, granted)
                }
            }
            DispatchQueue.global(qos: .userInitiated).asyncAfter(
                deadline: .now() + .nanoseconds(Int(timeoutNanoseconds))
            ) {
                gate.finish(continuation, nil)
            }
        }
    }

    static func isAuthorized(_ status: AVAuthorizationStatus) -> Bool {
        status == .authorized
    }

    static func isDenied(_ status: AVAuthorizationStatus) -> Bool {
        status == .denied || status == .restricted
    }

    static func failureCopy(detail: String) -> String {
        detail.isEmpty ? self.deniedCopy : detail
    }

    static func isMicrophoneFailure(_ text: String) -> Bool {
        text == self.deniedCopy
            || text == self.deniedSettingsCopy
            || text == self.promptTimedOutCopy
            || text == self.moveToApplicationsCopy
    }

    /// A timed-out read keeps `currentStatus` and does not invent a failure.
    /// A stale "not asked yet" must not wipe a grant the app already recorded.
    /// A real denial replaces it.
    static func resolvedDetail(
        read: AVAuthorizationStatus?,
        keeping previous: String,
        currentStatus: AVAuthorizationStatus
    ) -> MicrophoneAccessRead {
        guard let read else {
            if currentStatus == .authorized {
                return MicrophoneAccessRead(status: .authorized, detail: "")
            }
            if self.isDenied(currentStatus) {
                let detail = previous.isEmpty ? self.deniedSettingsCopy : previous
                return MicrophoneAccessRead(status: currentStatus, detail: detail)
            }
            return MicrophoneAccessRead(status: currentStatus, detail: previous)
        }
        if read == .authorized {
            return MicrophoneAccessRead(status: .authorized, detail: "")
        }
        if self.isDenied(read) {
            return MicrophoneAccessRead(status: read, detail: self.deniedSettingsCopy)
        }
        if currentStatus == .authorized {
            return MicrophoneAccessRead(status: .authorized, detail: "")
        }
        return MicrophoneAccessRead(status: .notDetermined, detail: "")
    }

    /// The system prompt itself did not answer. A slow status check must not call this.
    @MainActor
    static func notePromptTimedOut(_ asr: ASRService) {
        if asr.micStatus == .authorized || self.isDenied(asr.micStatus) { return }
        asr.microphoneAccessDetail = self.promptTimedOutCopy
    }

    @MainActor
    static func refresh(_ asr: ASRService) async {
        asr.recordMicrophoneAccessRead(await self.statusOffMain())
    }

    /// Prompts when the grant is still undetermined. Denied stays denied.
    /// A prompt that does not answer opens Settings and leaves a visible reason.
    @MainActor
    static func authorize(updating asr: ASRService) async -> Bool {
        await self.refresh(asr)
        if self.isAuthorized(asr.micStatus) { return true }
        if self.isDenied(asr.micStatus) { return false }

        guard let granted = await self.requestAccessOffMain() else {
            self.notePromptTimedOut(asr)
            asr.openSystemSettingsForMic()
            return false
        }
        await self.applyPromptResult(granted, to: asr)
        self.prewarmAfterGrant(asr)
        return asr.micPermissionGranted
    }

    /// Preparing the input can sit inside Core Audio. Listen must not wait on
    /// that, or a stuck prepare leaves every later Listen click doing nothing.
    @MainActor
    static func prewarmAfterGrant(_ asr: ASRService) {
        guard asr.micPermissionGranted else { return }
        Task { @MainActor in
            await asr.prewarmConfiguredAudioCaptureIfPossible(reason: "permission_granted")
        }
    }

    @MainActor
    static func applyPromptResult(_ granted: Bool, to asr: ASRService) async {
        if let status = await self.statusOffMain(), status != .notDetermined {
            asr.recordMicrophoneAccessRead(status)
        } else {
            asr.recordMicrophoneAccessRead(granted ? .authorized : .denied)
        }
    }
}

struct MicrophoneAccessRead: Equatable {
    var status: AVAuthorizationStatus
    var detail: String
}

/// Resumes a microphone status read once. The timeout and the system call can both finish.
private final class StatusReply: @unchecked Sendable {
    private let lock = NSLock()
    private var resumed = false

    func finish(_ continuation: CheckedContinuation<AVAuthorizationStatus?, Never>, _ status: AVAuthorizationStatus?) {
        self.lock.lock()
        let shouldResume = self.resumed == false
        self.resumed = true
        self.lock.unlock()
        guard shouldResume else { return }
        continuation.resume(returning: status)
    }
}

/// Resumes the microphone prompt once. The timeout and the system callback can both finish.
private final class PromptReply: @unchecked Sendable {
    private let lock = NSLock()
    private var resumed = false

    func finish(_ continuation: CheckedContinuation<Bool?, Never>, _ granted: Bool?) {
        self.lock.lock()
        let shouldResume = self.resumed == false
        self.resumed = true
        self.lock.unlock()
        guard shouldResume else { return }
        continuation.resume(returning: granted)
    }
}
