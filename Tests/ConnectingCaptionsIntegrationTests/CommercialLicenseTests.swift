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
        SettingsStore.testingAppBundleCreation = nil
        EarlyInstallAccess.resetForTests()
    }

    override func tearDown() {
        SettingsStore.shared.removeCommercialLicense()
        SettingsStore.shared.clearListenTrial()
        SettingsStore.testingAppBundleCreation = nil
        EarlyInstallAccess.resetForTests()
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

    func testKeyBeforeItsStartDateIsNotCalledExpired() throws {
        let issued = try XCTUnwrap(CommercialLicense.day(from: "2026-12-01"))
        let expires = try XCTUnwrap(CommercialLicense.day(from: "2027-12-01"))
        let record = CommercialLicense.Record(
            product: CommercialLicense.productID,
            org: "Example LLP",
            seats: 5,
            issued: issued,
            expires: expires
        )
        let token = try CommercialLicense.makeToken(record: record, privateKey: self.privateKey)
        let now = try XCTUnwrap(CommercialLicense.day(from: "2026-11-01"))

        XCTAssertEqual(
            CommercialLicense.verify(token, publicKey: self.privateKey.publicKey, now: now),
            .failure(.notYetValid)
        )
        XCTAssertEqual(
            CommercialLicense.Failure.notYetValid.localizedDescription,
            "That key is not active yet."
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
        XCTAssertFalse(ListenAccess.releaseAsksForKey)
        XCTAssertNotNil(CommercialLicense.day(from: ConnectingCaptionsProduct.earlierCopyCutoffDay))
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

    func testReleaseDoesNotStartOrEndTheTrial() throws {
        let start = try XCTUnwrap(CommercialLicense.day(from: "2026-10-01"))
        let lastDay = try XCTUnwrap(CommercialLicense.day(from: "2026-10-14"))
        let nextDay = try XCTUnwrap(CommercialLicense.day(from: "2026-10-15"))

        XCTAssertEqual(ListenAccess.phase(startedOn: nil, now: start), .notStarted)
        XCTAssertEqual(ListenAccess.phase(startedOn: start, now: start), .inTrial(daysRemaining: 14))
        XCTAssertEqual(ListenAccess.phase(startedOn: start, now: lastDay), .inTrial(daysRemaining: 1))
        XCTAssertEqual(ListenAccess.phase(startedOn: start, now: nextDay), .ended)

        let settings = SettingsStore.shared
        XCTAssertNil(settings.blockListenStart(now: start))
        XCTAssertNil(settings.listenTrialStartedOn)
        XCTAssertNil(settings.blockListenStart(now: lastDay))
        XCTAssertNil(settings.blockListenStart(now: nextDay))
        XCTAssertNil(settings.listenTrialStartedOn)
    }

    func testTrialClockMovedBackwardDoesNotStartATrial() throws {
        let start = try XCTUnwrap(CommercialLicense.day(from: "2026-10-01"))
        let earlier = try XCTUnwrap(CommercialLicense.day(from: "2026-09-01"))
        let settings = SettingsStore.shared
        XCTAssertNil(settings.blockListenStart(now: start))
        XCTAssertNil(settings.blockListenStart(now: earlier))
        XCTAssertNil(settings.listenTrialStartedOn)
        XCTAssertEqual(ListenAccess.phase(startedOn: start, now: earlier), .ended)
    }

    func testTrialClockYearsAheadDoesNotBlockListen() throws {
        let installed = try XCTUnwrap(CommercialLicense.day(from: "2026-10-01"))
        let ahead = try XCTUnwrap(CommercialLicense.day(from: "2099-01-01"))
        SettingsStore.testingAppBundleCreation = installed
        let settings = SettingsStore.shared
        XCTAssertNil(settings.blockListenStart(now: ahead))
        XCTAssertNil(settings.listenTrialStartedOn)
        XCTAssertNil(ListenAccess.acceptedNow(ahead, appBirth: installed))
    }

    func testPersonalKeyRejectsAMacItDoesNotName() throws {
        let issued = try XCTUnwrap(CommercialLicense.day(from: "2026-10-24"))
        let expires = try XCTUnwrap(CommercialLicense.day(from: "2099-12-31"))
        var record = CommercialLicense.Record(
            product: CommercialLicense.productID,
            org: "ada@example.com",
            seats: 2,
            issued: issued,
            expires: expires,
            personal: true,
            updatesThroughMajor: 1
        )
        record.macs = ["AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"]
        let token = try CommercialLicense.makeToken(record: record, privateKey: self.privateKey)
        XCTAssertEqual(
            CommercialLicense.verify(
                token,
                publicKey: self.privateKey.publicKey,
                machineID: "FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF"
            ),
            .failure(.wrongMac)
        )
        XCTAssertNoThrow(
            try CommercialLicense.verify(
                token,
                publicKey: self.privateKey.publicKey,
                machineID: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"
            ).get()
        )
    }

    func testExpiredKeyDoesNotStartATrial() throws {
        let issued = try XCTUnwrap(CommercialLicense.day(from: "2026-01-01"))
        let expires = try XCTUnwrap(CommercialLicense.day(from: "2026-06-01"))
        let record = CommercialLicense.Record(
            product: CommercialLicense.productID,
            org: "ada@example.com",
            seats: 1,
            issued: issued,
            expires: expires,
            personal: true
        )
        let token = try CommercialLicense.makeToken(record: record, privateKey: self.privateKey)
        let settings = SettingsStore.shared
        XCTAssertEqual(try settings.activateCommercialLicense(token, now: issued).get().org, "ada@example.com")
        let later = try XCTUnwrap(CommercialLicense.day(from: "2026-08-01"))
        XCTAssertEqual(settings.blockListenStart(now: later), CommercialLicense.Failure.expired.localizedDescription)
        XCTAssertNil(settings.listenTrialStartedOn)
    }

    func testEarlierCopyKeepsListenAfterTheTrialWouldEnd() throws {
        let cutoff = try XCTUnwrap(CommercialLicense.day(from: ConnectingCaptionsProduct.earlierCopyCutoffDay))
        let home = try self.makeHome(createdAt: cutoff.addingTimeInterval(-86_400))
        EarlyInstallAccess.testingKey = SymmetricKey(size: .bits256)
        EarlyInstallAccess.testingHome = home
        EarlyInstallAccess.testingAppBirth = cutoff
        EarlyInstallAccess.testingFirstSignOn = cutoff.addingTimeInterval(-40 * 86_400)
        EarlyInstallAccess.testingLaunchedAt = cutoff

        let settings = SettingsStore.shared
        XCTAssertTrue(settings.keepsEarlierCopy)
        XCTAssertNil(settings.blockListenStart(now: cutoff.addingTimeInterval(40 * 86_400)))
        XCTAssertNil(settings.listenTrialStartedOn)
    }

    func testNewMacListensWithoutStartingATrialAfterAnOldFileAppears() throws {
        let cutoff = try XCTUnwrap(CommercialLicense.day(from: ConnectingCaptionsProduct.earlierCopyCutoffDay))
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("earlier-copy-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        EarlyInstallAccess.testingKey = SymmetricKey(size: .bits256)
        EarlyInstallAccess.testingHome = home
        EarlyInstallAccess.testingAppBirth = cutoff
        EarlyInstallAccess.testingFirstSignOn = cutoff.addingTimeInterval(-40 * 86_400)
        EarlyInstallAccess.testingLaunchedAt = cutoff
        EarlyInstallAccess.testingNow = cutoff.addingTimeInterval(25 * 60 * 60)

        let settings = SettingsStore.shared
        XCTAssertFalse(settings.keepsEarlierCopy)
        _ = try self.makeHome(createdAt: cutoff.addingTimeInterval(-86_400), root: home)
        EarlyInstallAccess.forgetCachedDecision()

        XCTAssertFalse(settings.keepsEarlierCopy)
        let start = try XCTUnwrap(CommercialLicense.day(from: "2026-10-01"))
        let ended = try XCTUnwrap(CommercialLicense.day(from: "2026-10-15"))
        XCTAssertNil(settings.blockListenStart(now: start))
        XCTAssertNil(settings.blockListenStart(now: ended))
        XCTAssertNil(settings.listenTrialStartedOn)
    }

    func testEarlierCopySealDoesNotOpenForAnotherMacOrATamperedBox() throws {
        let cutoff = try XCTUnwrap(CommercialLicense.day(from: ConnectingCaptionsProduct.earlierCopyCutoffDay))
        let key = SymmetricKey(size: .bits256)
        let old = cutoff.addingTimeInterval(-86_400)
        let granted = EarlyInstallAccess.decide(
            stored: [],
            birthDates: [old],
            cutoff: cutoff,
            key: key,
            machineID: "AAAA"
        )
        let sealed = try XCTUnwrap(granted.sealed)
        XCTAssertTrue(granted.allowed)

        let otherMac = EarlyInstallAccess.decide(
            stored: [sealed],
            birthDates: [old],
            cutoff: cutoff,
            key: key,
            machineID: "BBBB"
        )
        XCTAssertFalse(otherMac.allowed)
        XCTAssertNil(otherMac.sealed)

        var tampered = sealed
        tampered[tampered.count - 1] ^= 0xFF
        let broken = EarlyInstallAccess.decide(
            stored: [tampered],
            birthDates: [old],
            cutoff: cutoff,
            key: key,
            machineID: "AAAA"
        )
        XCTAssertFalse(broken.allowed)
        XCTAssertNil(broken.sealed)
        XCTAssertNil(EarlyInstallAccess.key(fromMixedHex: "abcd"))
    }

    func testAPaidInstallDoesNotCountAsAnEarlierCopy() throws {
        let cutoff = try XCTUnwrap(CommercialLicense.day(from: ConnectingCaptionsProduct.earlierCopyCutoffDay))
        let home = try self.makeHome(createdAt: cutoff.addingTimeInterval(-60))
        EarlyInstallAccess.testingKey = SymmetricKey(size: .bits256)
        EarlyInstallAccess.testingHome = home
        EarlyInstallAccess.testingAppBirth = cutoff.addingTimeInterval(-86_400)

        XCTAssertFalse(SettingsStore.shared.keepsEarlierCopy)
    }

    func testYoungInstallWaitsForARestoreBeforeSealingNo() throws {
        let cutoff = try XCTUnwrap(CommercialLicense.day(from: ConnectingCaptionsProduct.earlierCopyCutoffDay))
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("earlier-copy-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        EarlyInstallAccess.testingKey = SymmetricKey(size: .bits256)
        EarlyInstallAccess.testingHome = home
        EarlyInstallAccess.testingAppBirth = cutoff
        EarlyInstallAccess.testingFirstSignOn = cutoff.addingTimeInterval(-40 * 86_400)
        EarlyInstallAccess.testingLaunchedAt = cutoff.addingTimeInterval(60)
        EarlyInstallAccess.testingNow = cutoff

        XCTAssertFalse(SettingsStore.shared.keepsEarlierCopy)
        _ = try self.makeHome(createdAt: cutoff.addingTimeInterval(-86_400), root: home)
        EarlyInstallAccess.forgetCachedDecision()
        XCTAssertTrue(SettingsStore.shared.keepsEarlierCopy)
    }

    func testCopiedHomeOlderThanThisMacDoesNotKeepListen() throws {
        let cutoff = try XCTUnwrap(CommercialLicense.day(from: ConnectingCaptionsProduct.earlierCopyCutoffDay))
        let home = try self.makeHome(createdAt: cutoff.addingTimeInterval(-40 * 86_400))
        EarlyInstallAccess.testingKey = SymmetricKey(size: .bits256)
        EarlyInstallAccess.testingHome = home
        EarlyInstallAccess.testingAppBirth = cutoff
        EarlyInstallAccess.testingFirstSignOn = cutoff.addingTimeInterval(-86_400)
        EarlyInstallAccess.testingLaunchedAt = cutoff

        XCTAssertFalse(SettingsStore.shared.keepsEarlierCopy)
        EarlyInstallAccess.forgetCachedDecision()
        EarlyInstallAccess.testingFirstSignOn = cutoff.addingTimeInterval(-80 * 86_400)
        XCTAssertFalse(SettingsStore.shared.keepsEarlierCopy)
    }

    func testFileCreatedOnThisLaunchDoesNotKeepListen() throws {
        let cutoff = try XCTUnwrap(CommercialLicense.day(from: ConnectingCaptionsProduct.earlierCopyCutoffDay))
        let launchedAt = cutoff.addingTimeInterval(-86_400)
        let home = try self.makeHome(createdAt: launchedAt.addingTimeInterval(5))
        EarlyInstallAccess.testingKey = SymmetricKey(size: .bits256)
        EarlyInstallAccess.testingHome = home
        EarlyInstallAccess.testingAppBirth = cutoff
        EarlyInstallAccess.testingFirstSignOn = cutoff.addingTimeInterval(-40 * 86_400)
        EarlyInstallAccess.testingLaunchedAt = launchedAt

        XCTAssertFalse(SettingsStore.shared.keepsEarlierCopy)
    }

    func testEmptySupportFolderIsNotAnEarlierCopy() throws {
        let cutoff = try XCTUnwrap(CommercialLicense.day(from: ConnectingCaptionsProduct.earlierCopyCutoffDay))
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("earlier-copy-\(UUID().uuidString)", isDirectory: true)
        let folder = home.appendingPathComponent("Library/Application Support/connectingCaptions", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try FileManager.default.setAttributes(
            [.creationDate: cutoff.addingTimeInterval(-86_400)],
            ofItemAtPath: folder.path
        )

        XCTAssertTrue(EarlyInstallAccess.birthDates(in: home).isEmpty)
        XCTAssertFalse(
            EarlyInstallAccess.admits(
                birth: cutoff.addingTimeInterval(-86_400),
                cutoff: cutoff,
                firstSignOn: nil,
                appBirth: cutoff,
                launchedAt: cutoff
            )
        )
    }

    func testPolicyTimestampAcceptsUnixAndAbsoluteTime() {
        let unix = Date(timeIntervalSince1970: 1_767_484_800)
        let absolute = unix.timeIntervalSinceReferenceDate
        XCTAssertEqual(
            MacFirstSignOn.date(fromPolicyTimestamp: unix.timeIntervalSince1970),
            unix
        )
        XCTAssertEqual(
            MacFirstSignOn.date(fromPolicyTimestamp: absolute),
            unix
        )
        XCTAssertNil(MacFirstSignOn.date(fromPolicyTimestamp: 0))
    }

    func testThisMacSignOnPredatesNow() throws {
        let signOn = try XCTUnwrap(MacFirstSignOn.date())
        XCTAssertLessThan(signOn, Date().addingTimeInterval(60))
        let started = try XCTUnwrap(MacFirstSignOn.processStart())
        XCTAssertLessThanOrEqual(started.timeIntervalSince1970, Date().timeIntervalSince1970 + 1)
        XCTAssertGreaterThan(started, Date().addingTimeInterval(-86_400))
    }

    private func makeHome(createdAt: Date, root: URL? = nil) throws -> URL {
        let home = root ?? FileManager.default.temporaryDirectory
            .appendingPathComponent("earlier-copy-\(UUID().uuidString)", isDirectory: true)
        let prefs = home.appendingPathComponent("Library/Preferences", isDirectory: true)
        try FileManager.default.createDirectory(at: prefs, withIntermediateDirectories: true)
        let plist = prefs.appendingPathComponent("com.connectingcaptions.app.plist")
        try Data("bplist00".utf8).write(to: plist)
        try FileManager.default.setAttributes([.creationDate: createdAt], ofItemAtPath: plist.path)
        return home
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
