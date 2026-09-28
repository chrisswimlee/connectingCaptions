import CryptoKit
import Foundation

/// On-device hash chain. Events name license, seat, and Listen start or stop.
/// Captions, transcripts, audio, and talk notes are rejected and never written.
nonisolated enum FleetAudit {
    enum Kind: String, Equatable, Sendable {
        case licenseActivated = "license.activated"
        case licenseRemoved = "license.removed"
        case seatAccepted = "seat.accepted"
        case seatRefused = "seat.refused"
        case listenStarted = "listen.started"
        case listenStopped = "listen.stopped"
        case settingsExported = "settings.exported"
        case settingsRestored = "settings.restored"
        case auditExported = "audit.exported"
        case auditCleared = "audit.cleared"
    }

    enum Failure: Equatable, LocalizedError {
        case retainedContent(String)
        case invalidField(String)
        case brokenChain
        case badSignature

        var errorDescription: String? {
            switch self {
            case .retainedContent, .invalidField:
                return "The activity log could not be written."
            case .brokenChain, .badSignature:
                return "The activity log on this Mac could not be checked."
            }
        }

        var logDetail: String {
            switch self {
            case let .retainedContent(key):
                return "retained \(key)"
            case let .invalidField(key):
                return "invalid \(key)"
            case .brokenChain:
                return "broken chain"
            case .badSignature:
                return "bad signature"
            }
        }
    }

    static let allowedFieldKeys: Set<String> = [
        "durationSeconds",
        "kind",
        "model",
        "org",
        "outcome",
        "reason",
        "seats",
        "sla",
        "source",
        "target",
        "via",
    ]

    static func outcomeToken(_ outcome: String) -> String {
        if outcome.hasPrefix("finished") { return "finished" }
        if outcome.hasPrefix("abandoned") { return "abandoned" }
        if outcome == "cancelled" { return "cancelled" }
        if outcome == "replaced" { return "replaced" }
        return "stopped"
    }

    static func listenKindToken(_ kind: String) -> String {
        kind == "captions" || kind == "insert" ? kind : "other"
    }

    static func listenStopFields(kind: String, outcome: String, elapsedSeconds: Int) -> [String: String] {
        [
            "durationSeconds": String(max(0, min(elapsedSeconds, 9_999_999))),
            "kind": self.listenKindToken(kind),
            "outcome": self.outcomeToken(outcome),
        ]
    }

    static func record(_ kind: Kind, fields: [String: String] = [:]) {
        guard !SettingsStore.isRunningTests else { return }
        do {
            try self.sharedStore().append(kind, seatID: CommercialSeat.currentID, fields: fields)
        } catch {
            let detail = (error as? Failure)?.logDetail ?? error.localizedDescription
            DebugLogger.shared.warning("audit \(detail)", source: "FleetAudit")
        }
    }

    static func recordListenStarted(kind: String) {
        guard !SettingsStore.isRunningTests else { return }
        let settings = SettingsStore.shared
        self.record(
            .listenStarted,
            fields: [
                "kind": self.listenKindToken(kind),
                "model": self.modelToken(settings.selectedSpeechModel.rawValue),
                "source": self.languageToken(settings.translationSourceLanguageID),
                "target": self.languageToken(settings.translationTargetLanguageID),
            ]
        )
    }

    static func recordListenStopped(kind: String, outcome: String, startedUptime: TimeInterval, now: TimeInterval) {
        guard !SettingsStore.isRunningTests else { return }
        let elapsed = Int((max(0, now - startedUptime)).rounded())
        self.record(
            .listenStopped,
            fields: self.listenStopFields(kind: kind, outcome: outcome, elapsedSeconds: elapsed)
        )
    }

    static func eventCount() -> Int {
        guard !SettingsStore.isRunningTests else { return 0 }
        return (try? self.sharedStore().lineCount()) ?? 0
    }

    static func exportData() throws -> Data {
        guard !SettingsStore.isRunningTests else { return Data() }
        let data = try self.sharedStore().exportData()
        self.record(.auditExported, fields: ["via": "user"])
        return data
    }

    static func clear() {
        guard !SettingsStore.isRunningTests else { return }
        try? self.sharedStore().clear(seatID: CommercialSeat.currentID)
    }

    static func validate(_ fields: [String: String]) throws {
        for (key, value) in fields {
            guard self.allowedFieldKeys.contains(key) else { throw Failure.retainedContent(key) }
            guard self.isAllowedValue(key, value) else { throw Failure.invalidField(key) }
        }
    }

    static func verifyExport(_ data: Data) -> Result<Int, Failure> {
        guard let export = try? JSONDecoder().decode(FleetAuditStore.ExportDocument.self, from: data),
              export.product == CommercialLicense.productID,
              let keyData = Data(base64Encoded: export.publicKey),
              let publicKey = try? Curve25519.Signing.PublicKey(rawRepresentation: keyData)
        else {
            return .failure(.brokenChain)
        }
        do {
            try self.verify(export.events, publicKey: publicKey)
            return .success(export.events.count)
        } catch let failure as Failure {
            return .failure(failure)
        } catch {
            return .failure(.brokenChain)
        }
    }

    private static let sharedLock = NSLock()
    private static var cachedStore: FleetAuditStore?

    private static func sharedStore() throws -> FleetAuditStore {
        self.sharedLock.lock()
        defer { self.sharedLock.unlock() }
        if let cachedStore = self.cachedStore {
            return cachedStore
        }
        let directory = AppSupportDirectory.url().appendingPathComponent("Fleet", isDirectory: true)
        let store = try FleetAuditStore(directory: directory)
        self.cachedStore = store
        return store
    }

    private static func languageToken(_ raw: String) -> String {
        let token = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard token.range(of: "^[a-z]{2,8}$", options: .regularExpression) != nil else { return "other" }
        return token
    }

    private static func modelToken(_ raw: String) -> String {
        let token = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard token.range(of: "^[a-z0-9.-]{1,64}$", options: .regularExpression) != nil else { return "other" }
        return token
    }

    private static func isAllowedValue(_ key: String, _ value: String) -> Bool {
        switch key {
        case "org":
            return !value.isEmpty && value.count <= 200 && !value.contains { $0.isNewline }
        case "kind":
            return value == "captions" || value == "insert" || value == "other"
        case "model":
            return value == "other" || value.range(of: "^[a-z0-9.-]{1,64}$", options: .regularExpression) != nil
        case "source", "target":
            return value == "other" || value.range(of: "^[a-z]{2,8}$", options: .regularExpression) != nil
        case "outcome":
            return ["finished", "cancelled", "abandoned", "replaced", "stopped"].contains(value)
        case "reason":
            return CommercialSeat.Decision.Reason(rawValue: value) != nil
        case "via":
            return value == "mdm" || value == "user"
        case "seats":
            return value.range(of: "^[1-9][0-9]{0,5}$", options: .regularExpression) != nil
        case "sla":
            return value == "true" || value == "false"
        case "durationSeconds":
            return value.range(of: "^[0-9]{1,7}$", options: .regularExpression) != nil
        default:
            return false
        }
    }

    static func verify(_ events: [FleetAuditStore.Line], publicKey: Curve25519.Signing.PublicKey) throws {
        var previous = ""
        for (index, line) in events.enumerated() {
            guard line.seq == index + 1, line.prev == previous else { throw Failure.brokenChain }
            let body = try FleetAuditStore.canonicalBody(line)
            let digest = Data(SHA256.hash(data: body))
            guard FleetAuditStore.hex(digest) == line.hash else { throw Failure.brokenChain }
            guard let signature = Data(base64URLEncoded: line.sig),
                  publicKey.isValidSignature(signature, for: digest)
            else {
                throw Failure.badSignature
            }
            previous = line.hash
        }
    }
}

final class FleetAuditStore: @unchecked Sendable {
    struct Line: Codable, Equatable, Sendable {
        var at: String
        var fields: [String: String]
        var hash: String
        var kind: String
        var prev: String
        var seat: String
        var seq: Int
        var sig: String
    }

    struct ExportDocument: Codable, Equatable, Sendable {
        var product: String
        var publicKey: String
        var events: [Line]
    }

    let publicKeyBase64: String

    #if DEBUG
    var logFileForTesting: URL { self.logURL }
    var signingKeyMaterialForTesting: String { self.privateKey.rawRepresentation.base64EncodedString() }
    #endif

    private let directory: URL
    private let privateKey: Curve25519.Signing.PrivateKey
    private let now: () -> Date
    private let lock = NSLock()
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    private var logURL: URL {
        self.directory.appendingPathComponent("audit.log")
    }

    init(
        directory: URL,
        privateKey: Curve25519.Signing.PrivateKey? = nil,
        now: @escaping () -> Date = Date.init
    ) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let key = try Self.loadOrCreateKey(in: directory, preferred: privateKey)
        self.directory = directory
        self.privateKey = key
        self.publicKeyBase64 = key.publicKey.rawRepresentation.base64EncodedString()
        self.now = now
    }

    func append(_ kind: FleetAudit.Kind, seatID: String, fields: [String: String], at date: Date? = nil) throws {
        try FleetAudit.validate(fields)
        self.lock.lock()
        defer { self.lock.unlock() }
        try self.appendUnlocked(kind, seatID: seatID, fields: fields, at: date ?? self.now())
    }

    func lineCount() -> Int {
        self.lock.lock()
        defer { self.lock.unlock() }
        guard let text = try? String(contentsOf: self.logURL, encoding: .utf8) else { return 0 }
        return text.split(separator: "\n", omittingEmptySubsequences: true).count
    }

    func exportData() throws -> Data {
        self.lock.lock()
        defer { self.lock.unlock() }
        let events = try self.readLines()
        let keyData = Data(base64Encoded: self.publicKeyBase64) ?? Data()
        guard let publicKey = try? Curve25519.Signing.PublicKey(rawRepresentation: keyData) else {
            throw FleetAudit.Failure.badSignature
        }
        try FleetAudit.verify(events, publicKey: publicKey)
        let export = ExportDocument(
            product: CommercialLicense.productID,
            publicKey: self.publicKeyBase64,
            events: events
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(export)
    }

    func clear(seatID: String) throws {
        self.lock.lock()
        defer { self.lock.unlock() }
        if FileManager.default.fileExists(atPath: self.logURL.path) {
            try FileManager.default.removeItem(at: self.logURL)
        }
        try self.appendUnlocked(.auditCleared, seatID: seatID, fields: [:], at: self.now())
    }

    fileprivate static func canonicalBody(_ line: Line) throws -> Data {
        let body = Body(
            at: line.at,
            fields: line.fields,
            kind: line.kind,
            prev: line.prev,
            seat: line.seat,
            seq: line.seq
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(body)
    }

    fileprivate static func hex(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }

    private func appendUnlocked(
        _ kind: FleetAudit.Kind,
        seatID: String,
        fields: [String: String],
        at date: Date
    ) throws {
        let existing = try self.readLines()
        try FleetAudit.verify(existing, publicKey: self.privateKey.publicKey)
        let previous = existing.last?.hash ?? ""
        let seat = CommercialSeat.isSeatID(seatID) ? CommercialSeat.normalize(seatID) : "unknown"
        let lineWithoutProof = Line(
            at: Self.stamp.string(from: date),
            fields: fields,
            hash: "",
            kind: kind.rawValue,
            prev: previous,
            seat: seat,
            seq: existing.count + 1,
            sig: ""
        )
        let body = try Self.canonicalBody(lineWithoutProof)
        let digest = Data(SHA256.hash(data: body))
        let signature = try self.privateKey.signature(for: digest)
        let line = Line(
            at: lineWithoutProof.at,
            fields: fields,
            hash: Self.hex(digest),
            kind: kind.rawValue,
            prev: previous,
            seat: lineWithoutProof.seat,
            seq: lineWithoutProof.seq,
            sig: signature.base64URLEncodedString
        )
        var text = ""
        if !existing.isEmpty {
            text = try String(contentsOf: self.logURL, encoding: .utf8)
            if !text.hasSuffix("\n") {
                text += "\n"
            }
        }
        let encodedLine = try self.encoder.encode(line)
        guard let encodedText = String(bytes: encodedLine, encoding: .utf8) else {
            throw FleetAudit.Failure.brokenChain
        }
        text += encodedText
        text += "\n"
        try text.write(to: self.logURL, atomically: true, encoding: .utf8)
    }

    private func readLines() throws -> [Line] {
        guard FileManager.default.fileExists(atPath: self.logURL.path) else { return [] }
        let text = try String(contentsOf: self.logURL, encoding: .utf8)
        var lines: [Line] = []
        for raw in text.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let line = try? JSONDecoder().decode(Line.self, from: Data(raw.utf8)) else {
                throw FleetAudit.Failure.brokenChain
            }
            lines.append(line)
        }
        return lines
    }

    private static func loadOrCreateKey(
        in directory: URL,
        preferred: Curve25519.Signing.PrivateKey?
    ) throws -> Curve25519.Signing.PrivateKey {
        let url = directory.appendingPathComponent("audit-signing-key")
        let key: Curve25519.Signing.PrivateKey
        if let preferred {
            key = preferred
        } else if let stored = try? String(contentsOf: url, encoding: .utf8),
                  let data = Data(base64Encoded: stored.trimmingCharacters(in: .whitespacesAndNewlines)),
                  let loaded = try? Curve25519.Signing.PrivateKey(rawRepresentation: data)
        {
            return loaded
        } else {
            key = Curve25519.Signing.PrivateKey()
        }
        try key.rawRepresentation.base64EncodedString().write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        let publicURL = directory.appendingPathComponent("audit-public-key")
        try key.publicKey.rawRepresentation.base64EncodedString().write(to: publicURL, atomically: true, encoding: .utf8)
        return key
    }

    private static let stamp: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()

    private struct Body: Encodable {
        var at: String
        var fields: [String: String]
        var kind: String
        var prev: String
        var seat: String
        var seq: Int
    }
}
