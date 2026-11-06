import Foundation
import SQLCipher

enum HistoryCipherError: LocalizedError, Equatable {
    case cipherUnavailable
    case notEnoughDiskSpace
    case migrationMismatch

    var errorDescription: String? {
        switch self {
        case .cipherUnavailable:
            return "History encryption is unavailable."
        case .notEnoughDiskSpace:
            return "Not enough free disk space to encrypt history."
        case .migrationMismatch:
            return "History could not be encrypted. The existing file was left unchanged."
        }
    }
}

enum HistorySQLCipher {
    nonisolated(unsafe) static var testingAvailableBytes: Int64?

    static func apply(key: Data, connection: OpaquePointer) throws {
        let pragma = "PRAGMA key = \"x'\(self.hex(key))'\";"
        guard sqlite3_exec(connection, pragma, nil, nil, nil) == SQLITE_OK else {
            throw self.databaseError(connection)
        }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(connection, "PRAGMA cipher_version;", -1, &statement, nil) == SQLITE_OK,
              let statement
        else {
            throw HistoryCipherError.cipherUnavailable
        }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW, let text = sqlite3_column_text(statement, 0) else {
            throw HistoryCipherError.cipherUnavailable
        }
        guard !String(cString: text).isEmpty else {
            throw HistoryCipherError.cipherUnavailable
        }
    }

    /// Copies a plaintext history file into a keyed file, checks the row count,
    /// then replaces the original. A failure leaves the plaintext file in place.
    static func migratePlaintextIfNeeded(at url: URL, key: Data) throws {
        let fileManager = FileManager.default
        try self.restoreInterruptedMigration(at: url)
        guard fileManager.fileExists(atPath: url.path), self.isPlaintext(url) else {
            self.removeLeftoverCopies(at: url)
            return
        }
        let needed = self.byteCount(url) * 3
        let available = self.availableBytes(url)
        guard available > needed else { throw HistoryCipherError.notEnoughDiskSpace }

        let sealed = self.sealedURL(url)
        let plainCount: Int
        do {
            plainCount = try self.export(from: url, to: sealed, key: key)
            let sealedCount = try self.rowCount(at: sealed, key: key)
            guard plainCount == sealedCount else { throw HistoryCipherError.migrationMismatch }
            try self.replacePlaintext(at: url, with: sealed)
        } catch {
            try? fileManager.removeItem(at: sealed)
            throw error
        }
        try? fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    /// A crash between deleting the original and renaming the encrypted file
    /// leaves the spare copy. Put that copy back before SQLite can create an
    /// empty database at the normal path.
    static func restoreInterruptedMigration(at url: URL) throws {
        let fileManager = FileManager.default
        guard !fileManager.fileExists(atPath: url.path) else { return }
        let backup = self.backupURL(url)
        let sealed = self.sealedURL(url)
        if fileManager.fileExists(atPath: backup.path) {
            try fileManager.moveItem(at: backup, to: url)
        } else if fileManager.fileExists(atPath: sealed.path) {
            try fileManager.moveItem(at: sealed, to: url)
        }
    }

    private static func replacePlaintext(at url: URL, with sealed: URL) throws {
        let fileManager = FileManager.default
        for suffix in ["-wal", "-shm"] {
            let sidecar = URL(fileURLWithPath: url.path + suffix)
            if fileManager.fileExists(atPath: sidecar.path) {
                try fileManager.removeItem(at: sidecar)
            }
        }
        let backupName = self.backupURL(url).lastPathComponent
        if fileManager.fileExists(atPath: self.backupURL(url).path) {
            try fileManager.removeItem(at: self.backupURL(url))
        }
        // Replaces the original in one step and keeps it under backupName until
        // the encrypted file is at the normal path.
        _ = try fileManager.replaceItemAt(url, withItemAt: sealed, backupItemName: backupName)
        self.removeLeftoverCopies(at: url)
    }

    private static func removeLeftoverCopies(at url: URL) {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: url.path), !self.isPlaintext(url) else { return }
        try? fileManager.removeItem(at: self.backupURL(url))
        try? fileManager.removeItem(at: self.sealedURL(url))
    }

    private static func backupURL(_ url: URL) -> URL {
        URL(fileURLWithPath: url.path + ".plaintext-copy")
    }

    private static func sealedURL(_ url: URL) -> URL {
        URL(fileURLWithPath: url.path + ".sealed")
    }

    private static func export(from url: URL, to sealed: URL, key: Data) throws -> Int {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: sealed.path) {
            try fileManager.removeItem(at: sealed)
        }
        var handle: OpaquePointer?
        guard sqlite3_open_v2(
            url.path,
            &handle,
            SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX,
            nil
        ) == SQLITE_OK,
              let handle
        else {
            if let handle { sqlite3_close(handle) }
            throw HistoryCipherError.migrationMismatch
        }
        defer { sqlite3_close(handle) }
        try self.execute(handle, "PRAGMA wal_checkpoint(TRUNCATE);")
        let count = try self.historyCount(handle)
        let escaped = sealed.path.replacingOccurrences(of: "'", with: "''")
        try self.execute(
            handle,
            "ATTACH DATABASE '\(escaped)' AS sealed KEY \"x'\(self.hex(key))'\";"
        )
        try self.execute(handle, "SELECT sqlcipher_export('sealed');")
        try self.execute(handle, "DETACH DATABASE sealed;")
        return count
    }

    private static func rowCount(at url: URL, key: Data) throws -> Int {
        var handle: OpaquePointer?
        guard sqlite3_open_v2(url.path, &handle, SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK,
              let handle
        else {
            if let handle { sqlite3_close(handle) }
            throw HistoryCipherError.migrationMismatch
        }
        defer { sqlite3_close(handle) }
        try self.apply(key: key, connection: handle)
        return try self.historyCount(handle)
    }

    private static func historyCount(_ connection: OpaquePointer) throws -> Int {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(
            connection,
            "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='history';",
            -1,
            &statement,
            nil
        ) == SQLITE_OK, let statement else {
            throw HistoryCipherError.migrationMismatch
        }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW, sqlite3_column_int(statement, 0) == 1 else { return 0 }
        var countStatement: OpaquePointer?
        guard sqlite3_prepare_v2(connection, "SELECT COUNT(*) FROM history;", -1, &countStatement, nil) == SQLITE_OK,
              let countStatement
        else {
            throw HistoryCipherError.migrationMismatch
        }
        defer { sqlite3_finalize(countStatement) }
        guard sqlite3_step(countStatement) == SQLITE_ROW else { throw HistoryCipherError.migrationMismatch }
        return Int(sqlite3_column_int(countStatement, 0))
    }

    private static func isPlaintext(_ url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        let header = try? handle.read(upToCount: 16)
        return header == Data("SQLite format 3\0".utf8)
    }

    private static func byteCount(_ url: URL) -> Int64 {
        let paths = [url.path, url.path + "-wal"]
        return paths.reduce(0) { total, path in
            let size = (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? NSNumber)?.int64Value ?? 0
            return total + size
        }
    }

    private static func availableBytes(_ url: URL) -> Int64 {
        if let testingAvailableBytes { return testingAvailableBytes }
        let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return Int64(values?.volumeAvailableCapacityForImportantUsage ?? 0)
    }

    private static func execute(_ connection: OpaquePointer, _ sql: String) throws {
        var message: UnsafeMutablePointer<CChar>?
        let status = sqlite3_exec(connection, sql, nil, nil, &message)
        guard status == SQLITE_OK else {
            let detail = message.map { String(cString: $0) } ?? String(cString: sqlite3_errmsg(connection))
            sqlite3_free(message)
            throw NSError(
                domain: "HistoryDatabase",
                code: Int(status),
                userInfo: [NSLocalizedDescriptionKey: detail]
            )
        }
    }

    private static func databaseError(_ connection: OpaquePointer) -> Error {
        NSError(
            domain: "HistoryDatabase",
            code: Int(sqlite3_errcode(connection)),
            userInfo: [NSLocalizedDescriptionKey: String(cString: sqlite3_errmsg(connection))]
        )
    }

    private static func hex(_ key: Data) -> String {
        key.map { String(format: "%02x", $0) }.joined()
    }
}
