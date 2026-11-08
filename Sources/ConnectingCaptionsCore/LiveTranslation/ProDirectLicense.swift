import CryptoKit
import Foundation

/// Air-gapped Pro key for the direct-download iPhone and iPad app.
/// The token is `base64url(json).base64url(ed25519)`, the same shape the Mac app verifies.
/// Signature checks run before the payload is trusted. A seat list is a Mac hardware roster,
/// so a key that requires one does not unlock this phone.
public enum ProDirectLicense {
    public static let productID = "connectingCaptions"
    /// Same public key the Mac app bakes in. The private key stays out of this repository.
    public static let productionPublicKeyBase64 = "6nbqb139VJ4xw6MbtwejD0I3fa3Ej7ILAqMuNZtHHPk="

    public static let productionPublicKey: Curve25519.Signing.PublicKey = {
        guard let data = Data(base64Encoded: productionPublicKeyBase64),
              let key = try? Curve25519.Signing.PublicKey(rawRepresentation: data)
        else {
            preconditionFailure("ProDirectLicense public key is invalid")
        }
        return key
    }()

    public struct Record: Equatable, Sendable {
        public var org: String
        public var seats: Int
        public var issued: Date
        public var expires: Date
        public var personal: Bool
        public var coverageTitle: String {
            self.personal ? "Personal license" : "Licensed to \(self.org)"
        }
    }

    public enum Failure: Equatable, LocalizedError {
        case malformed
        case badSignature
        case wrongProduct
        case expired
        case notYetValid
        case invalidRecord
        case outsideVersion(Int)
        case seatList

        public var errorDescription: String? {
            switch self {
            case .malformed:
                return "That is not a Connecting Captions Pro license key."
            case .badSignature:
                return "That key is not signed for this app."
            case .wrongProduct:
                return "That key is not for Connecting Captions Pro."
            case .expired:
                return "That key has expired."
            case .notYetValid:
                return "That key is not active yet."
            case .invalidRecord:
                return "That key is missing an organization, seats, or dates."
            case let .outsideVersion(major):
                return "That key includes updates for version \(major)."
            case .seatList:
                return "That key requires a Mac seat list. It does not unlock this iPhone or iPad."
            }
        }
    }

    public static func verify(
        _ token: String,
        publicKey: Curve25519.Signing.PublicKey = productionPublicKey,
        now: Date = Date(),
        appVersion: String = "1.0.0"
    ) -> Result<Record, Failure> {
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
        return self.record(from: wire, now: now, appVersion: appVersion)
    }

    public static func makeToken(
        wire: Wire,
        privateKey: Curve25519.Signing.PrivateKey
    ) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let payload = try encoder.encode(wire)
        let signature = try privateKey.signature(for: payload)
        return "\(payload.base64URLEncodedString()).\(signature.base64URLEncodedString())"
    }

    static func record(from wire: Wire, now: Date, appVersion: String) -> Result<Record, Failure> {
        let org = wire.org.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !org.isEmpty, wire.seats >= 1,
              let issued = Self.day(from: wire.issued),
              let expires = Self.day(from: wire.expires)
        else {
            return .failure(.invalidRecord)
        }
        guard wire.product == Self.productID else {
            return .failure(.wrongProduct)
        }
        if wire.enforceSeats == true {
            return .failure(.seatList)
        }
        let personal = wire.personal == true
        if personal, !(1 ... 2).contains(wire.seats) || wire.sla == true {
            return .failure(.invalidRecord)
        }
        let updatesThroughMajor = personal ? (wire.major ?? 1) : wire.major
        if let updatesThroughMajor, updatesThroughMajor < 1 {
            return .failure(.invalidRecord)
        }
        if personal, Self.majorVersion(of: appVersion) > (updatesThroughMajor ?? 1) {
            return .failure(.outsideVersion(updatesThroughMajor ?? 1))
        }
        if personal, let macs = wire.macs, !macs.isEmpty {
            guard (1 ... 2).contains(macs.count), macs.count <= wire.seats, macs.allSatisfy(Self.isHardwareUUID) else {
                return .failure(.invalidRecord)
            }
        }
        if now < issued {
            return .failure(.notYetValid)
        }
        if now >= Self.endOfDay(expires) {
            return .failure(.expired)
        }
        return .success(Record(
            org: org,
            seats: wire.seats,
            issued: issued,
            expires: expires,
            personal: personal
        ))
    }

    public static func majorVersion(of version: String) -> Int {
        Int(version.split(separator: ".").first ?? "") ?? 1
    }

    public struct Wire: Codable, Equatable, Sendable {
        public var product: String
        public var org: String
        public var seats: Int
        public var issued: String
        public var expires: String
        public var sla: Bool?
        public var enforceSeats: Bool?
        public var personal: Bool?
        public var major: Int?
        public var macs: [String]?

        public init(
            product: String = ProDirectLicense.productID,
            org: String,
            seats: Int,
            issued: String,
            expires: String,
            sla: Bool? = nil,
            enforceSeats: Bool? = nil,
            personal: Bool? = nil,
            major: Int? = nil,
            macs: [String]? = nil
        ) {
            self.product = product
            self.org = org
            self.seats = seats
            self.issued = issued
            self.expires = expires
            self.sla = sla
            self.enforceSeats = enforceSeats
            self.personal = personal
            self.major = major
            self.macs = macs
        }

        enum CodingKeys: String, CodingKey {
            case product, org, seats, issued, expires, sla, enforceSeats, personal, major, macs
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(self.product, forKey: .product)
            try container.encode(self.org, forKey: .org)
            try container.encode(self.seats, forKey: .seats)
            try container.encode(self.issued, forKey: .issued)
            try container.encode(self.expires, forKey: .expires)
            try container.encodeIfPresent(self.sla, forKey: .sla)
            try container.encodeIfPresent(self.enforceSeats, forKey: .enforceSeats)
            try container.encodeIfPresent(self.personal, forKey: .personal)
            try container.encodeIfPresent(self.major, forKey: .major)
            try container.encodeIfPresent(self.macs, forKey: .macs)
        }
    }

    static func day(from string: String) -> Date? {
        self.dayFormatter.date(from: string)
    }

    static func endOfDay(_ date: Date) -> Date {
        self.utcCalendar.date(byAdding: .day, value: 1, to: date) ?? date
    }

    private static func isHardwareUUID(_ value: String) -> Bool {
        let parts = value.split(separator: "-").map(String.init)
        let expected = [8, 4, 4, 4, 12]
        guard parts.count == expected.count else { return false }
        return zip(parts, expected).allSatisfy { part, count in
            part.count == count && part.allSatisfy { $0.isHexDigit }
        }
    }

    private static let dayFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()

    private static let utcCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return calendar
    }()
}

/// Fourteen UTC days from the first Listen, inclusive of the start day.
public enum ProListenTrial {
    public static let days = 14

    public enum Phase: Equatable, Sendable {
        case notStarted
        case inTrial(day: Int)
        case ended
        case unreadable
    }

    /// A license on the device never blocks Listen. An ended or unreadable trial
    /// blocks Listen only when this download asks for a key.
    public static func blocksListen(hasLicense: Bool, phase: Phase, asksForKey: Bool) -> Bool {
        if hasLicense { return false }
        guard asksForKey else { return false }
        switch phase {
        case .notStarted, .inTrial:
            return false
        case .ended, .unreadable:
            return true
        }
    }

    /// `startedOn` and `highWater` are `YYYY-MM-DD` in UTC.
    /// A clock moved backward does not reopen a day already passed.
    /// A missing clock is unreadable, which keeps Listen off when a key is required.
    public static func phase(startedOn: String?, highWater: String?, now: Date) -> Phase {
        guard let startedOn else { return .notStarted }
        guard let start = ProDirectLicense.day(from: startedOn) else { return .unreadable }
        let effective = self.effectiveNow(highWater: highWater, now: now)
        guard let effective else { return .unreadable }
        if effective < start { return .ended }
        let startDay = self.utcCalendar.startOfDay(for: start)
        let today = self.utcCalendar.startOfDay(for: effective)
        let elapsed = self.utcCalendar.dateComponents([.day], from: startDay, to: today).day ?? 0
        if elapsed < 0 { return .ended }
        if elapsed >= Self.days { return .ended }
        return .inTrial(day: elapsed + 1)
    }

    private static func effectiveNow(highWater: String?, now: Date) -> Date? {
        guard let highWater else { return now }
        guard let marked = ProDirectLicense.day(from: highWater) else { return nil }
        return max(now, marked)
    }

    private static let utcCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return calendar
    }()
}

extension Data {
    fileprivate func base64URLEncodedString() -> String {
        self.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    fileprivate init?(base64URLEncoded string: String) {
        var base64 = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let padding = (4 - base64.count % 4) % 4
        if padding > 0 {
            base64.append(String(repeating: "=", count: padding))
        }
        self.init(base64Encoded: base64)
    }
}
