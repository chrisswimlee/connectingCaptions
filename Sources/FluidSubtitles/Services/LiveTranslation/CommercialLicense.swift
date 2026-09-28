import CryptoKit
import Foundation

/// Air-gapped commercial license token: `base64url(json).base64url(ed25519)`.
nonisolated enum CommercialLicense {
    static let productID = "fluidSubtitles"
    static let productionPublicKeyBase64 = "RN2najSvCJkPkRf1fR5s+bfdAo0QXXLLR/C2AWLfhhA="

    static let productionPublicKey: Curve25519.Signing.PublicKey = {
        guard let data = Data(base64Encoded: productionPublicKeyBase64),
              let key = try? Curve25519.Signing.PublicKey(rawRepresentation: data)
        else {
            preconditionFailure("CommercialLicense public key is invalid")
        }
        return key
    }()

    struct Record: Equatable, Sendable {
        var product: String
        var org: String
        var seats: Int
        var issued: Date
        var expires: Date
        /// Written response window. Omitted keys stay false so older tokens still verify.
        var sla: Bool = false
        /// When true, Licensed to requires this Mac on a signed seat list. Listen stays unlocked either way.
        var enforceSeats: Bool = false

        var licensedToLine: String {
            "Licensed to \(self.org)"
        }

        func expiryLine(formatter: DateFormatter = Record.displayFormatter) -> String {
            "Through \(formatter.string(from: self.expires))"
        }

        static let displayFormatter: DateFormatter = {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = "d MMM yyyy"
            return formatter
        }()
    }

    enum Failure: Equatable, LocalizedError {
        case malformed
        case badSignature
        case wrongProduct
        case expired
        case invalidRecord
        case notSaved

        var errorDescription: String? {
            switch self {
            case .malformed:
                return "That is not a fluidSubtitles license key."
            case .badSignature:
                return "That key is not signed for this app."
            case .wrongProduct:
                return "That key is not for fluidSubtitles."
            case .expired:
                return "That key has expired."
            case .invalidRecord:
                return "That key is missing an organization, seats, or dates."
            case .notSaved:
                return "The key checked out, but Keychain would not save it."
            }
        }
    }

    struct Wire: Codable, Equatable, Sendable {
        var product: String
        var org: String
        var seats: Int
        var issued: String
        var expires: String
        var sla: Bool?
        var enforceSeats: Bool?

        enum CodingKeys: String, CodingKey {
            case product
            case org
            case seats
            case issued
            case expires
            case sla
            case enforceSeats
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(self.product, forKey: .product)
            try container.encode(self.org, forKey: .org)
            try container.encode(self.seats, forKey: .seats)
            try container.encode(self.issued, forKey: .issued)
            try container.encode(self.expires, forKey: .expires)
            try container.encodeIfPresent(self.sla, forKey: .sla)
            try container.encodeIfPresent(self.enforceSeats, forKey: .enforceSeats)
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.product = try container.decode(String.self, forKey: .product)
            self.org = try container.decode(String.self, forKey: .org)
            self.seats = try container.decode(Int.self, forKey: .seats)
            self.issued = try container.decode(String.self, forKey: .issued)
            self.expires = try container.decode(String.self, forKey: .expires)
            self.sla = try container.decodeIfPresent(Bool.self, forKey: .sla)
            self.enforceSeats = try container.decodeIfPresent(Bool.self, forKey: .enforceSeats)
        }

        init(
            product: String,
            org: String,
            seats: Int,
            issued: String,
            expires: String,
            sla: Bool? = nil,
            enforceSeats: Bool? = nil
        ) {
            self.product = product
            self.org = org
            self.seats = seats
            self.issued = issued
            self.expires = expires
            self.sla = sla
            self.enforceSeats = enforceSeats
        }
    }

    static func makeToken(
        record: Record,
        privateKey: Curve25519.Signing.PrivateKey
    ) throws -> String {
        let payload = try self.encodePayload(self.wire(from: record))
        let signature = try privateKey.signature(for: payload)
        return "\(payload.base64URLEncodedString).\(signature.base64URLEncodedString)"
    }

    static func verify(
        _ token: String,
        publicKey: Curve25519.Signing.PublicKey = productionPublicKey,
        now: Date = Date()
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
        return self.record(from: wire, now: now)
    }

    static func record(from wire: Wire, now: Date = Date()) -> Result<Record, Failure> {
        let org = wire.org.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !org.isEmpty, wire.seats >= 1,
              let issued = self.day(from: wire.issued),
              let expires = self.day(from: wire.expires)
        else {
            return .failure(.invalidRecord)
        }
        guard wire.product == self.productID else {
            return .failure(.wrongProduct)
        }
        let record = Record(
            product: wire.product,
            org: org,
            seats: wire.seats,
            issued: issued,
            expires: expires,
            sla: wire.sla == true,
            enforceSeats: wire.enforceSeats == true
        )
        if now >= self.endOfDay(expires) {
            return .failure(.expired)
        }
        return .success(record)
    }

    static func wire(from record: Record) -> Wire {
        Wire(
            product: record.product,
            org: record.org,
            seats: record.seats,
            issued: self.dayString(record.issued),
            expires: self.dayString(record.expires),
            sla: record.sla ? true : nil,
            enforceSeats: record.enforceSeats ? true : nil
        )
    }

    static func encodePayload(_ wire: Wire) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(wire)
    }

    static func day(from string: String) -> Date? {
        self.dayFormatter.date(from: string)
    }

    static func dayString(_ date: Date) -> String {
        self.dayFormatter.string(from: date)
    }

    static func endOfDay(_ date: Date) -> Date {
        self.utcCalendar.date(byAdding: .day, value: 1, to: date) ?? date
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

extension Data {
    var base64URLEncodedString: String {
        self.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    init?(base64URLEncoded string: String) {
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
