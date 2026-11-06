import CryptoKit
import Foundation

/// Air-gapped commercial license token: `base64url(json).base64url(ed25519)`.
nonisolated enum CommercialLicense {
    static let productID = "connectingCaptions"
    static let productionPublicKeyBase64 = "6nbqb139VJ4xw6MbtwejD0I3fa3Ej7ILAqMuNZtHHPk="

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
        /// When true, Licensed to requires this Mac on a signed seat list. Listen stays off when this Mac is outside that list.
        var enforceSeats: Bool = false
        /// Sold once, for one person. The organization line stays empty of a company name.
        var personal: Bool = false
        /// Personal keys include updates through this major version. Organization keys omit it.
        var updatesThroughMajor: Int? = nil
        /// Hardware UUIDs for a personal key. Empty means the key is not tied to a Mac.
        var macs: [String] = []

        var licensedToLine: String {
            "Licensed to \(self.org)"
        }

        var coverageTitle: String {
            self.personal ? "Personal license" : self.licensedToLine
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
        case notYetValid
        case invalidRecord
        case notSaved
        case outsideVersion(Int)
        case wrongMac

        var errorDescription: String? {
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
            case .notSaved:
                return "The key checked out, but Keychain would not save it."
            case let .outsideVersion(major):
                return "That key includes updates for version \(major)."
            case .wrongMac:
                return "That key is for a different Mac."
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
        var personal: Bool?
        var major: Int?
        var macs: [String]?

        enum CodingKeys: String, CodingKey {
            case product
            case org
            case seats
            case issued
            case expires
            case sla
            case enforceSeats
            case personal
            case major
            case macs
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
            try container.encodeIfPresent(self.personal, forKey: .personal)
            try container.encodeIfPresent(self.major, forKey: .major)
            try container.encodeIfPresent(self.macs, forKey: .macs)
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
            self.personal = try container.decodeIfPresent(Bool.self, forKey: .personal)
            self.major = try container.decodeIfPresent(Int.self, forKey: .major)
            self.macs = try container.decodeIfPresent([String].self, forKey: .macs)
        }

        init(
            product: String,
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
        now: Date = Date(),
        appVersion: String = CommercialLicense.runningAppVersion,
        machineID: String? = nil
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
        return self.record(from: wire, now: now, appVersion: appVersion, machineID: machineID)
    }

    static func record(from wire: Wire, now: Date = Date(), appVersion: String = CommercialLicense.runningAppVersion, machineID: String? = nil) -> Result<Record, Failure> {
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
        let personal = wire.personal == true
        if personal, !(1 ... 2).contains(wire.seats) || wire.sla == true || wire.enforceSeats == true {
            return .failure(.invalidRecord)
        }
        let updatesThroughMajor = personal ? (wire.major ?? 1) : wire.major
        if let updatesThroughMajor, updatesThroughMajor < 1 {
            return .failure(.invalidRecord)
        }
        if personal, self.majorVersion(of: appVersion) > (updatesThroughMajor ?? 1) {
            return .failure(.outsideVersion(updatesThroughMajor ?? 1))
        }
        let macs = (wire.macs ?? []).map(CommercialSeat.normalize)
        if personal, !macs.isEmpty {
            guard (1 ... 2).contains(macs.count), macs.count <= wire.seats, macs.allSatisfy(CommercialSeat.isSeatID) else {
                return .failure(.invalidRecord)
            }
            if let machineID, !macs.contains(CommercialSeat.normalize(machineID)) {
                return .failure(.wrongMac)
            }
        }
        let record = Record(
            product: wire.product,
            org: org,
            seats: wire.seats,
            issued: issued,
            expires: expires,
            sla: wire.sla == true,
            enforceSeats: wire.enforceSeats == true,
            personal: personal,
            updatesThroughMajor: personal ? updatesThroughMajor : nil,
            macs: personal ? macs : []
        )
        if now < issued {
            return .failure(.notYetValid)
        }
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
            enforceSeats: record.enforceSeats ? true : nil,
            personal: record.personal ? true : nil,
            major: record.personal ? (record.updatesThroughMajor ?? 1) : nil,
            macs: record.macs.isEmpty ? nil : record.macs
        )
    }

    static var runningAppVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    static func majorVersion(of version: String) -> Int {
        Int(version.split(separator: ".").first ?? "") ?? 1
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
