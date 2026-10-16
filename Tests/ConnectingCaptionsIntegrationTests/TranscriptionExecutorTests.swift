@testable import ConnectingCaptions_Debug
import XCTest

final class TranscriptionExecutorTests: XCTestCase {
    /// A wedged operation (stuck on a continuation that cancellation alone can't resume)
    /// must not park cancelAndAwaitPending forever: it should give up after its timeout.
    /// The continuation is released at the end so the test leaves no suspended task behind.
    func testCancelAndAwaitPendingReturnsAfterTimeoutOnWedgedOperation() async throws {
        let executor = TranscriptionExecutor()
        let hang = HangBox()

        let runTask = Task {
            _ = try? await executor.run { () async throws in
                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    hang.store(continuation)
                }
            }
        }
        while hang.isStored == false {
            await Task.yield()
        }

        let start = ContinuousClock.now
        let drained = await executor.cancelAndAwaitPending(timeout: .milliseconds(200))
        XCTAssertFalse(drained, "A timeout must tell the caller to retire the provider instance")
        let elapsed = start.duration(to: .now)

        XCTAssertLessThan(
            elapsed,
            .seconds(2),
            "cancelAndAwaitPending must bound its wait instead of hanging on a wedged operation"
        )

        hang.resume()
        _ = await runTask.result
    }

    /// An operation that is merely slow (and, like the wedged case above, not
    /// cancellation-aware) must still be waited out as long as it finishes
    /// inside the timeout, rather than being abandoned early.
    func testCancelAndAwaitPendingWaitsForASlowOperationToFinish() async throws {
        let executor = TranscriptionExecutor()
        let recorder = CompletionRecorder()
        let started = XCTestExpectation(description: "operation started")

        let runTask = Task {
            _ = try? await executor.run { () async throws in
                started.fulfill()
                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) {
                        continuation.resume()
                    }
                }
                await recorder.markCompleted()
            }
        }
        await fulfillment(of: [started], timeout: 2)

        let drained = await executor.cancelAndAwaitPending(timeout: .seconds(5))
        XCTAssertTrue(drained, "A completed operation allows healthy provider reuse")

        let completed = await recorder.completed
        XCTAssertTrue(completed, "cancelAndAwaitPending should wait for an in-flight operation to finish, not abandon it early")
        runTask.cancel()
    }

    /// The Theater confirm re-decode passes a budget. A decode wedged inside a
    /// non-cooperative provider call must not park the caption path that awaits it:
    /// `run` gives up at the budget and throws instead of waiting forever.
    func testBoundedRunGivesUpOnAWedgedOperation() async throws {
        let executor = TranscriptionExecutor()
        let hang = HangBox()

        let runTask = Task { () -> String in
            do {
                _ = try await executor.run(timeoutNanoseconds: 200_000_000) { () async throws in
                    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                        hang.store(continuation)
                    }
                }
                return "completed"
            } catch is TranscriptionExecutorError {
                return "timedOut"
            } catch {
                return "threw: \(error)"
            }
        }
        while hang.isStored == false {
            await Task.yield()
        }

        let startedAt = ContinuousClock.now
        let outcome = await runTask.value
        let elapsed = startedAt.duration(to: .now)

        XCTAssertEqual(outcome, "timedOut")
        XCTAssertLessThan(elapsed, .seconds(2), "A bounded run must stop waiting instead of hanging")

        hang.resume()
    }

    /// A budget is a ceiling on the wait, not a truncation of the decode: work that
    /// finishes inside its budget still returns its value rather than being dropped.
    func testBoundedRunWaitsForAnOperationThatFinishesInsideItsBudget() async throws {
        let executor = TranscriptionExecutor()

        let text = try await executor.run(timeoutNanoseconds: 5_000_000_000) { () async throws -> String in
            try await Task.sleep(nanoseconds: 100_000_000)
            return "오늘 모델을 학습했습니다."
        }

        XCTAssertEqual(text, "오늘 모델을 학습했습니다.")
    }

    /// `run` serializes, so a queued decode also waits on the one ahead of it.
    /// That queue wait is inside the same budget, so one wedged decode cannot
    /// quietly make every later decode on the session unbounded as well.
    func testQueuedOperationGivesUpWhileTheOperationAheadIsStillWedged() async throws {
        let executor = TranscriptionExecutor()
        let hang = HangBox()

        let wedged = Task {
            _ = try? await executor.run(timeoutNanoseconds: 200_000_000) { () async throws in
                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    hang.store(continuation)
                }
            }
        }
        while hang.isStored == false {
            await Task.yield()
        }

        let startedAt = ContinuousClock.now
        let queued = try? await executor.run(timeoutNanoseconds: 300_000_000) { () async throws -> String in
            "never reached"
        }
        let elapsed = startedAt.duration(to: .now)

        XCTAssertNil(queued, "A queued decode must not inherit an unbounded wait on the decode ahead of it")
        XCTAssertLessThan(elapsed, .seconds(3))

        hang.resume()
        _ = await wedged.value
    }
    /// A budget belongs to one wait, not to the whole chain. Once a budget has
    /// expired the provider that expired it is still holding the chain, so the
    /// next bounded wait is refused at once: spending a second budget on a queue
    /// that cannot drain would only move the stall onto every later tick.
    func testSecondBoundedRunIsRefusedWhileTheChainIsWedged() async throws {
        let executor = TranscriptionExecutor()
        let hang = HangBox()

        let wedged = Task {
            _ = try? await executor.run(timeoutNanoseconds: 200_000_000) { () async throws in
                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    hang.store(continuation)
                }
            }
        }
        while hang.isStored == false {
            await Task.yield()
        }
        _ = await wedged.value

        let startedAt = ContinuousClock.now
        let second = try? await executor.run(timeoutNanoseconds: 200_000_000) { "a caption nobody hears" }
        let elapsed = startedAt.duration(to: .now)

        XCTAssertNil(second, "a refused decode reports nothing, not a caption")
        XCTAssertLessThan(elapsed, .milliseconds(50), "the refusal must not spend a second budget")

        hang.resume()
    }

    /// The same wedge, one listen later. `start()` drops the previous listen's
    /// chain before a new listen begins, so a healthy provider is re-tested
    /// instead of queueing behind a call that may never return.
    func testADroppedChainDoesNotInheritThePreviousWedge() async throws {
        let executor = TranscriptionExecutor()
        let hang = HangBox()

        let wedged = Task {
            _ = try? await executor.run(timeoutNanoseconds: 200_000_000) { () async throws in
                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    hang.store(continuation)
                }
            }
        }
        while hang.isStored == false {
            await Task.yield()
        }
        _ = await wedged.value

        await executor.cancelAndAwaitPending(timeout: .milliseconds(100))

        let startedAt = ContinuousClock.now
        let text = try? await executor.run(timeoutNanoseconds: 2_000_000_000) { "next listen" }
        let elapsed = startedAt.duration(to: .now)

        XCTAssertEqual(
            text,
            "next listen",
            "a new listen re-tests the provider instead of queueing behind the old wedge"
        )
        XCTAssertLessThan(elapsed, .seconds(1), "the new listen must not wait out the old chain first")

        hang.resume()
    }
}

private actor CompletionRecorder {
    private(set) var completed = false

    func markCompleted() {
        self.completed = true
    }
}

/// Holds a continuation for a simulated non-cooperative hang so the test can
/// release it during cleanup instead of leaking a permanently suspended task.
private final class HangBox: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Never>?

    var isStored: Bool {
        self.lock.withLock { self.continuation != nil }
    }

    func store(_ continuation: CheckedContinuation<Void, Never>) {
        self.lock.withLock { self.continuation = continuation }
    }

    func resume() {
        let continuation = self.lock.withLock { () -> CheckedContinuation<Void, Never>? in
            defer { self.continuation = nil }
            return self.continuation
        }
        continuation?.resume()
    }
}
