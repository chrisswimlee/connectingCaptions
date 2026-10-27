import CryptoKit
@testable import ConnectingCaptions_Debug
import XCTest

@MainActor
final class CommercialLicenseTests: XCTestCase {
    private var privateKey: Curve25519.Signing.PrivateKey!

    override func setUp() {
        super.setUp()
        self.privateKey = Curve25519.Signing.PrivateKey()
        SettingsStore.licenseVerifyingKeyOverride = self.privateKey.publicKey
        FleetManagedDirectory.machineRootOverride = nil
        CommercialSeat.machineIDOverride = nil
        SettingsStore.shared.removeCommercialLicense()
        SettingsStore.shared.clearListenTrial()
    }

    override func tearDown() {
        SettingsStore.shared.removeCommercialLicense()
        SettingsStore.shared.clearListenTrial()
        SettingsStore.licenseVerifyingKeyOverride = nil
        super.tearDown()
    }

    func testValidPayloadVerifiesAndExposesOrg() throws {
        let record = try self.makeRecord(org: "Example LLP")
        let token = try CommercialLicense.makeToken(record: record, privateKey: self.privateKey)

        let verified = try CommercialLicense.verify(token, publicKey: self.privateKey.publicKey).get()

        XCTAssertEqual(verified.org, "Example LLP")
        XCTAssertEqual(verified.seats, 25)
        XCTAssertEqual(verified.product, CommercialLicense.productID)
        XCTAssertEqual(verified.licensedToLine, "Licensed to Example LLP")
        XCTAssertTrue(verified.expiryLine().contains("2027"))
    }

    func testWrongSignatureIsRejected() throws {
        let otherKey = Curve25519.Signing.PrivateKey()
        let token = try CommercialLicense.makeToken(
            record: self.makeRecord(),
            privateKey: otherKey
        )

        XCTAssertEqual(
            CommercialLicense.verify(token, publicKey: self.privateKey.publicKey),
            .failure(.badSignature)
        )
    }

    func testWrongProductIsRejected() throws {
        let record = try self.makeRecord(product: "otherApp")
        let token = try CommercialLicense.makeToken(record: record, privateKey: self.privateKey)

        XCTAssertEqual(
            CommercialLicense.verify(token, publicKey: self.privateKey.publicKey),
            .failure(.wrongProduct)
        )
    }

    func testExpiredKeyIsRejected() throws {
        let issued = try XCTUnwrap(CommercialLicense.day(from: "2025-01-01"))
        let expires = try XCTUnwrap(CommercialLicense.day(from: "2025-12-31"))
        let record = CommercialLicense.Record(
            product: CommercialLicense.productID,
            org: "Example LLP",
            seats: 5,
            issued: issued,
            expires: expires
        )
        let token = try CommercialLicense.makeToken(record: record, privateKey: self.privateKey)
        let now = try XCTUnwrap(CommercialLicense.day(from: "2026-01-01"))

        XCTAssertEqual(
            CommercialLicense.verify(token, publicKey: self.privateKey.publicKey, now: now),
            .failure(.expired)
        )
    }

    func testActivateAndRemoveUpdateLicensedState() throws {
        let settings = SettingsStore.shared
        XCTAssertFalse(settings.isCommerciallyLicensed)

        let token = try CommercialLicense.makeToken(
            record: self.makeRecord(org: "Harbor Law"),
            privateKey: self.privateKey
        )
        let activated = settings.activateCommercialLicense(token)

        XCTAssertEqual(try activated.get().org, "Harbor Law")
        XCTAssertTrue(settings.isCommerciallyLicensed)
        XCTAssertEqual(settings.commercialLicenseRecord?.org, "Harbor Law")

        settings.removeCommercialLicense()

        XCTAssertFalse(settings.isCommerciallyLicensed)
        XCTAssertNil(settings.commercialLicenseRecord)
        XCTAssertNil(settings.commercialLicenseToken)
    }

    func testMalformedTokenIsRejected() {
        XCTAssertEqual(CommercialLicense.verify("not-a-key"), .failure(.malformed))
        XCTAssertEqual(
            SettingsStore.shared.activateCommercialLicense("not-a-key"),
            .failure(.malformed)
        )
    }

    func testCommercialLicenseURLsPointAtTheSiteAndMail() {
        XCTAssertEqual(
            ConnectingCaptionsProduct.commercialLicenseURL.absoluteString,
            "https://local-host.ai/connectingCaptions/license/"
        )
        XCTAssertEqual(ConnectingCaptionsProduct.commercialLicenseMailURL.scheme, "mailto")
        XCTAssertTrue(ConnectingCaptionsProduct.commercialLicenseMailURL.absoluteString.contains("commercial%20license"))
        XCTAssertTrue(ConnectingCaptionsProduct.workNotice.contains("$240"))
        XCTAssertTrue(ConnectingCaptionsProduct.workNotice.contains("$49"))
        XCTAssertEqual(ConnectingCaptionsProduct.personalLicensePriceLine, "$49 once")
        XCTAssertEqual(ConnectingCaptionsProduct.personalLaunchPriceLine, "$29 once")
        XCTAssertEqual(ConnectingCaptionsProduct.personalPurchaseURL.absoluteString, "https://local-host.ai/connectingCaptions/pricing/")
        XCTAssertEqual(ConnectingCaptionsProduct.personalMacs, 2)
        XCTAssertEqual(ConnectingCaptionsProduct.listenTrialDays, 14)
        XCTAssertEqual(ConnectingCaptionsProduct.commercialSeatMinimum, 5)
        XCTAssertTrue(ConnectingCaptionsProduct.commercialLicenseMailURL.absoluteString.contains("Mac%20count"))
    }

    func testPersonalKeyUnlocksTwoMacsAndHidesTheOrganization() throws {
        let issued = try XCTUnwrap(CommercialLicense.day(from: "2026-10-24"))
        let expires = try XCTUnwrap(CommercialLicense.day(from: "2099-12-31"))
        let record = CommercialLicense.Record(
            product: CommercialLicense.productID,
            org: "ada@example.com",
            seats: 2,
            issued: issued,
            expires: expires,
            personal: true,
            updatesThroughMajor: 1
        )
        let token = try CommercialLicense.makeToken(record: record, privateKey: self.privateKey)
        let verified = try CommercialLicense.verify(token, publicKey: self.privateKey.publicKey, appVersion: "1.6.16").get()

        XCTAssertTrue(verified.personal)
        XCTAssertEqual(verified.seats, 2)
        XCTAssertEqual(verified.updatesThroughMajor, 1)
        XCTAssertEqual(verified.coverageTitle, "Personal license")
        XCTAssertFalse(verified.coverageTitle.contains("ada@example.com"))

        let settings = SettingsStore.shared
        XCTAssertEqual(try settings.activateCommercialLicense(token).get().org, "ada@example.com")
        XCTAssertTrue(settings.isCommerciallyLicensed)
        let ended = try XCTUnwrap(CommercialLicense.day(from: "2026-11-08"))
        XCTAssertNil(settings.blockListenStart(now: ended))
    }

    func testPersonalKeyRejectsExtraSeatsAndAnSLA() throws {
        let issued = try XCTUnwrap(CommercialLicense.day(from: "2026-10-24"))
        let expires = try XCTUnwrap(CommercialLicense.day(from: "2036-10-24"))
        let tooMany = CommercialLicense.Record(
            product: CommercialLicense.productID,
            org: "ada@example.com",
            seats: 3,
            issued: issued,
            expires: expires,
            personal: true
        )
        let sla = CommercialLicense.Record(
            product: CommercialLicense.productID,
            org: "ada@example.com",
            seats: 2,
            issued: issued,
            expires: expires,
            sla: true,
            personal: true
        )
        let tooManyToken = try CommercialLicense.makeToken(record: tooMany, privateKey: self.privateKey)
        let slaToken = try CommercialLicense.makeToken(record: sla, privateKey: self.privateKey)

        XCTAssertEqual(
            CommercialLicense.verify(tooManyToken, publicKey: self.privateKey.publicKey),
            .failure(.invalidRecord)
        )
        XCTAssertEqual(
            CommercialLicense.verify(slaToken, publicKey: self.privateKey.publicKey),
            .failure(.invalidRecord)
        )
        XCTAssertEqual(
            CommercialLicense.verify(slaToken, publicKey: self.privateKey.publicKey, appVersion: "2.0"),
            .failure(.invalidRecord)
        )
    }

    func testPersonalKeyStopsAtTheNextMajorVersion() throws {
        let issued = try XCTUnwrap(CommercialLicense.day(from: "2026-10-24"))
        let expires = try XCTUnwrap(CommercialLicense.day(from: "2099-12-31"))
        let record = CommercialLicense.Record(
            product: CommercialLicense.productID,
            org: "ada@example.com",
            seats: 2,
            issued: issued,
            expires: expires,
            personal: true,
            updatesThroughMajor: 1
        )
        let token = try CommercialLicense.makeToken(record: record, privateKey: self.privateKey)

        XCTAssertEqual(
            CommercialLicense.verify(token, publicKey: self.privateKey.publicKey, appVersion: "2.0"),
            .failure(.outsideVersion(1))
        )
        XCTAssertNoThrow(try CommercialLicense.verify(token, publicKey: self.privateKey.publicKey, appVersion: "1.9").get())
    }

    func testTrialLastsFourteenUTCDaysThenBlocksListen() throws {
        let start = try XCTUnwrap(CommercialLicense.day(from: "2026-10-01"))
        let lastDay = try XCTUnwrap(CommercialLicense.day(from: "2026-10-14"))
        let nextDay = try XCTUnwrap(CommercialLicense.day(from: "2026-10-15"))

        XCTAssertEqual(ListenAccess.phase(startedOn: nil, now: start), .notStarted)
        XCTAssertEqual(ListenAccess.phase(startedOn: start, now: start), .inTrial(daysRemaining: 14))
        XCTAssertEqual(ListenAccess.phase(startedOn: start, now: lastDay), .inTrial(daysRemaining: 1))
        XCTAssertEqual(ListenAccess.phase(startedOn: start, now: nextDay), .ended)

        let settings = SettingsStore.shared
        XCTAssertNil(settings.blockListenStart(now: start))
        XCTAssertEqual(settings.listenTrialStartedOn, start)
        XCTAssertNil(settings.blockListenStart(now: lastDay))
        XCTAssertEqual(settings.blockListenStart(now: nextDay), ListenAccess.trialEndedMessage)
    }

    private func makeRecord(
        product: String = CommercialLicense.productID,
        org: String = "Example LLP"
    ) throws -> CommercialLicense.Record {
        CommercialLicense.Record(
            product: product,
            org: org,
            seats: 25,
            issued: try XCTUnwrap(CommercialLicense.day(from: "2026-09-21")),
            expires: try XCTUnwrap(CommercialLicense.day(from: "2027-09-21"))
        )
    }
}
