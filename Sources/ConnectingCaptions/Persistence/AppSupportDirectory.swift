import Foundation

nonisolated enum AppTestEnvironment {
    static var isRunning: Bool {
        let environment = ProcessInfo.processInfo.environment
        #if DEBUG
        if environment["CONNECTINGCAPTIONS_UI_TESTS"] == "1" { return true }
        #endif
        return environment["XCTestConfigurationFilePath"] != nil
    }

    static let supportDirectory: URL? = {
        guard Self.isRunning else { return nil }
        return FileManager.default.temporaryDirectory
            .appendingPathComponent("connectingCaptions-tests-\(UUID().uuidString)", isDirectory: true)
    }()
}

nonisolated enum AppSupportDirectory {
    static func url(fileManager: FileManager = .default) -> URL {
        if let testDirectory = AppTestEnvironment.supportDirectory { return testDirectory }
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent(
                "Library/Application Support",
                isDirectory: true
            )
        let current = base.appendingPathComponent(ConnectingCaptionsProduct.supportFolderName, isDirectory: true)

        if fileManager.fileExists(atPath: current.path) {
            return current
        }

        for legacyName in ConnectingCaptionsProduct.priorSupportFolderNames {
            guard self.shouldRenameLegacyFolder(named: legacyName) else { continue }
            let legacy = base.appendingPathComponent(legacyName, isDirectory: true)
            guard fileManager.fileExists(atPath: legacy.path) else { continue }
            do {
                try fileManager.moveItem(at: legacy, to: current)
                return current
            } catch {
                DebugLogger.shared.warning(
                    "Could not migrate \(legacyName) support folder: \(error.localizedDescription)",
                    source: "AppSupportDirectory"
                )
                return legacy
            }
        }

        return current
    }

    /// Only this app's earlier folder name is renamed. A FluidVoice folder stays put.
    static func shouldRenameLegacyFolder(named legacyName: String) -> Bool {
        ConnectingCaptionsProduct.priorSupportFolderNames.contains(legacyName)
    }
}
