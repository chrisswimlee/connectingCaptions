import ConnectingCaptionsCore
import Foundation
import Security

/// Trial and Pro key for this phone. The keychain is the only copy.
/// A read failure keeps Listen off. Preferences are not a second copy of the key.
@MainActor
final class ProIOSLicenseStore: ObservableObject {
    static let shared = ProIOSLicenseStore()

    @Published private(set) var record: ProDirectLicense.Record?
    @Published private(set) var trialPhase: ProListenTrial.Phase = .notStarted
    @Published private(set) var hasStoredToken = false
    @Published var statusMessage: String?

    private var keychainBroken = false

    init() {
        self.reload()
    }

    var statusTitle: String {
        if let record = self.record {
            return record.coverageTitle
        }
        guard ConnectingCaptionsProduct.directDownloadAsksForKey else {
            return "Free download"
        }
        switch self.trialPhase {
        case .notStarted:
            return "14-day trial"
        case let .inTrial(day):
            return "Trial day \(day) of \(ProListenTrial.days)"
        case .ended:
            return "Trial ended"
        case .unreadable:
            return "License store unavailable"
        }
    }

    var statusDetail: String {
        if self.record != nil {
            return "Listen stays unlocked on this iPhone or iPad. The same key is the Mac app's Connecting Captions Pro key."
        }
        guard ConnectingCaptionsProduct.directDownloadAsksForKey else {
            return "Listen does not ask for a key. A Connecting Captions Pro key can still be pasted."
        }
        switch self.trialPhase {
        case .notStarted:
            return "The first Listen starts a 14-day trial. After that, paste a Connecting Captions Pro key."
        case .inTrial:
            return "FluidVoice is the voice engine. Apple Translation runs on this device."
        case .ended:
            return "Paste a Connecting Captions Pro key to keep listening."
        case .unreadable:
            return "The trial clock could not be read. Listen stays off."
        }
    }

    func blockListenStart() -> String? {
        if self.record != nil {
            return nil
        }
        guard ConnectingCaptionsProduct.directDownloadAsksForKey else {
            return nil
        }
        if self.keychainBroken {
            return "The license store could not be read. Listen stays off."
        }
        switch self.trialPhase {
        case .notStarted, .inTrial:
            return nil
        case .ended:
            return "The 14-day trial has ended. Paste a Connecting Captions Pro key in License."
        case .unreadable:
            return "The trial clock could not be read. Listen stays off."
        }
    }

    /// Rereads the trial clock before the microphone starts. A day that ended while the app stayed open blocks Listen.
    func rereadClock() {
        self.reload()
    }

    @discardableResult
    func noteListenStarted(now: Date = Date()) -> Bool {
        guard ConnectingCaptionsProduct.directDownloadAsksForKey else { return true }
        guard self.record == nil else { return true }
        let today = Self.dayString(now)
        if Self.read(account: Account.trialStart) == nil {
            guard self.write(account: Account.trialStart, value: today) else {
                self.statusMessage = "The trial clock could not be saved. Listen stays off."
                return false
            }
        }
        let marked = Self.read(account: Account.trialHighWater)
        if marked == nil || (marked ?? "") < today {
            guard self.write(account: Account.trialHighWater, value: today) else {
                self.statusMessage = "The trial clock could not be saved. Listen stays off."
                return false
            }
        }
        self.statusMessage = nil
        self.reload()
        return self.blockListenStart() == nil
    }

    func save(token: String) {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
        switch ProDirectLicense.verify(token, now: Date(), appVersion: version) {
        case .success:
            let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
            guard self.write(account: Account.license, value: trimmed) else {
                self.statusMessage = "The key could not be saved on this device."
                return
            }
            self.statusMessage = nil
            self.reload()
        case let .failure(failure):
            self.statusMessage = failure.localizedDescription
        }
    }

    func removeLicense() {
        guard self.write(account: Account.license, value: nil) else {
            self.statusMessage = "The key could not be removed from this device."
            return
        }
        self.record = nil
        self.hasStoredToken = false
        self.statusMessage = nil
        self.reload()
    }

    private func reload() {
        self.keychainBroken = false
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
        let token = Self.read(account: Account.license)
        let tokenFailed = Self.lastReadFailed
        let startedOn = Self.read(account: Account.trialStart)
        let startFailed = Self.lastReadFailed
        let highWater = Self.read(account: Account.trialHighWater)
        let waterFailed = Self.lastReadFailed
        if tokenFailed || startFailed || waterFailed {
            self.keychainBroken = true
            self.record = nil
            self.hasStoredToken = false
            self.trialPhase = .unreadable
            return
        }
        if let token, !token.isEmpty {
            self.hasStoredToken = true
            switch ProDirectLicense.verify(token, now: Date(), appVersion: version) {
            case let .success(record):
                self.record = record
                self.statusMessage = nil
            case let .failure(failure):
                self.record = nil
                self.statusMessage = failure.localizedDescription
            }
        } else {
            self.hasStoredToken = false
            self.record = nil
        }
        self.trialPhase = ProListenTrial.phase(startedOn: startedOn, highWater: highWater, now: Date())
    }

    private func write(account: String, value: String?) -> Bool {
        do {
            try ProIOSKeychain.write(account: account, value: value)
            return true
        } catch {
            return false
        }
    }

    private static var lastReadFailed = false

    private static func read(account: String) -> String? {
        do {
            let value = try ProIOSKeychain.read(account: account)
            Self.lastReadFailed = false
            return value
        } catch {
            Self.lastReadFailed = true
            return nil
        }
    }

    private static func dayString(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: date)
    }

    private enum Account {
        static let license = "license"
        static let trialStart = "trial-start"
        static let trialHighWater = "trial-high-water"
    }
}

enum ProIOSKeychain {
    private static let service = "com.connectingcaptions.ios.pro"

    static func read(account: String) throws -> String? {
        var query = self.query(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw KeychainError.status(status)
        }
        guard let data = item as? Data, let text = String(data: data, encoding: .utf8) else {
            throw KeychainError.invalid
        }
        return text
    }

    static func write(account: String, value: String?) throws {
        let existing = try self.read(account: account)
        if let value {
            let data = Data(value.utf8)
            if existing != nil {
                let status = SecItemUpdate(
                    self.query(account: account) as CFDictionary,
                    [kSecValueData as String: data] as CFDictionary
                )
                guard status == errSecSuccess else { throw KeychainError.status(status) }
            } else {
                var query = self.query(account: account)
                query[kSecValueData as String] = data
                let status = SecItemAdd(query as CFDictionary, nil)
                guard status == errSecSuccess else { throw KeychainError.status(status) }
            }
        } else if existing != nil {
            let status = SecItemDelete(self.query(account: account) as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else {
                throw KeychainError.status(status)
            }
        }
    }

    private static func query(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: self.service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
    }

    enum KeychainError: Error {
        case status(OSStatus)
        case invalid
    }
}
