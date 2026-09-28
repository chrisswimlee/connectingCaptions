import Foundation

/// Voice Engine weights live under this app's Application Support folder.
/// FluidAudio's own cache is a shared library folder. This type copies a model
/// out of it once, then reads and deletes only the copy.
enum VoiceEngineModelDirectory {
    private static let lock = NSLock()
    private static let legacyModelsMarker = "/FluidAudio/Models/"

    static func modelsRoot() -> URL {
        AppSupportDirectory.url().appendingPathComponent("Models", isDirectory: true)
    }

    static func relativePath(mirroring legacy: URL) -> String {
        let path = legacy.standardizedFileURL.path
        if let range = path.range(of: self.legacyModelsMarker) {
            return String(path[range.upperBound...])
        }
        return legacy.lastPathComponent
    }

    static func ownedURL(mirroring legacy: URL, modelsRoot: URL) -> URL {
        modelsRoot.appendingPathComponent(self.relativePath(mirroring: legacy), isDirectory: true)
    }

    static func ownedURL(mirroring legacy: URL) -> URL {
        self.ownedURL(mirroring: legacy, modelsRoot: self.modelsRoot())
    }

    static func hasAdopted(legacy: URL, modelsRoot: URL, fileManager: FileManager = .default) -> Bool {
        fileManager.fileExists(atPath: self.markerURL(for: legacy, modelsRoot: modelsRoot).path)
    }

    static func hasAdopted(legacy: URL) -> Bool {
        self.hasAdopted(legacy: legacy, modelsRoot: self.modelsRoot())
    }

    /// Copies `legacy` into this app's Models folder when that copy does not exist yet.
    /// A later discard keeps the marker so the shared folder is not copied again.
    @discardableResult
    static func adopt(legacy: URL, modelsRoot: URL, fileManager: FileManager = .default) -> URL {
        self.lock.lock()
        defer { self.lock.unlock() }

        let owned = self.ownedURL(mirroring: legacy, modelsRoot: modelsRoot)
        let marker = self.markerURL(for: legacy, modelsRoot: modelsRoot)
        if fileManager.fileExists(atPath: owned.path) {
            self.writeMarker(marker, fileManager: fileManager)
            return owned
        }
        if fileManager.fileExists(atPath: marker.path) {
            return owned
        }
        guard fileManager.fileExists(atPath: legacy.path) else {
            return owned
        }

        do {
            try fileManager.createDirectory(
                at: owned.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try fileManager.copyItem(at: legacy, to: owned)
            self.writeMarker(marker, fileManager: fileManager)
        } catch {
            DebugLogger.shared.warning(
                "Could not copy Voice Engine weights out of the shared cache: \(error.localizedDescription)",
                source: "VoiceEngineModelDirectory"
            )
        }
        return owned
    }

    @discardableResult
    static func adopt(legacy: URL) -> URL {
        self.adopt(legacy: legacy, modelsRoot: self.modelsRoot())
    }

    /// Deletes this app's copy and remembers that the shared cache must stay put.
    static func discardOwnedCopy(of legacy: URL, modelsRoot: URL, fileManager: FileManager = .default) throws {
        self.lock.lock()
        defer { self.lock.unlock() }

        let owned = self.ownedURL(mirroring: legacy, modelsRoot: modelsRoot)
        self.writeMarker(self.markerURL(for: legacy, modelsRoot: modelsRoot), fileManager: fileManager)
        if fileManager.fileExists(atPath: owned.path) {
            try fileManager.removeItem(at: owned)
        }
    }

    static func discardOwnedCopy(of legacy: URL) throws {
        try self.discardOwnedCopy(of: legacy, modelsRoot: self.modelsRoot())
    }

    private static func markerURL(for legacy: URL, modelsRoot: URL) -> URL {
        let safe = self.relativePath(mirroring: legacy).replacingOccurrences(of: "/", with: "_")
        return modelsRoot
            .appendingPathComponent(".adopted", isDirectory: true)
            .appendingPathComponent(safe, isDirectory: false)
    }

    private static func writeMarker(_ url: URL, fileManager: FileManager) {
        try? fileManager.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if !fileManager.fileExists(atPath: url.path) {
            fileManager.createFile(atPath: url.path, contents: Data())
        }
    }
}
