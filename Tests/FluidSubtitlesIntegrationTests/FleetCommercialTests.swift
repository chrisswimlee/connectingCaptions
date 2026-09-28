import CryptoKit
@testable import FluidSubtitles_Debug
import XCTest

@MainActor
final class FleetCommercialTests: XCTestCase {
    private let seatID = "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"
    private let otherSeatID = "11111111-2222-3333-4444-555555555555"
    private var privateKey: Curve25519.Signing.PrivateKey!
    private var directory: URL!
    private var spokenLine: TheaterSpokenLineMode!
    private var captionSize: Int!

    override func setUp() {
        super.setUp()
        self.privateKey = Curve25519.Signing.PrivateKey()
        self.directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("fleet-tests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
        SettingsStore.licenseVerifyingKeyOverride = self.privateKey.publicKey
        FleetManagedDirectory.machineRootOverride = self.directory
        CommercialSeat.machineIDOverride = self.seatID
        let settings = SettingsStore.shared
        settings.removeCommercialLicense()
        settings.resetManagedFleetBookkeeping()
        self.spokenLine = settings.theaterSpokenLineMode
        self.captionSize = settings.presenterFontSize
    }

    override func tearDown() {
        let settings = SettingsStore.shared
        settings.theaterSpokenLineMode = self.spokenLine
        settings.presenterFontSize = self.captionSize
        settings.removeCommercialLicense()
        settings.resetManagedFleetBookkeeping()
        SettingsStore.licenseVerifyingKeyOverride = nil
        FleetManagedDirectory.machineRootOverride = nil
        CommercialSeat.machineIDOverride = nil
        try? FileManager.default.removeItem(at: self.directory)
        super.tearDown()
    }

    func testOptionalClaimsStayOffTheTokenUntilSet() throws {
        let plain = try CommercialLicense.makeToken(record: self.license(), privateKey: self.privateKey)
        let plainJSON = try self.payloadJSON(plain)
        XCTAssertNil(plainJSON["sla"])
        XCTAssertNil(plainJSON["enforceSeats"])

        var claimed = self.license()
        claimed.sla = true
        claimed.enforceSeats = true
        let token = try CommercialLicense.makeToken(record: claimed, privateKey: self.privateKey)
        let verified = try CommercialLicense.verify(token, publicKey: self.privateKey.publicKey).get()
        XCTAssertTrue(verified.sla)
        XCTAssertTrue(verified.enforceSeats)
    }

    func testSeatListCoversOnlyListedMacs() throws {
        let license = self.license(seats: 2, enforceSeats: true)
        let roster = try self.rosterToken([self.seatID, self.otherSeatID])
        let accepted = CommercialSeat.decide(
            license: license,
            rosterToken: roster,
            seatID: self.seatID,
            publicKey: self.privateKey.publicKey
        )
        XCTAssertEqual(accepted, CommercialSeat.Decision.accepted(seatCount: 2))

        let outside = CommercialSeat.decide(
            license: license,
            rosterToken: try self.rosterToken([self.otherSeatID]),
            seatID: self.seatID,
            publicKey: self.privateKey.publicKey
        )
        XCTAssertEqual(outside, CommercialSeat.Decision.refused(.notOnRoster))
        XCTAssertTrue(outside.refusalLine?.contains("Listen stays unlocked") == true)
    }

    func testOverCapacityAndMissingListRefuseWithoutLockingListen() throws {
        let license = self.license(seats: 1, enforceSeats: true)
        let crowded = CommercialSeat.decide(
            license: license,
            rosterToken: try self.rosterToken([self.seatID, self.otherSeatID]),
            seatID: self.seatID,
            publicKey: self.privateKey.publicKey
        )
        XCTAssertEqual(crowded, CommercialSeat.Decision.refused(.overCapacity))

        let missing = CommercialSeat.decide(
            license: license,
            rosterToken: nil,
            seatID: self.seatID,
            publicKey: self.privateKey.publicKey
        )
        XCTAssertEqual(missing, CommercialSeat.Decision.refused(.missingRoster))
        XCTAssertFalse(missing.coversThisMac)
        XCTAssertTrue(missing.refusalLine?.contains("Listen stays unlocked") == true)
    }

    func testUnenforcedKeyStaysLicensedWithoutASeatList() throws {
        let settings = SettingsStore.shared
        let token = try CommercialLicense.makeToken(record: self.license(), privateKey: self.privateKey)
        _ = settings.activateCommercialLicense(token)
        XCTAssertTrue(settings.isCommerciallyLicensed)
        XCTAssertEqual(
            settings.seatDecision(for: try XCTUnwrap(settings.commercialLicenseRecord)),
            CommercialSeat.Decision.notRequired
        )
    }

    func testEnforcedKeyOnThisMacShowsTheSeatList() throws {
        let settings = SettingsStore.shared
        let token = try CommercialLicense.makeToken(
            record: self.license(enforceSeats: true),
            privateKey: self.privateKey
        )
        try self.rosterToken([self.seatID]).write(
            to: self.directory.appendingPathComponent(FleetManagedDirectory.rosterFileName),
            atomically: true,
            encoding: .utf8
        )
        _ = settings.activateCommercialLicense(token)
        XCTAssertTrue(settings.isCommerciallyLicensed)
        let record = try XCTUnwrap(settings.commercialLicenseRecord)
        XCTAssertTrue(settings.commercialCoverageLine(for: record).contains("on the seat list"))
    }

    func testEnforcedKeyOutsideTheListKeepsListenUnlocked() throws {
        let settings = SettingsStore.shared
        let token = try CommercialLicense.makeToken(
            record: self.license(org: "Harbor Law", enforceSeats: true),
            privateKey: self.privateKey
        )
        _ = settings.activateCommercialLicense(token)
        XCTAssertFalse(settings.isCommerciallyLicensed)
        XCTAssertEqual(settings.commercialLicenseRecord?.org, "Harbor Law")
        XCTAssertTrue(settings.commercialSeatRefusal?.contains("Listen stays unlocked") == true)
    }

    func testManagedLicenseWinsOverAPastedKey() throws {
        let settings = SettingsStore.shared
        let managed = try CommercialLicense.makeToken(
            record: self.license(org: "Managed LLP"),
            privateKey: self.privateKey
        )
        try managed.write(
            to: self.directory.appendingPathComponent(FleetManagedDirectory.licenseFileName),
            atomically: true,
            encoding: .utf8
        )
        let pasted = try CommercialLicense.makeToken(
            record: self.license(org: "Pasted LLP"),
            privateKey: self.privateKey
        )
        _ = settings.activateCommercialLicense(pasted)
        XCTAssertEqual(settings.commercialLicenseRecord?.org, "Managed LLP")
        XCTAssertTrue(settings.commercialLicenseIsManaged)
    }

    func testFleetSettingsRejectCaptionsAndApplyCaptionPolicy() throws {
        let settings = SettingsStore.shared
        settings.theaterSpokenLineMode = .off
        settings.presenterFontSize = 42
        let poisoned = Data(#"{"product":"fluidSubtitles","spokenLine":"afterPause","transcript":"secret words"}"#.utf8)
        XCTAssertThrowsError(try FleetSettingsDocument.decode(poisoned)) { error in
            let text = error.localizedDescription
            XCTAssertFalse(text.contains("transcript"))
            XCTAssertFalse(text.contains("spokenLine"))
            XCTAssertTrue(text.contains("caption policy"))
        }
        XCTAssertEqual(settings.theaterSpokenLineMode, .off)

        let clean = Data(
            #"{"product":"fluidSubtitles","spokenLine":"afterPause","captionSize":36}"#.utf8
        )
        try settings.restoreFleetSettingsData(clean)
        XCTAssertEqual(settings.theaterSpokenLineMode, .afterPause)
        XCTAssertEqual(settings.presenterFontSize, 36)

        try clean.write(
            to: self.directory.appendingPathComponent(FleetManagedDirectory.settingsFileName),
            options: .atomic
        )
        settings.theaterSpokenLineMode = .off
        settings.applyManagedFleetIfNeeded()
        XCTAssertEqual(settings.theaterSpokenLineMode, .afterPause)
        settings.theaterSpokenLineMode = .off
        settings.applyManagedFleetIfNeeded()
        XCTAssertEqual(settings.theaterSpokenLineMode, .off)
    }

    func testAuditChainRejectsCaptionsAndTampering() throws {
        let store = try FleetAuditStore(directory: self.directory.appendingPathComponent("audit", isDirectory: true))
        let seat = self.seatID
        try store.append(.listenStarted, seatID: seat, fields: ["kind": "captions", "source": "en", "target": "ko"])
        XCTAssertThrowsError(
            try store.append(.listenStopped, seatID: seat, fields: ["transcript": "the words that were said"])
        )
        XCTAssertEqual(store.lineCount(), 1)

        let fields = FleetAudit.listenStopFields(kind: "captions", outcome: "finished chars=120", elapsedSeconds: 4)
        XCTAssertEqual(fields["outcome"], "finished")
        XCTAssertEqual(fields["durationSeconds"], "4")
        XCTAssertFalse(fields.values.contains { $0.contains("120") || $0.contains("chars") })
        try store.append(.listenStopped, seatID: seat, fields: fields)

        let exported = try store.exportData()
        let text = String(decoding: exported, as: UTF8.self)
        XCTAssertFalse(text.contains("120"))
        XCTAssertFalse(text.contains(store.signingKeyMaterialForTesting))
        XCTAssertEqual(try FleetAudit.verifyExport(exported).get(), 2)

        var tampered = try String(contentsOf: store.logFileForTesting, encoding: .utf8)
        tampered = tampered.replacingOccurrences(of: "captions", with: "insert")
        try tampered.write(to: store.logFileForTesting, atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try store.exportData())

        try store.clear(seatID: seat)
        let cleared = try String(contentsOf: store.logFileForTesting, encoding: .utf8)
        XCTAssertFalse(cleared.contains("captions"))
        XCTAssertTrue(cleared.contains("audit.cleared"))
        XCTAssertEqual(try FleetAudit.verifyExport(try store.exportData()).get(), 1)
    }

    private func license(
        org: String = "Example LLP",
        seats: Int = 25,
        enforceSeats: Bool = false
    ) -> CommercialLicense.Record {
        CommercialLicense.Record(
            product: CommercialLicense.productID,
            org: org,
            seats: seats,
            issued: CommercialLicense.day(from: "2026-09-21") ?? Date(),
            expires: CommercialLicense.day(from: "2027-09-21") ?? Date(),
            sla: false,
            enforceSeats: enforceSeats
        )
    }

    private func rosterToken(_ seatIDs: [String]) throws -> String {
        try CommercialSeat.makeToken(
            roster: CommercialSeat.Roster(
                product: CommercialLicense.productID,
                org: "Example LLP",
                seatIDs: seatIDs,
                issued: CommercialLicense.day(from: "2026-09-21") ?? Date(),
                expires: CommercialLicense.day(from: "2027-09-21") ?? Date()
            ),
            privateKey: self.privateKey
        )
    }

    private func payloadJSON(_ token: String) throws -> [String: Any] {
        let part = try XCTUnwrap(token.split(separator: ".").first)
        let data = try XCTUnwrap(Data(base64URLEncoded: String(part)))
        return try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}
