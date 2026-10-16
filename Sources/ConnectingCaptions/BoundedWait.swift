//
//  BoundedWait.swift
//  fluid
//
//  A wait that can actually expire.
//

import Foundation

/// Waits for work that may never return, without inheriting its hang.
///
/// The obvious way to bound a wait is a two-child `withTaskGroup`: one child does
/// the work, one sleeps, and the first to finish wins. That does not work. A task
/// group joins on *every* child before returning, so while the sleep child is free
/// to finish on time, the group still refuses to return until the work child
/// finishes too. When the point of the budget is that the work may be wedged
/// (a non-cooperative CoreML or AVAudioEngine call that ignores cancellation),
/// the group waits forever and the budget is decorative — the code reads bounded
/// and behaves unbounded.
///
/// `completedWithin` races two independent tasks instead and joins on neither, so
/// "stop waiting" never requires the abandoned call to return.
enum BoundedWait {
    /// Returns `true` when `work` finished inside `timeout`, `false` when the
    /// budget expired first. A `false` result means "no answer", not "no work
    /// happened": the abandoned task may still be running.
    static func completedWithin(
        _ timeout: Duration,
        _ work: @escaping @Sendable () async -> Void
    ) async -> Bool {
        let gate = FirstClaimant()
        return await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            let timeoutTask = Task.detached {
                try? await Task.sleep(for: timeout)
                if gate.claim() { continuation.resume(returning: false) }
            }
            Task.detached {
                await work()
                if gate.claim() {
                    continuation.resume(returning: true)
                    // `work` may be a non-cooperative call that ignores
                    // cancellation, but the sleep always honors it, so
                    // cancel the timer rather than leave it running idle.
                    timeoutTask.cancel()
                }
            }
        }
    }
}

/// Hands the resume to whichever racer finishes first, and only to that one.
/// Without it the loser could resume the same continuation a second time, which
/// traps. Internal (not `private`) so other racing call sites, such as the
/// Apple Translation serve loop, can reuse the same claim discipline against a
/// `CheckedContinuation` that carries a real result instead of just `Bool`.
final class FirstClaimant: @unchecked Sendable {
    private let lock = NSLock()
    private var claimed = false

    /// `true` for the first caller only.
    func claim() -> Bool {
        self.lock.withLock {
            if self.claimed { return false }
            self.claimed = true
            return true
        }
    }
}
