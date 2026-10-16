import Foundation

/// Stages on the destination volume and retains displaced bundles until relaunch.
/// Failed recovery leaves every surviving bundle in a named recovery directory.
enum AppBundleReplacement {
    typealias Move = (URL, URL) throws -> Void

    struct RecoveryRequired: LocalizedError {
        let directory: URL
        var errorDescription: String? {
            AppLanguage.format("The app could not be restored automatically. Recovery files are at {0}.", self.directory.path)
        }
    }

    struct Transaction {
        let destination: URL
        let directory: URL
        let displaced: [(original: URL, backup: URL)]

        func commit(fileManager: FileManager = .default) {
            do {
                try fileManager.removeItem(at: self.directory)
            } catch {
                DebugLogger.shared.warning("Update recovery files retained at \(self.directory.path)", source: "SimpleUpdater")
            }
        }

        func rollback(fileManager: FileManager = .default) throws {
            do {
                if fileManager.fileExists(atPath: self.destination.path) {
                    try fileManager.moveItem(at: self.destination, to: self.directory.appendingPathComponent("Rejected.app"))
                }
                for item in self.displaced.reversed() {
                    try fileManager.moveItem(at: item.backup, to: item.original)
                }
            } catch {
                throw RecoveryRequired(directory: self.directory)
            }
            try? fileManager.removeItem(at: self.directory)
        }
    }

    static func begin(
        installed: URL,
        candidate: URL,
        destination: URL,
        fileManager: FileManager = .default,
        move: Move? = nil
    ) throws -> Transaction {
        let move = move ?? { try fileManager.moveItem(at: $0, to: $1) }
        let directory = installed.deletingLastPathComponent()
            .appendingPathComponent(".ConnectingCaptions-update-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: false)
        let staged = directory.appendingPathComponent("Candidate.app", isDirectory: true)
        var displaced: [(original: URL, backup: URL)] = []
        do {
            // A missing candidate or failed copy cannot touch the installed app.
            try fileManager.copyItem(at: candidate, to: staged)
            var originals = [installed]
            if destination.standardizedFileURL != installed.standardizedFileURL { originals.append(destination) }
            for (index, original) in originals.enumerated() where fileManager.fileExists(atPath: original.path) {
                let backup = directory.appendingPathComponent("Previous-\(index).app", isDirectory: true)
                displaced.append((original, backup))
                try move(original, backup)
            }
            try move(staged, destination)
        } catch {
            var recovered = true
            for item in displaced.reversed() {
                if fileManager.fileExists(atPath: item.backup.path) {
                    do { try move(item.backup, item.original) } catch { recovered = false }
                } else if !fileManager.fileExists(atPath: item.original.path) {
                    recovered = false
                }
            }
            guard recovered else { throw RecoveryRequired(directory: directory) }
            try? fileManager.removeItem(at: directory)
            throw error
        }
        return Transaction(destination: destination, directory: directory, displaced: displaced)
    }
}
