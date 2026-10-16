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

    func testParsesCodesignTeamAndRejectsZipSlip() throws {
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

        let work = FileManager.default.temporaryDirectory.appendingPathComponent("update-extract-\(UUID())")
        try FileManager.default.createDirectory(
            at: work.appendingPathComponent("Connecting Captions.app"), withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: work) }
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

    func testRejectsExternalAppSymlinkAndNonDirectory() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("update-link-\(UUID())")
        let work = root.appendingPathComponent("extract")
        let target = root.appendingPathComponent("outside.app")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let app = work.appendingPathComponent("Connecting Captions.app")
        try FileManager.default.createSymbolicLink(at: app, withDestinationURL: target)
        XCTAssertFalse(UpdateSignaturePolicy.isSafeExtractedApp(app, workDirectory: work))
        XCTAssertNil(UpdateSignaturePolicy.selectSoleTopLevelApp(in: work))
        try FileManager.default.removeItem(at: app)
        try Data().write(to: app)
        XCTAssertFalse(UpdateSignaturePolicy.isSafeExtractedApp(app, workDirectory: work))
        XCTAssertNil(UpdateSignaturePolicy.selectSoleTopLevelApp(in: work))
        try FileManager.default.removeItem(at: app)
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
        XCTAssertEqual(
            UpdateSignaturePolicy.selectSoleTopLevelApp(in: work)?.resolvingSymlinksInPath().path,
            app.resolvingSymlinksInPath().path
        )
    }

    func testRollbackPreservesInstalledAppPathWhileUpdatesCanRename() {
        let installed = URL(fileURLWithPath: "/Applications/Connecting Captions.app")
        let backup = URL(fileURLWithPath: "/tmp/Connecting Captions-1.6.10-123456.app")
        XCTAssertEqual(
            SimpleUpdater.installationDestination(installedAppURL: installed, downloadedAppURL: backup, isRollback: true),
            installed
        )
        XCTAssertEqual(
            SimpleUpdater.installationDestination(installedAppURL: installed, downloadedAppURL: backup, isRollback: false),
            installed.deletingLastPathComponent().appendingPathComponent(backup.lastPathComponent)
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

final class AppBundleReplacementTests: XCTestCase {
    private func fixture() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        self.addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return root
    }

    private func app(_ root: URL, _ name: String, contents: String) throws -> URL {
        let url = root.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try Data(contents.utf8).write(to: url.appendingPathComponent("marker"))
        return url
    }

    private func contents(_ app: URL) throws -> String {
        try String(contentsOf: app.appendingPathComponent("marker"), encoding: .utf8)
    }

    func testMissingCandidateLeavesInstalledAppUntouched() throws {
        let root = try self.fixture()
        let installed = try self.app(root, "Installed.app", contents: "old")
        XCTAssertThrowsError(try AppBundleReplacement.begin(installed: installed,
                                                           candidate: root.appendingPathComponent("missing.app"), destination: installed))
        XCTAssertEqual(try self.contents(installed), "old")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), ["Installed.app"])
    }

    func testFailedCandidateMoveRestoresInstalledApp() throws {
        let root = try self.fixture()
        let installed = try self.app(root, "Installed.app", contents: "old")
        let candidate = try self.app(root, "Candidate.app", contents: "new")
        var moves = 0
        XCTAssertThrowsError(try AppBundleReplacement.begin(installed: installed, candidate: candidate, destination: installed) { from, to in
            moves += 1
            if moves == 2 { throw CocoaError(.fileWriteNoPermission) }
            try FileManager.default.moveItem(at: from, to: to)
        })
        XCTAssertEqual(try self.contents(installed), "old")
        XCTAssertEqual(try self.contents(candidate), "new")
    }

    func testFailureReportedAfterMovingOriginalStillRestoresIt() throws {
        let root = try self.fixture()
        let installed = try self.app(root, "Installed.app", contents: "old")
        let candidate = try self.app(root, "Candidate.app", contents: "new")
        var moves = 0
        XCTAssertThrowsError(try AppBundleReplacement.begin(installed: installed, candidate: candidate, destination: installed) { from, to in
            moves += 1
            try FileManager.default.moveItem(at: from, to: to)
            if moves == 1 { throw CocoaError(.fileWriteUnknown) }
        })
        XCTAssertEqual(try self.contents(installed), "old")
    }

    func testFailedRenameRestoresBothDisplacedApps() throws {
        let root = try self.fixture()
        let installed = try self.app(root, "Installed.app", contents: "old")
        let candidate = try self.app(root, "Candidate.app", contents: "new")
        let destination = try self.app(root, "Renamed.app", contents: "collision")
        var moves = 0
        XCTAssertThrowsError(try AppBundleReplacement.begin(installed: installed, candidate: candidate, destination: destination) { from, to in
            moves += 1
            if moves == 3 { throw CocoaError(.fileWriteNoPermission) }
            try FileManager.default.moveItem(at: from, to: to)
        })
        XCTAssertEqual(try self.contents(installed), "old")
        XCTAssertEqual(try self.contents(destination), "collision")
    }

    func testRelaunchFailureCanRestoreTheOldBundle() throws {
        let root = try self.fixture()
        let installed = try self.app(root, "Installed.app", contents: "old")
        let candidate = try self.app(root, "Candidate.app", contents: "new")
        let transaction = try AppBundleReplacement.begin(installed: installed, candidate: candidate, destination: installed)
        XCTAssertEqual(try self.contents(installed), "new")
        XCTAssertTrue(FileManager.default.fileExists(atPath: transaction.directory.path))
        try transaction.rollback()
        XCTAssertEqual(try self.contents(installed), "old")
        XCTAssertEqual(try self.contents(candidate), "new")
        XCTAssertFalse(FileManager.default.fileExists(atPath: transaction.directory.path))
    }

    func testSuccessfulReplacementRetainsCandidateAndCommitsRecoveryFiles() throws {
        let root = try self.fixture()
        let installed = try self.app(root, "Installed.app", contents: "old")
        let candidate = try self.app(root, "Candidate.app", contents: "new")
        let transaction = try AppBundleReplacement.begin(installed: installed, candidate: candidate, destination: installed)
        transaction.commit()
        XCTAssertEqual(try self.contents(installed), "new")
        XCTAssertEqual(try self.contents(candidate), "new")
        XCTAssertFalse(FileManager.default.fileExists(atPath: transaction.directory.path))
    }

    func testRecoveryFailureRetainsOriginalBundleAndReportsItsLocation() throws {
        let root = try self.fixture()
        let installed = try self.app(root, "Installed.app", contents: "old")
        let candidate = try self.app(root, "Candidate.app", contents: "new")
        var moves = 0
        do {
            _ = try AppBundleReplacement.begin(installed: installed, candidate: candidate, destination: installed) { from, to in
                moves += 1
                if moves > 1 { throw CocoaError(.fileWriteNoPermission) }
                try FileManager.default.moveItem(at: from, to: to)
            }
            XCTFail("Expected recovery failure")
        } catch let error as AppBundleReplacement.RecoveryRequired {
            XCTAssertEqual(try self.contents(error.directory.appendingPathComponent("Previous-0.app")), "old")
            XCTAssertTrue(error.localizedDescription.contains(error.directory.path))
        }
    }

    func testPruningProtectsSelectedRollbackBehindThreeNewerBackups() throws {
        let root = try self.fixture()
        let backups = try (0..<5).map { try self.app(root, "Backup-\($0).app", contents: "version-\($0)") }
        let selected = backups[3]
        let removals = SimpleUpdater.rollbackBackupsToRemove(backups, limit: 3, protecting: selected)
        XCTAssertEqual(removals, [backups[4]])
        for url in removals { try FileManager.default.removeItem(at: url) }
        XCTAssertEqual(try self.contents(selected), "version-3")
        let installed = try self.app(root, "Installed.app", contents: "current")
        let transaction = try AppBundleReplacement.begin(installed: installed, candidate: selected, destination: installed)
        transaction.commit()
        XCTAssertEqual(try self.contents(installed), "version-3")
    }
}

final class DiagnosticPrivacyTests: XCTestCase {
    func testStreamingProviderDiagnosticsDoNotWriteResponseDeltas() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent("Sources/ConnectingCaptions/Services/LLMClient.swift"), encoding: .utf8)
        for raw in [#"\(rawDelta)"#, #"\(escaped)"#, #"\(errorBody)"#] {
            XCTAssertFalse(source.contains(raw), "Provider diagnostics can echo user speech")
        }
        XCTAssertTrue(source.contains("Delta bytes:"))
        XCTAssertTrue(source.contains("Chunk characters:"))
    }

    func testPromptAndProviderErrorMetadataCannotContainUserContent() {
        let sentinel = "PRIVATE SPEECH SENTINEL 80217"
        let error = LLMError.httpError(400, sentinel)
        XCTAssertFalse(DiagnosticMetadata.error(error).contains(sentinel))
        XCTAssertFalse(DiagnosticMetadata.error(NSError(domain: "provider", code: 7,
                                                        userInfo: [NSLocalizedDescriptionKey: sentinel])).contains(sentinel))
        let trace = DiagnosticMetadata.promptTrace(title: "Input transcription (Q)", value: sentinel)
        XCTAssertFalse(trace.contains(sentinel))
        XCTAssertTrue(trace.contains("characters=\(sentinel.count)"))
    }

    func testClearingLogsRemovesCurrentRotatedAndLegacyContentOnly() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let names = ["connectingCaptions.log", "connectingCaptions.log.1", "fluid.log", "fluid.log.1"]
        for name in names { try Data("private speech sentinel".utf8).write(to: root.appendingPathComponent(name)) }
        try Data("keep".utf8).write(to: root.appendingPathComponent("unrelated.txt"))
        try FileLogger.removeDiagnosticFiles(in: root)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), ["unrelated.txt"])
        try FileLogger.removeDiagnosticFiles(in: root) // Clearing twice is harmless.
    }

    func testSpeechAndTypingDiagnosticsDoNotInterpolateTranscriptContent() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let files = ["AppleSpeechProvider.swift", "AppleSpeechAnalyzerProvider.swift", "ASRService+Stop.swift", "TypingService.swift"]
        let rawInterpolations = [#"\(text)"#, #"\(finalText)"#, #"\(transcription)"#, #"\(outputText)"#,
                                 #"\(text.prefix("#, #"\(String(text.prefix("#]
        for file in files {
            let source = try String(contentsOf: root.appendingPathComponent("Sources/ConnectingCaptions/Services/\(file)"), encoding: .utf8)
            let logLines = source.split(separator: "\n").filter { $0.contains("DebugLogger.") || $0.contains("self.log(") }
            for line in logLines {
                XCTAssertFalse(rawInterpolations.contains { line.contains($0) }, "Transcript diagnostic in \(file): \(line)")
            }
        }
    }
}
