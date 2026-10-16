//
//  ASRService+Types.swift
//  fluid
//
//  ASR helpers that sit beside ASRService.
//

import Foundation
#if arch(arm64)
import FluidAudio
#endif

/// Raised when a caller stops waiting on a pending transcription rather than
/// letting it run to completion. A call wedged inside a non-cooperative CoreML
/// invocation cannot be cancelled, so abandoning the wait is the only way to keep
/// the caption path moving.
nonisolated enum TranscriptionExecutorError: LocalizedError {
    case timedOut
    /// Refused before the operation ever started, because an earlier call on
    /// this chain already used its whole budget. Distinct from `.timedOut`
    /// (which means this specific call spent its own budget), so a caller can
    /// tell "never got a chance" apart from "ran and gave up."
    case chainAlreadyWedged

    var errorDescription: String? {
        switch self {
        case .timedOut:
            "The pending transcription was still running when its budget expired."
        case .chainAlreadyWedged:
            "The transcription chain was already wedged by an earlier call that used its whole budget."
        }
    }
}

/// Serializes transcription operations and lets teardown cancel the real queued work.
actor TranscriptionExecutor {
    var lastTask: Task<Void, Never>?
    var operationCancellations: [UUID: () -> Void] = [:]

    /// Set when a budget expires. The abandoned call still holds the serialized
    /// chain, so every later decode on that chain would queue behind a provider
    /// that may never return.
    private var isChainWedged = false
    private var chainGeneration: UInt64 = 0

    /// Waits for one operation behind the serialized chain.
    ///
    /// Pass `timeoutNanoseconds` to bound that wait. It covers the queue wait as
    /// well as the decode, because a queued operation waits on the one before it.
    /// On expiry the operation is cancelled (best effort) and
    /// `TranscriptionExecutorError.timedOut` is thrown.
    ///
    /// The chain is deliberately left intact on expiry, so a later operation still
    /// queues rather than overlapping a provider that may still be busy: two
    /// decodes sharing one incremental provider would index the next window against
    /// samples the wedged call already accepted. Once the chain is known wedged,
    /// a bounded caller is refused immediately instead of spending its own budget
    /// on a queue that cannot drain; an unbounded caller keeps waiting, because
    /// that is what an unbounded wait promises.
    func run<T>(
        benchmarkSessionID: Int? = nil,
        timeoutNanoseconds: UInt64? = nil,
        _ operation: @escaping () async throws -> T
    ) async throws -> T {
        logTranscriptionExecutorPhase("entered", sessionID: benchmarkSessionID)
        if timeoutNanoseconds != nil, self.isChainWedged {
            logTranscriptionExecutorPhase("skipped_wedged_chain", sessionID: benchmarkSessionID)
            DebugLogger.shared.warning(
                "TranscriptionExecutor refused a transcription: the chain was already "
                    + "wedged by a call that used its whole budget.",
                source: "TranscriptionExecutor"
            )
            throw TranscriptionExecutorError.chainAlreadyWedged
        }
        let previous = self.lastTask
        let generation = self.chainGeneration
        let operationID = UUID()
        let task = Task<T, Error> {
            logTranscriptionExecutorPhase("task_started", sessionID: benchmarkSessionID)
            _ = await previous?.result
            logTranscriptionExecutorPhase("previous_finished", sessionID: benchmarkSessionID)
            try Task.checkCancellation()
            return try await operation()
        }
        self.operationCancellations[operationID] = { task.cancel() }
        self.lastTask = Task { _ = try? await task.value }
        defer { self.operationCancellations.removeValue(forKey: operationID) }

        guard let timeoutNanoseconds else {
            return try await task.value
        }
        // Race the wait against the budget. Neither racer is joined, so a budget
        // that expires can actually end the wait even though the abandoned call
        // never returns (see `BoundedWait`).
        let didComplete = await BoundedWait.completedWithin(
            Duration.nanoseconds(Int(timeoutNanoseconds))
        ) {
            _ = try? await task.value
        }
        guard didComplete else {
            if generation == self.chainGeneration { self.isChainWedged = true }
            task.cancel()
            DebugLogger.shared.warning(
                "TranscriptionExecutor gave up waiting after \(timeoutNanoseconds / 1_000_000) ms; "
                    + "abandoning the pending transcription",
                source: "TranscriptionExecutor"
            )
            throw TranscriptionExecutorError.timedOut
        }
        return try await task.value
    }

    /// Bounds the wait on a pending operation. If `operation()` is stuck on a
    /// non-cooperative call (e.g. a wedged FluidAudio/CoreML invocation),
    /// cancellation alone won't unblock it, so this gives up waiting after
    /// `timeout` rather than parking the caller forever. The orphaned task is
    /// detached from `lastTask`; it may keep running in the background.
    /// Returns false on timeout: the caller must retire its provider instance
    /// before using the newly cleared executor chain.
    @discardableResult
    func cancelAndAwaitPending(timeout: Duration = .seconds(5)) async -> Bool {
        var didDrain = true
        for cancel in self.operationCancellations.values {
            cancel()
        }
        if let lastTask {
            let didFinish = await BoundedWait.completedWithin(timeout) {
                _ = await lastTask.result
            }
            didDrain = didFinish
            if didFinish == false {
                DebugLogger.shared.error(
                    "TranscriptionExecutor.cancelAndAwaitPending timed out after \(timeout); " +
                        "abandoning wedged task",
                    source: "TranscriptionExecutor"
                )
            }
        }
        self.lastTask = nil
        self.operationCancellations.removeAll()
        self.isChainWedged = false
        self.chainGeneration &+= 1
        return didDrain
    }
}

private nonisolated func logTranscriptionExecutorPhase(_ phase: String, sessionID: Int?) {
    guard let sessionID else { return }
    let timestamp = ProcessInfo.processInfo.systemUptime
    DebugLogger.shared.info(
        "ASR_BENCH t=\(timestamp) session=\(sessionID) final_queue_\(phase) mainThread=\(Thread.isMainThread)",
        source: "ASRBenchmark"
    )
}

nonisolated func logStreamingProviderOperationReturn(
    sessionID: Int,
    operationID: UUID,
    route: String
) {
    let returnedAt = ProcessInfo.processInfo.systemUptime
    DebugLogger.shared.info(
        "ASR_BENCH t=\(returnedAt) streaming_provider_operation_return " +
            "session=\(sessionID) operation=\(operationID.uuidString) route=\(route)",
        source: "ASRBenchmark"
    )
}

/// Keeps a stop-state UI refresh from entering the main-actor queue ahead of
/// final transcription. The owner must always finish the gate; repeated finishes
/// are harmless so early-return paths can share one cleanup.
struct ASRStopUIInvalidationGate {
    private(set) var isDeferring = false
    var hasOutputPipelineHold = false
    var stopDidFinish = false

    mutating func holdForOutputPipeline() {
        self.isDeferring = true
        self.hasOutputPipelineHold = true
    }

    mutating func begin() {
        self.isDeferring = true
    }

    mutating func finish() -> Bool {
        guard self.isDeferring else { return false }
        self.stopDidFinish = true
        return self.completeIfReady()
    }

    mutating func releaseOutputPipelineHold() -> Bool {
        self.hasOutputPipelineHold = false
        guard self.stopDidFinish else {
            let wasDeferring = self.isDeferring
            self.isDeferring = false
            return wasDeferring
        }
        return self.completeIfReady()
    }

    mutating func forceFinish() -> Bool {
        self.hasOutputPipelineHold = false
        self.stopDidFinish = true
        return self.completeIfReady()
    }

    private mutating func completeIfReady() -> Bool {
        guard self.isDeferring, self.stopDidFinish, self.hasOutputPipelineHold == false else { return false }
        self.isDeferring = false
        self.stopDidFinish = false
        return true
    }
}

@MainActor
func scheduleDeferredMainActorOperation(
    afterNanoseconds delayNanoseconds: UInt64,
    shouldRun: @escaping @MainActor () -> Bool = { true },
    operation: @escaping @MainActor () -> Void
) -> Task<Void, Never> {
    Task { @MainActor in
        do {
            try await Task.sleep(nanoseconds: delayNanoseconds)
        } catch {
            return
        }
        guard Task.isCancelled == false, shouldRun() else { return }
        operation()
    }
}

/// Identifies the recording and provider generation allowed to publish a live preview.
/// Operation completion uses the narrower operation identity so stale cleanup cannot
/// clear state owned by a newer chunk.
struct StreamingTranscriptionWorkState {
    private(set) var sessionID: Int?
    private(set) var activeOperationID: UUID?
    private(set) var providerGeneration: UInt64 = 0

    mutating func beginSession(_ sessionID: Int) {
        self.sessionID = sessionID
        self.activeOperationID = nil
    }

    mutating func beginOperation(
        sessionID: Int,
        operationID: UUID
    ) -> UInt64? {
        guard self.sessionID == sessionID, self.activeOperationID == nil else { return nil }
        self.activeOperationID = operationID
        return self.providerGeneration
    }

    func ownsOperation(sessionID: Int, operationID: UUID) -> Bool {
        self.sessionID == sessionID && self.activeOperationID == operationID
    }

    func canPublish(
        sessionID: Int,
        operationID: UUID,
        providerGeneration: UInt64
    ) -> Bool {
        self.ownsOperation(sessionID: sessionID, operationID: operationID) &&
            self.providerGeneration == providerGeneration
    }

    func canPublishPreview(
        sessionID: Int,
        operationID: UUID,
        providerGeneration: UInt64,
        isRunning: Bool,
        schedulingSessionID: Int?
    ) -> Bool {
        isRunning &&
            schedulingSessionID == sessionID &&
            self.canPublish(
                sessionID: sessionID,
                operationID: operationID,
                providerGeneration: providerGeneration
            )
    }

    mutating func finishOperation(sessionID: Int, operationID: UUID) -> Bool {
        guard self.ownsOperation(sessionID: sessionID, operationID: operationID) else { return false }
        self.activeOperationID = nil
        return true
    }

    mutating func invalidateProvider() {
        self.providerGeneration &+= 1
    }

    mutating func endSession(_ sessionID: Int) {
        guard self.sessionID == sessionID, self.activeOperationID == nil else { return }
        self.sessionID = nil
    }
}

/// Blocks a new recording only while the previous recording still owns the shared PCM buffer.
/// Cancelling a pending start releases its waiter without completing the active handoff.
@MainActor
final class RecordingBufferHandoffGate {
    struct Token: Equatable {
        let id = UUID()
    }

    var activeToken: Token?
    var waiters: [CheckedContinuation<Void, Never>] = []
    private(set) var isRecovering = false

    var isActive: Bool { self.activeToken != nil }
    var pendingWaiterCount: Int { self.waiters.count }

    func begin() -> Token? {
        guard self.activeToken == nil else { return nil }
        let token = Token()
        self.activeToken = token
        return token
    }

    func waitUntilAvailable() async {
        guard self.activeToken != nil else { return }
        await withCheckedContinuation { continuation in
            self.waiters.append(continuation)
        }
    }

    func releasePendingWaiters() {
        let waiters = self.waiters
        self.waiters.removeAll(keepingCapacity: false)
        waiters.forEach { $0.resume() }
    }

    func complete(_ token: Token) {
        guard self.activeToken == token else { return }
        self.activeToken = nil
        self.isRecovering = false
        self.releasePendingWaiters()
    }

    func markTimedOut(_ token: Token) {
        guard self.activeToken == token else { return }
        self.isRecovering = true
        // Wake starts already waiting so they fail visibly instead of hanging.
        self.releasePendingWaiters()
    }
}

/// Owns the cancellable idle delay separately from provider work. Normal recording
/// stop cancels only the delay; an active provider operation is allowed to settle.
@MainActor
final class StreamingTaskLifecycle {
    var scheduler: (id: UUID, task: Task<Void, Never>)?
    var active: (sessionID: Int, operationID: UUID, task: Task<Void, Never>)?
    var drainWaiters: [UUID: (operationID: UUID, continuation: CheckedContinuation<Bool, Never>, timer: Task<Void, Never>)] = [:]

    var hasScheduledIdleWork: Bool { self.scheduler != nil }
    var hasActiveWork: Bool { self.active != nil }
    var pendingDrainCount: Int { self.drainWaiters.count }

    @discardableResult
    func schedule(
        sessionID: Int,
        delayNanoseconds: UInt64,
        operation: @escaping @MainActor (UUID) async -> Void,
        completion: @escaping @MainActor (UUID) -> Void
    ) -> Bool {
        guard self.scheduler == nil, self.active == nil else { return false }
        let schedulerID = UUID()
        let task = Task { @MainActor [weak self] in
            if delayNanoseconds > 0 {
                do {
                    try await Task.sleep(nanoseconds: delayNanoseconds)
                } catch {
                    return
                }
            }
            guard let self,
                  Task.isCancelled == false,
                  self.scheduler?.id == schedulerID
            else { return }

            self.scheduler = nil
            let operationID = UUID()
            let activeTask = Task { @MainActor [weak self] in
                await operation(operationID)
                guard let self,
                      self.active?.sessionID == sessionID,
                      self.active?.operationID == operationID
                else { return }
                self.active = nil
                completion(operationID)
                let completedWaiters = self.drainWaiters.filter { $0.value.operationID == operationID }
                for id in completedWaiters.keys {
                    self.finishDrain(id: id, completed: true)
                }
            }
            self.active = (sessionID, operationID, activeTask)
        }
        self.scheduler = (schedulerID, task)
        return true
    }

    @discardableResult
    func cancelScheduler() -> Bool {
        guard let scheduler = self.scheduler else { return false }
        self.scheduler = nil
        scheduler.task.cancel()
        return true
    }

    func activeTaskToDrain(sessionID: Int) -> Task<Void, Never>? {
        guard let active = self.active, active.sessionID == sessionID else { return nil }
        return active.task
    }

    /// Deadline bounds the caller only. Never cancel or release a provider still
    /// using incremental state. Completion removes the timer; timeout removes the waiter.
    func drain(sessionID: Int, timeoutNanoseconds: UInt64) async -> Bool {
        guard let active = self.active, active.sessionID == sessionID else { return true }
        let id = UUID()
        return await withCheckedContinuation { continuation in
            let timer = Task { @MainActor [weak self] in
                do {
                    try await Task.sleep(nanoseconds: timeoutNanoseconds)
                } catch { return }
                self?.finishDrain(id: id, completed: false)
            }
            self.drainWaiters[id] = (active.operationID, continuation, timer)
        }
    }

    func finishDrain(id: UUID, completed: Bool) {
        guard let waiter = self.drainWaiters.removeValue(forKey: id) else { return }
        waiter.timer.cancel()
        waiter.continuation.resume(returning: completed)
    }
}

struct ShortAudioSilenceAssessment: Equatable {
    let durationMilliseconds: Int
    let isEligible: Bool
    let shouldSkipTranscription: Bool
    let peakAmplitude: Float
    let rmsAmplitude: Float
    let maximumFrameRMS: Float
}

enum AudioCaptureStartOutcome: Equatable {
    case started
    case alreadyActive
    case failed
}

enum ASRStopOutcome: Equatable {
    case success
    case empty
    case failed
}

// swiftlint:disable file_length type_body_length function_body_length cyclomatic_complexity
// Upstream: FluidVoice (altic-dev), GPLv3. Speech engine. Do not rewrite it to look original.
/// A comprehensive speech recognition service that handles real-time audio transcription.
///
/// This service manages the entire ASR (Automatic Speech Recognition) pipeline including:
/// - Audio capture and processing
/// - Model downloading and management
/// - Real-time transcription
/// - Audio level visualization
/// - Text-to-speech integration
///
/// The service is designed to work seamlessly with macOS system APIs and provides
/// robust error handling and performance optimization.
///
/// ## Language Support
/// I speak and Show as are every language both Apple Translation and a Voice Engine can use.
/// Parakeet Flash and TDT stay on English. Apple Speech and Whisper hear that list.
/// Nemotron Thai is experimental.
/// ## Thread Safety
/// All public methods are marked with @MainActor to ensure thread safety.
/// Audio processing happens on background threads for optimal performance.
///
/// ## Model Management
/// The service automatically downloads and manages ASR models from Hugging Face.
/// Models are cached locally to avoid repeated downloads.
