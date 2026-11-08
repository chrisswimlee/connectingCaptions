import XCTest
@testable import ConnectingCaptions_Debug

final class TranscriptEncryptionTests: XCTestCase {
    private let key = Data(repeating: 0x3C, count: 32)

    override func tearDown() {
        HistoryKeySource.forceUnavailable = false
        HistoryKeySource.testingKey = nil
        HistorySQLCipher.testingAvailableBytes = nil
        super.tearDown()
    }

    func testKeyedOpenKeepsFullTextSearch() throws {
        let url = self.temporaryDatabase()
        defer { self.removeDatabase(url) }
        let match = self.entry(text: "unique caption zebra")
        try self.write(match, to: url, key: nil)
        let sealed = try TranscriptionHistoryDatabase(url: url, key: self.key)
        let page = try sealed.readPage(limit: 10, query: "zebra")
        XCTAssertEqual(page.map(\.id), [match.id])
        let header = try Data(contentsOf: url).prefix(16)
        XCTAssertNotEqual(header, Data("SQLite format 3\0".utf8))
    }

    func testInterruptedMigrationRestoresThePlaintextCopy() throws {
        let url = self.temporaryDatabase()
        defer { self.removeDatabase(url) }
        try self.write(self.entry(text: "kept through a crash"), to: url, key: nil)
        let backup = URL(fileURLWithPath: url.path + ".plaintext-copy")
        try FileManager.default.copyItem(at: url, to: backup)
        try FileManager.default.removeItem(at: url)

        let restored = try TranscriptionHistoryDatabase(url: url, key: self.key)
        XCTAssertEqual(try restored.read().count, 1)
        let header = try Data(contentsOf: url).prefix(16)
        XCTAssertNotEqual(header, Data("SQLite format 3\0".utf8))
        XCTAssertFalse(FileManager.default.fileExists(atPath: backup.path))
    }

    func testMigrationStopsWhenDiskSpaceIsShortAndLeavesThePlaintextFile() throws {
        let url = self.temporaryDatabase()
        defer { self.removeDatabase(url) }
        try self.write(self.entry(text: "keep this row"), to: url, key: nil)
        let before = try Data(contentsOf: url).prefix(16)
        HistorySQLCipher.testingAvailableBytes = 1
        XCTAssertThrowsError(try TranscriptionHistoryDatabase(url: url, key: self.key)) { error in
            XCTAssertEqual(
                (error as? HistoryCipherError),
                .notEnoughDiskSpace
            )
        }
        XCTAssertEqual(try Data(contentsOf: url).prefix(16), before)
        let reopened = try TranscriptionHistoryDatabase(url: url)
        XCTAssertEqual(try reopened.read().count, 1)
    }

    func testUnavailableKeyNeverWritesAndTheNextOpenRetries() async throws {
        let url = self.temporaryDatabase()
        defer { self.removeDatabase(url) }
        let marker = Data("do-not-touch".utf8)
        try marker.write(to: url, options: .atomic)
        HistoryKeySource.forceUnavailable = true
        let defaults = UserDefaults(suiteName: "history-key-\(UUID().uuidString)")!
        let writer = TranscriptionHistoryWriter(defaults: defaults, url: url)
        do {
            _ = try await writer.load()
            XCTFail("A missing key must not open history")
        } catch {
            XCTAssertEqual(error.localizedDescription, "History is locked on this Mac.")
        }
        XCTAssertEqual(try Data(contentsOf: url), marker)

        try FileManager.default.removeItem(at: url)
        HistoryKeySource.forceUnavailable = false
        HistoryKeySource.testingKey = self.key
        let loaded = try await writer.load()
        XCTAssertTrue(loaded.isEmpty)
        let header = try Data(contentsOf: url).prefix(16)
        XCTAssertNotEqual(header, Data("SQLite format 3\0".utf8))
    }

    func testBothAudioPathsSealAndExportDecrypts() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("sealed-audio-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = DictationAudioHistoryStore(audioDirectory: directory, key: self.key)

        let saved = try store.save(
            snapshot: DictationAudioSnapshot(samples: [0.25, -0.25], sampleRate: 16_000, channels: 1),
            entryID: UUID(),
            timestamp: Date(),
            model: "test"
        )
        let savedURL = directory.appendingPathComponent(saved.fileName)
        XCTAssertTrue(SealedAudioFile.isSealed(at: savedURL))
        XCTAssertEqual(try SealedAudioFile.plaintext(at: savedURL, key: self.key).prefix(4), Data("RIFF".utf8))

        let streaming = try store.beginStreamingWrite(entryID: UUID(), timestamp: Date())
        streaming.append([0.5, -0.5])
        let streamed = try streaming.finish(model: "test")
        let streamedURL = directory.appendingPathComponent(streamed.fileName)
        XCTAssertTrue(SealedAudioFile.isSealed(at: streamedURL))

        let legacyURL = directory.appendingPathComponent("legacy.wav")
        try Data("RIFF".utf8).write(to: legacyURL)
        store.sealLegacyFiles()
        XCTAssertTrue(SealedAudioFile.isSealed(at: legacyURL))

        let entry = TranscriptionHistoryEntry(
            timestamp: Date(),
            rawText: "heard",
            processedText: "heard",
            appName: "Test",
            windowTitle: "Test",
            wasAIProcessed: false,
            audio: saved
        )
        let zip = directory.appendingPathComponent("export.zip")
        try await store.exportPair(entry: entry, to: zip)
        let unpacked = directory.appendingPathComponent("unpacked", isDirectory: true)
        try FileManager.default.createDirectory(at: unpacked, withIntermediateDirectories: true)
        let unzip = Process()
        unzip.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        unzip.arguments = ["-q", zip.path, "-d", unpacked.path]
        try unzip.run()
        unzip.waitUntilExit()
        XCTAssertEqual(unzip.terminationStatus, 0)
        let wavs = try FileManager.default.subpathsOfDirectory(atPath: unpacked.path).filter { $0.hasSuffix(".wav") }
        let exported = try XCTUnwrap(wavs.first)
        let bytes = try Data(contentsOf: unpacked.appendingPathComponent(exported))
        XCTAssertEqual(bytes.prefix(4), Data("RIFF".utf8))
    }

    private func temporaryDatabase() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("history-seal-\(UUID().uuidString).sqlite3")
    }

    private func removeDatabase(_ url: URL) {
        let fileManager = FileManager.default
        for suffix in ["", "-wal", "-shm", ".sealed", ".plaintext-copy", "-wal.plaintext-copy", "-shm.plaintext-copy"] {
            let path = url.path + suffix
            guard fileManager.fileExists(atPath: path) else { continue }
            do {
                try fileManager.removeItem(atPath: path)
            } catch {
                continue
            }
        }
    }

    private func entry(text: String) -> TranscriptionHistoryEntry {
        TranscriptionHistoryEntry(
            timestamp: Date(),
            rawText: text,
            processedText: text,
            appName: "Test",
            windowTitle: "Test",
            wasAIProcessed: false
        )
    }

    private func write(_ entry: TranscriptionHistoryEntry, to url: URL, key: Data?) throws {
        let database = try TranscriptionHistoryDatabase(url: url, key: key)
        let record = try TranscriptionHistoryDatabase.Record(id: entry.id, payload: JSONEncoder().encode(entry))
        try database.write(upserts: [record], deletes: [], replacing: true)
    }
}
