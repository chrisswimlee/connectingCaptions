//
//  SimpleUpdaterSignatureTests.swift
//  Fluid
//
//  Update zip signature, team, and checksum policy.
//

import XCTest
@testable import ConnectingCaptions_Debug

final class SimpleUpdaterSignatureTests: XCTestCase {
    func testRejectsEmptyAdHocAndUnsetTeamIDs() {
        XCTAssertFalse(UpdateSignaturePolicy.isUsableTeamID(nil))
        XCTAssertFalse(UpdateSignaturePolicy.isUsableTeamID(""))
        XCTAssertFalse(UpdateSignaturePolicy.isUsableTeamID("not set"))
        XCTAssertFalse(UpdateSignaturePolicy.isUsableTeamID("NOT SET"))
        XCTAssertFalse(UpdateSignaturePolicy.isUsableTeamID("-"))
        XCTAssertFalse(UpdateSignaturePolicy.isUsableTeamID("adhoc"))
        XCTAssertFalse(UpdateSignaturePolicy.isUsableTeamID("ABCDEFGHI"))
        XCTAssertTrue(UpdateSignaturePolicy.isUsableTeamID("ABCD123456"))
    }

    func testPublicUpdatesStayOffForEmptyAllowlistAndAdHocTeams() {
        XCTAssertFalse(
            UpdateSignaturePolicy.canInstallPublicUpdates(currentTeam: nil, allowed: [])
        )
        XCTAssertFalse(
            UpdateSignaturePolicy.canInstallPublicUpdates(currentTeam: "adhoc", allowed: [])
        )
        XCTAssertTrue(
            UpdateSignaturePolicy.canInstallPublicUpdates(
                currentTeam: "ABCD123456",
                allowed: []
            )
        )
        XCTAssertFalse(
            UpdateSignaturePolicy.canInstallPublicUpdates(
                currentTeam: nil,
                allowed: ["ABCD123456"]
            )
        )
        XCTAssertFalse(
            UpdateSignaturePolicy.canInstallPublicUpdates(
                currentTeam: "ABCD123456",
                allowed: ["C6BH3WS28B"]
            )
        )
        XCTAssertTrue(
            UpdateSignaturePolicy.canInstallPublicUpdates(
                currentTeam: "C6BH3WS28B",
                allowed: ["C6BH3WS28B"]
            )
        )
    }

    func testRejectsTeamMismatchAndAllowsSameOrAllowlistedTeams() {
        let allowed: Set<String> = ["ABCD123456", "EFGH789012"]
        XCTAssertTrue(
            UpdateSignaturePolicy.accepts(
                currentTeam: "ABCD123456",
                newTeam: "ABCD123456",
                allowed: allowed,
                bundleIdentifier: ConnectingCaptionsProduct.bundleIdentifier
            )
        )
        XCTAssertTrue(
            UpdateSignaturePolicy.accepts(
                currentTeam: "ABCD123456",
                newTeam: "EFGH789012",
                allowed: allowed,
                bundleIdentifier: ConnectingCaptionsProduct.bundleIdentifier
            )
        )
        XCTAssertFalse(
            UpdateSignaturePolicy.accepts(
                currentTeam: "ABCD123456",
                newTeam: "ZZZZ999999",
                allowed: allowed,
                bundleIdentifier: ConnectingCaptionsProduct.bundleIdentifier
            )
        )
        XCTAssertFalse(
            UpdateSignaturePolicy.accepts(
                currentTeam: "ABCD123456",
                newTeam: "not set",
                allowed: allowed,
                bundleIdentifier: ConnectingCaptionsProduct.bundleIdentifier
            )
        )
        XCTAssertFalse(
            UpdateSignaturePolicy.accepts(
                currentTeam: nil,
                newTeam: "ABCD123456",
                allowed: [],
                bundleIdentifier: ConnectingCaptionsProduct.bundleIdentifier
            )
        )
        XCTAssertFalse(
            UpdateSignaturePolicy.accepts(
                currentTeam: "ABCD123456",
                newTeam: "ABCD123456",
                allowed: allowed,
                bundleIdentifier: "com.example.other"
            )
        )
    }

    func testParsesCodesignTeamAndRejectsZipSlip() {
        let output = """
        Executable=/tmp/Connecting Captions.app/Contents/MacOS/Connecting Captions
        Identifier=com.connectingcaptions.app
        Format=app bundle with Mach-O thin (arm64)
        TeamIdentifier=ABCD123456
        designated => identifier "com.connectingcaptions.app" and certificate leaf[subject.OU] = ABCD123456
        """
        XCTAssertEqual(UpdateSignaturePolicy.teamID(fromCodesignOutput: output), "ABCD123456")
        XCTAssertEqual(
            UpdateSignaturePolicy.bundleIdentifier(fromCodesignOutput: output),
            "com.connectingcaptions.app"
        )
        XCTAssertTrue(
            UpdateSignaturePolicy.designatedRequirement(fromCodesignOutput: output)?
                .contains("com.connectingcaptions.app") == true
        )

        let work = URL(fileURLWithPath: "/tmp/update-extract")
        XCTAssertTrue(
            UpdateSignaturePolicy.isSafeExtractedApp(
                work.appendingPathComponent("Connecting Captions.app"),
                workDirectory: work
            )
        )
        XCTAssertFalse(
            UpdateSignaturePolicy.isSafeExtractedApp(
                URL(fileURLWithPath: "/tmp/evil.app"),
                workDirectory: work
            )
        )
    }

    func testChecksumLookupAndSHA256() throws {
        let sums = """
        # comment
        abcdef0123456789  Connecting-Captions-1.6.10.zip
        fedcba9876543210  connectingcaptions-1.6.10.zip
        deadbeefdeadbeef *other.zip
        """
        XCTAssertEqual(
            UpdateSignaturePolicy.expectedSHA256(
                fromChecksumFile: sums,
                assetName: "Connecting-Captions-1.6.10.zip"
            ),
            "abcdef0123456789"
        )
        XCTAssertEqual(
            UpdateSignaturePolicy.expectedSHA256(
                fromChecksumFile: sums,
                assetName: "connectingcaptions-1.6.10.zip"
            ),
            "fedcba9876543210"
        )
        XCTAssertNil(
            UpdateSignaturePolicy.expectedSHA256(fromChecksumFile: sums, assetName: "missing.zip")
        )
        let digest = UpdateSignaturePolicy.hexSHA256(of: Data("connectingCaptions".utf8))
        XCTAssertEqual(digest.count, 64)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("sha256-\(UUID().uuidString).bin")
        try Data("connectingCaptions".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertEqual(try UpdateSignaturePolicy.hexSHA256(ofFile: url), digest)
    }

    func testPrefersTheVersionedConnectingCaptionsZip() {
        let names = [
            "Connecting-Captions.zip",
            "fluidsubtitles-1.6.14.zip",
            "Connecting-Captions-1.6.14.zip",
            "SHA256SUMS",
        ]
        XCTAssertEqual(
            UpdateAssetSelection.preferredZipName(in: names, version: "1.6.14", repo: "connectingCaptions"),
            "Connecting-Captions-1.6.14.zip"
        )
        XCTAssertEqual(
            UpdateAssetSelection.preferredZipName(
                in: ["connectingcaptions-1.6.14.zip"],
                version: "1.6.14",
                repo: "connectingCaptions"
            ),
            "connectingcaptions-1.6.14.zip"
        )
        XCTAssertNil(
            UpdateAssetSelection.preferredZipName(
                in: ["fluidsubtitles-1.6.14.zip", "Connecting-Captions.zip"],
                version: "1.6.14",
                repo: "connectingCaptions"
            )
        )
    }

    func testLegacyBundleInstallsEvenWhenTheVersionMatches() {
        XCTAssertTrue(
            UpdateAssetSelection.installsDespiteSameVersion(
                runningBundleIdentifier: "com.fluidsubtitles.app"
            )
        )
        XCTAssertFalse(
            UpdateAssetSelection.installsDespiteSameVersion(
                runningBundleIdentifier: ConnectingCaptionsProduct.bundleIdentifier
            )
        )
        XCTAssertFalse(
            UpdateAssetSelection.installsDespiteSameVersion(runningBundleIdentifier: nil)
        )
    }
}
