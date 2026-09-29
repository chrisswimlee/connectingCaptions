import Foundation

/// Centralized startup gate for any code paths that can trigger CoreAudio initialization.
///
/// Why this exists:
/// - SwiftUI/AttributeGraph does not expose a reliable "initial metadata processing is finished" signal.
/// - CoreAudio/AVFoundation initialization can race that work during app launch and crash with EXC_BAD_ACCESS.
/// - A single shared gate makes it much harder for new call-sites (e.g., Settings views) to accidentally
///   trigger CoreAudio too early.
actor AudioStartupGate {
    static let shared = AudioStartupGate()

    private var isOpen: Bool = false
    private var openTask: Task<Void, Never>?
    private var waiters: [CheckedContinuation<Void, Never>] = []

    /// Schedule opening the gate once. Safe to call multiple times.
    func scheduleOpenAfterInitialUISettled(delayNanoseconds: UInt64 = 2_000_000_000) {
        guard self.isOpen == false, self.openTask == nil else { return }

        self.openTask = Task { @MainActor [weak self] in
            guard let self else { return }

            // Give SwiftUI a couple runloop turns to finish initial layout/metadata passes.
            await Task.yield()
            await Task.yield()

            // Safety delay for slower / loaded systems (e.g., long uptime, heavy background load).
            try? await Task.sleep(nanoseconds: delayNanoseconds)

            let pending = await self.markOpen()
            // Resume off this MainActor task. A waiter that continues on the
            // main thread must not run nested inside the task that opened the gate.
            Task.detached {
                pending.resume()
            }
        }
    }

    /// Await until the gate is open. Returns immediately if already open.
    func waitUntilOpen() async {
        if self.isOpen { return }

        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            if self.isOpen {
                cont.resume()
            } else {
                self.waiters.append(cont)
            }
        }
    }

    private func markOpen() -> GateWaiters {
        guard self.isOpen == false else { return GateWaiters([]) }
        self.isOpen = true

        let pending = self.waiters
        self.waiters.removeAll(keepingCapacity: false)
        return GateWaiters(pending)
    }
}

/// Resumes gate waiters away from both the audio actor and the main thread.
private final class GateWaiters: @unchecked Sendable {
    private let resumeAll: @Sendable () -> Void

    init(_ pending: [CheckedContinuation<Void, Never>]) {
        self.resumeAll = {
            pending.forEach { $0.resume() }
        }
    }

    func resume() {
        self.resumeAll()
    }
}
