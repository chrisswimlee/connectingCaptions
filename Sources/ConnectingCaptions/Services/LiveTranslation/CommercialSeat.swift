import CryptoKit
import Foundation
import IOKit

/// This Mac's seat id is its hardware UUID, the same id Jamf and Fleet already inventory.
/// A signed roster says which of those Macs the organization paid for.
/// Refusal does not lock Listen.
nonisolated enum CommercialSeat {
    #if DEBUG
    nonisolated(unsafe) static var machineIDOverride: String?
    #endif
    private nonisolated(unsafe) static var cachedMachineID: String?

    struct Roster: Equatable, Sendable {
        var product: String
        var org: String
        var seatIDs: [String]
        var issued: Date
        var expires: Date
    }

    enum Decision: Equatable, Sendable {
        case notRequired
        case accepted(seatCount: Int)
        case refused(Reason)

        enum Reason: String, Equatable, Sendable {
            case missingRoster
            case notOnRoster
            case overCapacity
            case orgMismatch
            case invalidRoster
        }

        var coversThisMac: Bool {
            switch self {
            case .notRequired, .accepted:
                return true
            case .refused:
                return false
            }
        }

        var refusalLine: String? {
            switch self {
            case .notRequired, .accepted:
                return nil
            case let .refused(reason):
                return "\(reason.explanation) Personal use stays free. Listen stays unlocked."
            }
        }
    }

    static var currentID: String {
        #if DEBUG
        if let override = self.machineIDOverride?.trimmingCharacters(in: .whitespacesAndNewlines),
           !override.isEmpty
        {
            return self.normalize(override)
        }
        #endif
        if let cachedMachineID = self.cachedMachineID {
            return cachedMachineID
        }
        let resolved = self.platformUUID().map(self.normalize) ?? self.fallbackID()
        self.cachedMachineID = resolved
        return resolved
    }

    static func normalize(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "{}"))
            .uppercased()
    }

    static func isSeatID(_ raw: String) -> Bool {
        let id = self.normalize(raw)
        guard (8 ... 64).contains(id.count) else { return false }
        return id.allSatisfy { $0.isHexDigit || $0 == "-" }
    }

    static func makeToken(
        roster: Roster,
        privateKey: Curve25519.Signing.PrivateKey
    ) throws -> String {
        guard let seatIDs = self.canonicalSeatIDs(roster.seatIDs) else {
            throw CommercialLicense.Failure.invalidRecord
        }
        var canonical = roster
        canonical.seatIDs = seatIDs
        let payload = try self.encodePayload(self.wire(from: canonical))
        let signature = try privateKey.signature(for: payload)
        return "\(payload.base64URLEncodedString).\(signature.base64URLEncodedString)"
    }

    static func verify(
        _ token: String,
        publicKey: Curve25519.Signing.PublicKey = CommercialLicense.productionPublicKey,
        now: Date = Date()
    ) -> Result<Roster, CommercialLicense.Failure> {
        let parts = token.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 2,
              let payload = Data(base64URLEncoded: String(parts[0])),
              let signature = Data(base64URLEncoded: String(parts[1]))
        else {
            return .failure(.malformed)
        }
        guard publicKey.isValidSignature(signature, for: payload) else {
            return .failure(.badSignature)
        }
        guard let wire = try? JSONDecoder().decode(Wire.self, from: payload) else {
            return .failure(.malformed)
        }
        return self.roster(from: wire, now: now)
    }

    static func decide(
        license: CommercialLicense.Record,
        rosterToken: String?,
        seatID: String,
        publicKey: Curve25519.Signing.PublicKey = CommercialLicense.productionPublicKey,
        now: Date = Date()
    ) -> Decision {
        guard license.enforceSeats else { return .notRequired }
        let trimmed = rosterToken?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return .refused(.missingRoster) }
        switch self.verify(trimmed, publicKey: publicKey, now: now) {
        case let .failure:
            return .refused(.invalidRoster)
        case let .success(roster):
            guard roster.org == license.org else { return .refused(.orgMismatch) }
            guard roster.seatIDs.count <= license.seats else { return .refused(.overCapacity) }
            guard roster.seatIDs.contains(self.normalize(seatID)) else { return .refused(.notOnRoster) }
            return .accepted(seatCount: roster.seatIDs.count)
        }
    }

    static func roster(from wire: Wire, now: Date = Date()) -> Result<Roster, CommercialLicense.Failure> {
        let org = wire.org.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let seatIDs = self.canonicalSeatIDs(wire.seatIDs), !org.isEmpty,
              let issued = CommercialLicense.day(from: wire.issued),
              let expires = CommercialLicense.day(from: wire.expires)
        else {
            return .failure(.invalidRecord)
        }
        guard wire.product == CommercialLicense.productID else {
            return .failure(.wrongProduct)
        }
        let roster = Roster(
            product: wire.product,
            org: org,
            seatIDs: seatIDs,
            issued: issued,
            expires: expires
        )
        if now >= CommercialLicense.endOfDay(expires) {
            return .failure(.expired)
        }
        return .success(roster)
    }

    static func wire(from roster: Roster) -> Wire {
        Wire(
            product: roster.product,
            org: roster.org,
            seatIDs: roster.seatIDs,
            issued: CommercialLicense.dayString(roster.issued),
            expires: CommercialLicense.dayString(roster.expires)
        )
    }

    static func encodePayload(_ wire: Wire) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(wire)
    }

    static func canonicalSeatIDs(_ raw: [String]) -> [String]? {
        guard !raw.isEmpty, raw.allSatisfy(self.isSeatID) else { return nil }
        return Array(Set(raw.map(self.normalize))).sorted()
    }

    private static func fallbackID() -> String {
        let key = "CommercialSeatFallbackID"
        if let stored = UserDefaults.standard.string(forKey: key), self.isSeatID(stored) {
            return self.normalize(stored)
        }
        let created = self.normalize(UUID().uuidString)
        UserDefaults.standard.set(created, forKey: key)
        return created
    }

    private static func platformUUID() -> String? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPlatformExpertDevice"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        guard let unmanaged = IORegistryEntryCreateCFProperty(
            service,
            kIOPlatformUUIDKey as CFString,
            kCFAllocatorDefault,
            0
        ) else {
            return nil
        }
        let value = unmanaged.takeRetainedValue() as? String
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    struct Wire: Codable, Equatable, Sendable {
        var product: String
        var org: String
        var seatIDs: [String]
        var issued: String
        var expires: String
    }
}

extension CommercialSeat.Decision.Reason {
    fileprivate var explanation: String {
        switch self {
        case .missingRoster:
            return "Seat enforcement is on, and this Mac has no seat list."
        case .notOnRoster:
            return "This Mac is outside the seat list."
        case .overCapacity:
            return "The seat list is longer than the license."
        case .orgMismatch:
            return "The seat list names a different organization."
        case .invalidRoster:
            return "The seat list is unsigned, expired, or damaged."
        }
    }
}
