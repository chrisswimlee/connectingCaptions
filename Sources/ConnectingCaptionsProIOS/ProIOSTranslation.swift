import ConnectingCaptionsCore
import Foundation
import SwiftUI
import Translation

/// Apple Translation for Show as. The session exists only while `.translationTask` is attached.
@MainActor
final class ProIOSTranslation: ObservableObject {
    @Published var configuration: TranslationSession.Configuration?
    @Published private(set) var packStatus: PackStatus = .notNeeded

    enum PackStatus: Equatable {
        case notNeeded
        case checking
        case installed
        case needsDownload
        case downloading
        case unsupported
    }

    private var session: TranslationSession?
    private var sessionGeneration: UInt64 = 0
    private var pairID = ""
    private var availabilitySource: Locale.Language?
    private var availabilityTarget: Locale.Language?
    private var hold: CheckedContinuation<Void, Never>?
    private var translateInFlight = 0
    private var queuedConfiguration: TranslationSession.Configuration?
    private var configurationChangeQueued = false
    private var waiters: [Waiter] = []
    private var busy = false
    private var queue: [CheckedContinuation<Void, Never>] = []

    private struct Waiter {
        var id: UUID
        var continuation: CheckedContinuation<TranslationSession, Error>
    }

    func prepare(source: TranslationLanguage, target: TranslationLanguage) {
        guard source.id != target.id else {
            self.pairID = ""
            self.availabilitySource = nil
            self.availabilityTarget = nil
            self.packStatus = .notNeeded
            self.failWaiters(TranslationEngineError(message: "Apple Translation is not needed for this pair."))
            self.queueConfigurationChange(nil)
            return
        }
        let next = TranslationSession.Configuration(
            source: source.localeLanguage,
            target: target.localeLanguage
        )
        if self.configuration != next {
            self.queueConfigurationChange(next)
        }
        let pairID = "\(source.id)>\(target.id)"
        self.availabilitySource = source.localeLanguage
        self.availabilityTarget = target.localeLanguage
        if pairID != self.pairID {
            self.pairID = pairID
            self.packStatus = .checking
            Task { await self.refreshPackStatus() }
        }
    }

    func refreshPackStatus() async {
        guard let source = self.availabilitySource, let target = self.availabilityTarget else { return }
        let pairID = self.pairID
        let status = await LanguageAvailability().status(from: source, to: target)
        guard pairID == self.pairID, self.packStatus != .downloading else { return }
        switch status {
        case .installed:
            self.packStatus = .installed
        case .supported:
            self.packStatus = .needsDownload
        case .unsupported:
            self.packStatus = .unsupported
        @unknown default:
            self.packStatus = .unsupported
        }
    }

    func downloadPack() async {
        guard self.packStatus == .needsDownload else { return }
        let pairID = self.pairID
        self.packStatus = .downloading
        do {
            let session = try await self.session(waiting: .seconds(20))
            try await session.prepareTranslation()
        } catch {
            // The sheet can be dismissed. The next check shows whether the pack landed.
        }
        guard pairID == self.pairID else { return }
        self.packStatus = .checking
        await self.refreshPackStatus()
    }

    func use(_ session: TranslationSession) async {
        let previous = self.hold
        self.hold = nil
        self.sessionGeneration &+= 1
        let generation = self.sessionGeneration
        self.session = session
        previous?.resume()
        let ready = self.waiters
        self.waiters = []
        for waiter in ready {
            waiter.continuation.resume(returning: session)
        }
        await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                guard self.sessionGeneration == generation else {
                    continuation.resume()
                    return
                }
                self.hold = continuation
            }
        } onCancel: {
            Task { @MainActor in
                guard self.sessionGeneration == generation else { return }
                self.session = nil
                let parked = self.hold
                self.hold = nil
                parked?.resume()
            }
        }
    }

    func translate(_ text: String, source: TranslationLanguage, target: TranslationLanguage) async throws -> String {
        if source.id == target.id { return text }
        await self.acquire()
        self.translateInFlight += 1
        defer {
            self.translateInFlight -= 1
            self.applyQueuedConfigurationIfIdle()
            self.release()
        }
        let timeout = LiveTranslationTiming.mailboxTimeoutNanoseconds(for: .commit)
        let session = try await self.bounded(timeout) {
            try await self.session(waiting: .seconds(7))
        }
        do {
            return try await self.bounded(timeout) {
                try await session.translate(text).targetText
            }
        } catch {
            if (error as? TranslationEngineError)?.isTimeout == true {
                self.invalidateWedgedSession()
            }
            throw error
        }
    }

    private func session(waiting limit: Duration) async throws -> TranslationSession {
        if let session = self.session { return session }
        let id = UUID()
        return try await withCheckedThrowingContinuation { continuation in
            self.waiters.append(Waiter(id: id, continuation: continuation))
            Task { @MainActor in
                try? await Task.sleep(for: limit)
                guard let index = self.waiters.firstIndex(where: { $0.id == id }) else { return }
                let waiter = self.waiters.remove(at: index)
                waiter.continuation.resume(
                    throwing: TranslationEngineError(message: "The language pack is not ready yet.")
                )
            }
        }
    }

    private func failWaiters(_ error: Error) {
        let pending = self.waiters
        self.waiters = []
        for waiter in pending {
            waiter.continuation.resume(throwing: error)
        }
    }

    private func acquire() async {
        if !self.busy {
            self.busy = true
            return
        }
        await withCheckedContinuation { continuation in
            self.queue.append(continuation)
        }
    }

    private func release() {
        if self.queue.isEmpty {
            self.busy = false
        } else {
            self.queue.removeFirst().resume()
        }
    }

    private func resumeHold() {
        let parked = self.hold
        self.hold = nil
        parked?.resume()
    }

    private func queueConfigurationChange(_ configuration: TranslationSession.Configuration?) {
        self.sessionGeneration &+= 1
        self.session = nil
        self.queuedConfiguration = configuration
        self.configurationChangeQueued = true
        self.applyQueuedConfigurationIfIdle()
    }

    private func applyQueuedConfigurationIfIdle() {
        guard self.translateInFlight == 0, self.configurationChangeQueued else { return }
        let next = self.queuedConfiguration
        self.queuedConfiguration = nil
        self.configurationChangeQueued = false
        self.resumeHold()
        self.configuration = next
    }

    private func invalidateWedgedSession() {
        guard var configuration = self.configuration else {
            self.queueConfigurationChange(nil)
            return
        }
        configuration.invalidate()
        self.queueConfigurationChange(configuration)
    }

    private func bounded<T>(
        _ nanoseconds: UInt64,
        operation: @escaping @MainActor () async throws -> T
    ) async throws -> T {
        let gate = ProIOSTranslationClaim()
        let operationTask = Task { @MainActor in
            try await operation()
        }
        let result: Result<T, Error> = await withCheckedContinuation { continuation in
            let timeoutTask = Task { @MainActor in
                do {
                    try await Task.sleep(nanoseconds: nanoseconds)
                } catch {
                    return
                }
                if gate.claim() {
                    continuation.resume(returning: .failure(TranslationEngineError.timeout))
                }
            }
            Task { @MainActor in
                do {
                    let value = try await operationTask.value
                    if gate.claim() {
                        timeoutTask.cancel()
                        continuation.resume(returning: .success(value))
                    }
                } catch {
                    if gate.claim() {
                        timeoutTask.cancel()
                        continuation.resume(returning: .failure(error))
                    }
                }
            }
        }
        switch result {
        case .success(let value):
            return value
        case .failure(let error):
            operationTask.cancel()
            _ = await operationTask.result
            throw error
        }
    }
}

private final class ProIOSTranslationClaim: @unchecked Sendable {
    private let lock = NSLock()
    private var claimed = false

    func claim() -> Bool {
        self.lock.lock()
        defer { self.lock.unlock() }
        if self.claimed { return false }
        self.claimed = true
        return true
    }
}
