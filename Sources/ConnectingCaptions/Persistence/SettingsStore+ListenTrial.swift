import Combine
import Foundation
import Security

extension SettingsStore {
    var listenTrialStartedOn: Date? {
        guard let raw = self.readListenTrialDay() else { return nil }
        return CommercialLicense.day(from: raw)
    }

    var listenTrialPhase: ListenAccess.Phase {
        ListenAccess.phase(startedOn: self.listenTrialStartedOn, now: Date())
    }

    /// nil when Listen may start. The first allowed Listen writes the trial day.
    func blockListenStart(now: Date = Date()) -> String? {
        if self.isCommerciallyLicensed {
            return nil
        }
        if self.commercialLicenseRecord != nil {
            return self.commercialSeatRefusal
                ?? "This Mac is outside the seat list. Listen stays off until the seat list includes it."
        }
        let phase = ListenAccess.phase(startedOn: self.listenTrialStartedOn, now: now)
        switch phase {
        case .notStarted, .inTrial:
            self.ensureListenTrialStarted(now: now)
            return nil
        case .ended:
            return ListenAccess.trialEndedMessage
        }
    }

    func ensureListenTrialStarted(now: Date = Date()) {
        guard self.listenTrialStartedOn == nil else { return }
        self.storeListenTrialDay(CommercialLicense.dayString(now))
        self.objectWillChange.send()
    }

    func clearListenTrial() {
        self.storeListenTrialDay(nil)
        self.objectWillChange.send()
    }

    private func readListenTrialDay() -> String? {
        if Self.isRunningTests {
            return self.defaults.string(forKey: ListenTrialDefaults.startedOn)
        }
        if let keychain = try? ListenTrialKeychain.read() {
            return keychain
        }
        return self.defaults.string(forKey: ListenTrialDefaults.startedOn)
    }

    private func storeListenTrialDay(_ day: String?) {
        if Self.isRunningTests {
            if let day {
                self.defaults.set(day, forKey: ListenTrialDefaults.startedOn)
            } else {
                self.defaults.removeObject(forKey: ListenTrialDefaults.startedOn)
            }
            return
        }
        do {
            try ListenTrialKeychain.write(day)
        } catch {
            if let day {
                self.defaults.set(day, forKey: ListenTrialDefaults.startedOn)
            } else {
                self.defaults.removeObject(forKey: ListenTrialDefaults.startedOn)
            }
        }
    }

    private enum ListenTrialDefaults {
        static let startedOn = "ListenTrialStartedOn"
    }
}

private enum ListenTrialKeychain {
    static func read() throws -> String? {
        var query = self.query
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw KeychainServiceError.unhandled(status)
        }
        guard let data = item as? Data, let day = String(data: data, encoding: .utf8) else {
            throw KeychainServiceError.invalidData
        }
        return day
    }

    static func write(_ day: String?) throws {
        if let day {
            let data = Data(day.utf8)
            let status: OSStatus
            if try self.read() != nil {
                status = SecItemUpdate(
                    self.query as CFDictionary,
                    [kSecValueData as String: data] as CFDictionary
                )
            } else {
                var add = self.query
                add[kSecValueData as String] = data
                status = SecItemAdd(add as CFDictionary, nil)
            }
            guard status == errSecSuccess else {
                throw KeychainServiceError.unhandled(status)
            }
        } else {
            let status = SecItemDelete(self.query as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else {
                throw KeychainServiceError.unhandled(status)
            }
        }
    }

    private static var query: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: ConnectingCaptionsProduct.licenseKeychainService,
            kSecAttrAccount as String: ConnectingCaptionsProduct.trialKeychainAccount,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
    }
}
