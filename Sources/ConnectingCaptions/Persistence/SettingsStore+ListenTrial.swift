import Combine
import Foundation
import Security

extension SettingsStore {
    var listenTrialStartedOn: Date? {
        guard let raw = self.readListenTrialDay() else { return nil }
        return CommercialLicense.day(from: raw)
    }

    #if DEBUG
    static var testingAppBundleCreation: Date?
    #endif

    var listenTrialPhase: ListenAccess.Phase {
        ListenAccess.phase(
            startedOn: self.listenTrialStartedOn,
            now: Date(),
            highWater: self.listenClockHighWater
        )
    }

    /// nil when Listen may start.
    /// Release 1.6.16 does not start or end the 14-day trial. A work key that
    /// names seats still keeps Listen off on a Mac outside that list.
    func blockListenStart(now: Date = Date()) -> String? {
        self.noteListenClock(now)
        if self.isCommerciallyLicensed {
            return nil
        }
        // An earlier download keeps Listen even if a seat list does not name this Mac.
        if self.keepsEarlierCopy {
            return nil
        }
        if self.commercialLicenseRecord != nil {
            return self.commercialSeatRefusal
                ?? "This Mac is outside the seat list. Listen stays off until the seat list includes it."
        }
        if let failure = self.commercialLicenseFailure, failure == .expired || failure == .notYetValid {
            return failure.localizedDescription
        }
        guard ListenAccess.releaseAsksForKey else { return nil }
        let phase = ListenAccess.phase(
            startedOn: self.listenTrialStartedOn,
            now: now,
            highWater: self.listenClockHighWater
        )
        switch phase {
        case .notStarted, .inTrial:
            guard ListenAccess.acceptedNow(now, appBirth: self.appBundleCreation) != nil else {
                return ListenAccess.dateAheadMessage
            }
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
        self.storeListenClockDay(nil)
        self.objectWillChange.send()
    }

    var listenClockHighWater: Date? {
        guard let raw = self.readListenClockDay() else { return nil }
        return CommercialLicense.day(from: raw)
    }

    /// When this copy of the app was installed. A clock set years past that is not used as the first Listen.
    var appBundleCreation: Date? {
        #if DEBUG
        if Self.isRunningTests, let override = Self.testingAppBundleCreation {
            return override
        }
        #endif
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: Bundle.main.bundleURL.path),
              let created = attributes[.creationDate] as? Date
        else {
            return nil
        }
        return created
    }

    func noteListenClock(_ now: Date) {
        let marked = ListenAccess.advanceHighWater(
            self.listenClockHighWater,
            now: now,
            appBirth: self.appBundleCreation
        )
        guard let marked else { return }
        let day = CommercialLicense.dayString(marked)
        guard day != self.readListenClockDay() else { return }
        self.storeListenClockDay(day)
    }

    /// Day used for key expiry. A clock moved backward stays at the latest day already seen.
    var licenseClockNow: Date {
        let now = Date()
        return ListenAccess.advanceHighWater(
            self.listenClockHighWater,
            now: now,
            appBirth: self.appBundleCreation
        ) ?? now
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

    private func readListenClockDay() -> String? {
        if Self.isRunningTests {
            return self.defaults.string(forKey: ListenTrialDefaults.highWater)
        }
        if let keychain = try? ListenClockKeychain.read() {
            return keychain
        }
        return self.defaults.string(forKey: ListenTrialDefaults.highWater)
    }

    private func storeListenClockDay(_ day: String?) {
        if Self.isRunningTests {
            if let day {
                self.defaults.set(day, forKey: ListenTrialDefaults.highWater)
            } else {
                self.defaults.removeObject(forKey: ListenTrialDefaults.highWater)
            }
            return
        }
        do {
            try ListenClockKeychain.write(day)
        } catch {
            if let day {
                self.defaults.set(day, forKey: ListenTrialDefaults.highWater)
            } else {
                self.defaults.removeObject(forKey: ListenTrialDefaults.highWater)
            }
        }
    }

    private enum ListenTrialDefaults {
        static let startedOn = "ListenTrialStartedOn"
        static let highWater = "ListenClockHighWater"
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
            kSecAttrSynchronizable as String: false,
        ]
    }
}

private enum ListenClockKeychain {
    static func read() throws -> String? {
        var query = self.query
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw KeychainServiceError.unhandled(status) }
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
                status = SecItemUpdate(self.query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
            } else {
                var add = self.query
                add[kSecValueData as String] = data
                status = SecItemAdd(add as CFDictionary, nil)
            }
            guard status == errSecSuccess else { throw KeychainServiceError.unhandled(status) }
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
            kSecAttrAccount as String: "connectingCaptionsListenClock",
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecAttrSynchronizable as String: false,
        ]
    }
}
