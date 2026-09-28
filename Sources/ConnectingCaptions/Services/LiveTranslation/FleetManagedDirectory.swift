import Foundation

/// Root-owned files a Jamf or Fleet pkg drops for this Mac.
/// Tests never read `/Library` unless they set `machineRootOverride`.
nonisolated enum FleetManagedDirectory {
    static let licenseFileName = "license.key"
    static let rosterFileName = "seats.roster"
    static let settingsFileName = "settings.fleet.json"

    #if DEBUG
    nonisolated(unsafe) static var machineRootOverride: URL?
    #endif

    static var machineRoot: URL {
        URL(fileURLWithPath: "/Library/Application Support/\(ConnectingCaptionsProduct.supportFolderName)", isDirectory: true)
    }

    static func licenseToken() -> String? {
        self.readText(self.licenseFileName)
    }

    static func rosterToken() -> String? {
        self.readText(self.rosterFileName)
    }

    static func settingsData() -> Data? {
        guard let root = self.rootForRead() else { return nil }
        let url = root.appendingPathComponent(self.settingsFileName)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try? Data(contentsOf: url)
    }

    private static func readText(_ name: String) -> String? {
        guard let root = self.rootForRead() else { return nil }
        let url = root.appendingPathComponent(name)
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func rootForRead() -> URL? {
        #if DEBUG
        if let override = self.machineRootOverride {
            return override
        }
        if SettingsStore.isRunningTests {
            return nil
        }
        #endif
        return self.machineRoot
    }
}
