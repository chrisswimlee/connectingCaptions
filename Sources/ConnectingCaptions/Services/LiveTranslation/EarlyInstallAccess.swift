import CryptoKit
import Foundation
import Security

/// A Mac that already had the app before the paid release keeps Listen.
/// The file has to have been created after this Mac was first signed in, and before this launch.
/// The decision is sealed on this Mac with a key that comes from the build, not from a preference.
nonisolated enum EarlyInstallAccess {
    struct Decision: Equatable, Sendable {
        var allowed: Bool
        var sealed: Data?
    }

    #if DEBUG
    nonisolated(unsafe) static var testingKey: SymmetricKey?
    nonisolated(unsafe) static var testingHome: URL?
    nonisolated(unsafe) static var testingAppBirth: Date?
    nonisolated(unsafe) static var testingFirstSignOn: Date?
    nonisolated(unsafe) static var testingLaunchedAt: Date?
    nonisolated(unsafe) static var testingNow: Date?
    #endif

    private nonisolated(unsafe) static var cached: Bool?
    private static let mask: [UInt8] = [
        0xBA, 0x0F, 0x11, 0x14, 0x7C, 0x7D, 0xF8, 0xBF, 0x55, 0x68, 0x15, 0x37, 0xB6, 0xEE, 0xFE, 0x24,
        0x6D, 0xFF, 0xA2, 0x44, 0x3B, 0x7A, 0x89, 0x59, 0x32, 0x55, 0xE1, 0xB1, 0x97, 0x02, 0x00, 0xCA,
    ]

    static func resetForTests() {
        self.cached = nil
        EarlyInstallStore.resetForTests()
        #if DEBUG
        self.testingKey = nil
        self.testingHome = nil
        self.testingAppBirth = nil
        self.testingFirstSignOn = nil
        self.testingLaunchedAt = nil
        self.testingNow = nil
        #endif
    }

    static func forgetCachedDecision() {
        self.cached = nil
    }

    static func currentDecision() -> Bool {
        if let cached = self.cached { return cached }
        let appBirth = self.appBirth()
        let firstSignOn = self.firstSignOn()
        let launchedAt = self.launchedAt()
        let raw = self.birthDates(in: self.homeDirectory())
        let births = raw.filter {
            self.admits(
                birth: $0,
                cutoff: self.cutoff,
                firstSignOn: firstSignOn,
                appBirth: appBirth,
                launchedAt: launchedAt
            )
        }
        // An empty home on a brand-new install can be a restore still in progress.
        // A file that is present and does not qualify is a final no.
        let canJudge = firstSignOn != nil && launchedAt != nil
        let sealEmpty = canJudge && (!raw.isEmpty || self.absenceHasSettled(appBirth))
        let decision = self.decide(
            stored: EarlyInstallStore.readAll(),
            birthDates: births,
            cutoff: self.cutoff,
            key: self.sealingKey(),
            machineID: CommercialSeat.currentID,
            sealEmpty: sealEmpty
        )
        if let sealed = decision.sealed {
            EarlyInstallStore.write(sealed)
        }
        self.cached = decision.allowed
        return decision.allowed
    }

    static func decide(
        stored: [Data],
        birthDates: [Date],
        cutoff: Date,
        key: SymmetricKey?,
        machineID: String,
        sealEmpty: Bool = true
    ) -> Decision {
        var opened: [Bool] = []
        if let key {
            for blob in stored {
                if let allowed = self.open(blob, key: key, machineID: machineID) {
                    opened.append(allowed)
                }
            }
        }
        if opened.contains(false) {
            return Decision(allowed: false, sealed: nil)
        }
        if opened.contains(true) {
            return Decision(allowed: true, sealed: nil)
        }
        if !stored.isEmpty {
            return Decision(allowed: false, sealed: nil)
        }
        guard let key else {
            return Decision(allowed: false, sealed: nil)
        }
        let allowed = birthDates.contains { $0 < cutoff }
        if !allowed, birthDates.isEmpty, !sealEmpty {
            return Decision(allowed: false, sealed: nil)
        }
        guard let sealed = try? self.seal(allowed: allowed, cutoff: cutoff, key: key, machineID: machineID) else {
            return Decision(allowed: false, sealed: nil)
        }
        return Decision(allowed: allowed, sealed: sealed)
    }

    /// A copied file is older than this Mac's first sign-on. A file from this launch is newer than
    /// the process start. An empty support folder never reaches here.
    static func admits(
        birth: Date,
        cutoff: Date,
        firstSignOn: Date?,
        appBirth: Date,
        launchedAt: Date?
    ) -> Bool {
        guard let firstSignOn, let launchedAt else { return false }
        return birth >= firstSignOn && birth < cutoff && birth < appBirth && birth < launchedAt
    }

    static func key(fromMixedHex hex: String) -> SymmetricKey? {
        guard let mixed = self.hexData(hex), mixed.count == self.mask.count else { return nil }
        let raw = Data(zip(mixed, self.mask).map { $0 ^ $1 })
        return SymmetricKey(data: raw)
    }

    static func birthDates(in home: URL, fileManager: FileManager = .default) -> [Date] {
        self.candidateURLs(in: home).compactMap { url in
            guard self.isPriorArtifact(url, fileManager: fileManager),
                  let attributes = try? fileManager.attributesOfItem(atPath: url.path),
                  let created = attributes[.creationDate] as? Date
            else {
                return nil
            }
            return created
        }
    }

    private static var cutoff: Date {
        CommercialLicense.day(from: ConnectingCaptionsProduct.earlierCopyCutoffDay) ?? .distantPast
    }

    private static func sealingKey() -> SymmetricKey? {
        #if DEBUG
        if AppTestEnvironment.isRunning { return self.testingKey }
        #endif
        guard let hex = Bundle.main.object(forInfoDictionaryKey: "CCSeal") as? String else { return nil }
        return self.key(fromMixedHex: hex)
    }

    private static func appBirth() -> Date {
        #if DEBUG
        if AppTestEnvironment.isRunning {
            return self.testingAppBirth ?? .distantPast
        }
        #endif
        let path = Bundle.main.bundleURL.path
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path),
              let created = attributes[.creationDate] as? Date
        else {
            return .distantPast
        }
        return created
    }

    private static func decisionNow() -> Date {
        #if DEBUG
        if AppTestEnvironment.isRunning, let testingNow {
            return testingNow
        }
        #endif
        return Date()
    }

    /// A first launch with no app files waits a day before sealing no, so a restore can finish.
    private static func absenceHasSettled(_ appBirth: Date) -> Bool {
        self.decisionNow().timeIntervalSince(appBirth) >= 24 * 60 * 60
    }

    private static func firstSignOn() -> Date? {
        #if DEBUG
        if AppTestEnvironment.isRunning { return self.testingFirstSignOn }
        #endif
        return MacFirstSignOn.date()
    }

    private static func launchedAt() -> Date? {
        #if DEBUG
        if AppTestEnvironment.isRunning { return self.testingLaunchedAt }
        #endif
        return MacFirstSignOn.processStart()
    }

    private static func homeDirectory() -> URL {
        #if DEBUG
        if AppTestEnvironment.isRunning {
            return self.testingHome ?? URL(fileURLWithPath: "/var/empty")
        }
        #endif
        return FileManager.default.homeDirectoryForCurrentUser
    }

    private static func candidateURLs(in home: URL) -> [URL] {
        let preferences = home.appendingPathComponent("Library/Preferences", isDirectory: true)
        let support = home.appendingPathComponent("Library/Application Support", isDirectory: true)
        let folders = [ConnectingCaptionsProduct.supportFolderName] + ConnectingCaptionsProduct.priorSupportFolderNames
        var urls = [
            preferences.appendingPathComponent("com.connectingcaptions.app.plist"),
            preferences.appendingPathComponent("com.connectingcaptions.app.debug.plist"),
            preferences.appendingPathComponent("com.fluidsubtitles.app.plist"),
        ]
        for folder in folders {
            let root = support.appendingPathComponent(folder, isDirectory: true)
            urls.append(root)
            urls.append(root.appendingPathComponent("TranscriptionHistory.sqlite3"))
        }
        return urls
    }

    private static func isPriorArtifact(_ url: URL, fileManager: FileManager) -> Bool {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return false }
        if isDirectory.boolValue { return false }
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        let header = (try? handle.read(upToCount: 16)) ?? Data()
        if url.pathExtension == "sqlite3" {
            return header.starts(with: Data("SQLite format 3".utf8))
        }
        return header.starts(with: Data("bplist".utf8)) || header.starts(with: Data("<?xml".utf8))
    }

    private static func seal(allowed: Bool, cutoff: Date, key: SymmetricKey, machineID: String) throws -> Data {
        let box = try AES.GCM.seal(
            self.payload(allowed: allowed, cutoff: cutoff),
            using: key,
            authenticating: Data(machineID.utf8)
        )
        guard let combined = box.combined else {
            throw EarlyInstallSealError.unavailable
        }
        return combined
    }

    private static func open(_ combined: Data, key: SymmetricKey, machineID: String) -> Bool? {
        guard let box = try? AES.GCM.SealedBox(combined: combined),
              let plain = try? AES.GCM.open(box, using: key, authenticating: Data(machineID.utf8)),
              plain.count == 10,
              plain[0] == 1,
              plain[1] == 0 || plain[1] == 1
        else {
            return nil
        }
        return plain[1] == 1
    }

    private static func payload(allowed: Bool, cutoff: Date) -> Data {
        var data = Data([1, allowed ? 1 : 0])
        var seconds = Int64(cutoff.timeIntervalSince1970.rounded()).bigEndian
        withUnsafeBytes(of: &seconds) { data.append(contentsOf: $0) }
        return data
    }

    private static func hexData(_ hex: String) -> Data? {
        let text = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count.isMultiple(of: 2), !text.isEmpty else { return nil }
        var data = Data()
        data.reserveCapacity(text.count / 2)
        var index = text.startIndex
        while index < text.endIndex {
            let next = text.index(index, offsetBy: 2)
            guard let byte = UInt8(text[index ..< next], radix: 16) else { return nil }
            data.append(byte)
            index = next
        }
        return data
    }
}

private enum EarlyInstallSealError: Error {
    case unavailable
}

private enum EarlyInstallStore {
    #if DEBUG
    nonisolated(unsafe) static var memory: [Data] = []
    #endif
    private static let fileName = "CCSeal"

    static func resetForTests() {
        #if DEBUG
        self.memory = []
        #endif
    }

    static func readAll() -> [Data] {
        #if DEBUG
        if AppTestEnvironment.isRunning { return self.memory }
        #endif
        var blobs: [Data] = []
        if let keychain = try? EarlyInstallKeychain.read() {
            blobs.append(keychain)
        }
        if let file = try? Data(contentsOf: self.fileURL()), !blobs.contains(file) {
            blobs.append(file)
        }
        return blobs
    }

    static func write(_ data: Data) {
        #if DEBUG
        if AppTestEnvironment.isRunning {
            self.memory = [data]
            return
        }
        #endif
        try? EarlyInstallKeychain.write(data)
        let url = self.fileURL()
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: url, options: .atomic)
    }

    private static func fileURL() -> URL {
        AppSupportDirectory.url().appendingPathComponent(self.fileName)
    }
}

private enum EarlyInstallKeychain {
    static func read() throws -> Data? {
        var query = self.query
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else {
            throw EarlyInstallSealError.unavailable
        }
        return data
    }

    static func write(_ data: Data) throws {
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
            throw EarlyInstallSealError.unavailable
        }
    }

    private static var query: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: ConnectingCaptionsProduct.licenseKeychainService,
            kSecAttrAccount as String: "cc.ei.1",
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecAttrSynchronizable as String: false,
        ]
    }
}
