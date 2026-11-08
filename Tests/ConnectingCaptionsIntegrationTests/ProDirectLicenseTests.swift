import ConnectingCaptionsCore
import CryptoKit
import XCTest

final class ProDirectLicenseTests: XCTestCase {
    private var privateKey: Curve25519.Signing.PrivateKey!

    override func setUp() {
        super.setUp()
        self.privateKey = Curve25519.Signing.PrivateKey()
    }

    func testSignedPersonalKeyUnlocks() throws {
        let token = try ProDirectLicense.makeToken(
            wire: ProDirectLicense.Wire(
                org: "buyer@example.com",
                seats: 2,
                issued: "2026-10-01",
                expires: "2027-10-01",
                personal: true,
                major: 1
            ),
            privateKey: self.privateKey
        )
        let record = try self.verify(token, on: "2026-10-30", version: "1.0.0").get()
        XCTAssertTrue(record.personal)
        XCTAssertEqual(record.coverageTitle, "Personal license")
    }

    func testBadSignatureFailsClosed() throws {
        var token = try ProDirectLicense.makeToken(
            wire: ProDirectLicense.Wire(
                org: "buyer@example.com",
                seats: 1,
                issued: "2026-10-01",
                expires: "2027-10-01",
                personal: true,
                major: 1
            ),
            privateKey: self.privateKey
        )
        token.append("x")
        XCTAssertEqual(self.verify(token, on: "2026-10-30", version: "1.0.0"), .failure(.badSignature))
    }

    func testSeatListDoesNotUnlockThePhone() throws {
        let token = try ProDirectLicense.makeToken(
            wire: ProDirectLicense.Wire(
                org: "Example LLP",
                seats: 5,
                issued: "2026-10-01",
                expires: "2027-10-01",
                enforceSeats: true
            ),
            privateKey: self.privateKey
        )
        XCTAssertEqual(self.verify(token, on: "2026-10-30", version: "1.0.0"), .failure(.seatList))
    }

    func testPersonalKeyStopsAtTheNextMajorVersion() throws {
        let token = try ProDirectLicense.makeToken(
            wire: ProDirectLicense.Wire(
                org: "buyer@example.com",
                seats: 1,
                issued: "2026-10-01",
                expires: "2027-10-01",
                personal: true,
                major: 1
            ),
            privateKey: self.privateKey
        )
        XCTAssertEqual(
            self.verify(token, on: "2026-10-30", version: "2.0.0"),
            .failure(.outsideVersion(1))
        )
    }

    func testFreeDownloadDoesNotBlockListen() {
        XCTAssertFalse(ConnectingCaptionsProduct.directDownloadAsksForKey)
        XCTAssertFalse(
            ProListenTrial.blocksListen(hasLicense: false, phase: .ended, asksForKey: false)
        )
        XCTAssertFalse(
            ProListenTrial.blocksListen(hasLicense: false, phase: .unreadable, asksForKey: false)
        )
        XCTAssertTrue(
            ProListenTrial.blocksListen(hasLicense: false, phase: .ended, asksForKey: true)
        )
        XCTAssertFalse(
            ProListenTrial.blocksListen(hasLicense: true, phase: .ended, asksForKey: true)
        )
        XCTAssertFalse(
            ProListenTrial.blocksListen(hasLicense: false, phase: .inTrial(day: 1), asksForKey: true)
        )
    }

    func testTrialLastsFourteenUTCDays() {
        let start = "2026-10-01"
        XCTAssertEqual(
            ProListenTrial.phase(startedOn: start, highWater: start, now: self.date("2026-10-01")),
            .inTrial(day: 1)
        )
        XCTAssertEqual(
            ProListenTrial.phase(startedOn: start, highWater: "2026-10-14", now: self.date("2026-10-14")),
            .inTrial(day: 14)
        )
        XCTAssertEqual(
            ProListenTrial.phase(startedOn: start, highWater: "2026-10-15", now: self.date("2026-10-15")),
            .ended
        )
    }

    func testClockRollbackDoesNotReopenTheTrial() {
        XCTAssertEqual(
            ProListenTrial.phase(startedOn: "2026-10-01", highWater: "2026-10-20", now: self.date("2026-10-02")),
            .ended
        )
    }

    private func verify(_ token: String, on day: String, version: String) -> Result<ProDirectLicense.Record, ProDirectLicense.Failure> {
        ProDirectLicense.verify(
            token,
            publicKey: self.privateKey.publicKey,
            now: self.date(day),
            appVersion: version
        )
    }

    private func date(_ day: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.date(from: day) ?? .distantFuture
    }
}
