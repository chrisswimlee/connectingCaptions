import AppKit
import Foundation

/// Which GitHub zip an install should fetch, and how a relaunch closes the copy
/// that is still showing the download panel.
enum UpdateAssetSelection {
    /// fluidSubtitles 1.6.12 accepts only this codesign identifier.
    static let legacyBundleIdentifier = "com.fluidsubtitles.app"

    /// That build is already at the latest version number and still has the old identifier.
    /// Install the Connecting Captions zip anyway so the next launch is the current app.
    static func installsDespiteSameVersion(runningBundleIdentifier: String?) -> Bool {
        runningBundleIdentifier == self.legacyBundleIdentifier
    }

    /// Prefer `Connecting-Captions-{version}.zip`. A same-bytes alias signed as another
    /// bundle id must not be chosen when the product zip is on the release.
    static func preferredZipName(in names: [String], version: String, repo: String) -> String? {
        let product = "\(ConnectingCaptionsProduct.releaseDownloadPrefix)-\(version).zip"
        if let exact = names.first(where: { $0.caseInsensitiveCompare(product) == .orderedSame }) {
            return exact
        }
        let prefixes = [ConnectingCaptionsProduct.releaseDownloadPrefix]
            + ConnectingCaptionsProduct.legacyReleaseDownloadPrefixes
            + [repo]
        return names.first { name in
            guard name.lowercased().hasSuffix(".zip") else { return false }
            let base = (name as NSString).deletingPathExtension.lowercased()
            return prefixes.contains { prefix in
                base == "\(prefix.lowercased())-\(version.lowercased())"
            }
        }
    }
}

enum UpdateHandoff {
    /// The outdated updater replaces this bundle, opens the new copy, then waits on Quit.
    /// That wait never finishes, so the downloading panel stays up. Close that copy.
    static func closePreviousCopy() {
        let myPID = ProcessInfo.processInfo.processIdentifier
        guard let bundleID = Bundle.main.bundleIdentifier else { return }
        let myPath = Bundle.main.bundleURL.resolvingSymlinksInPath().standardizedFileURL.path
        let others = NSWorkspace.shared.runningApplications.filter { app in
            app.processIdentifier != myPID
                && app.bundleIdentifier == bundleID
                && app.bundleURL?.resolvingSymlinksInPath().standardizedFileURL.path == myPath
        }
        guard !others.isEmpty else { return }
        DebugLogger.shared.info(
            "Closing \(others.count) previous copy still running this app",
            source: "UpdateHandoff"
        )
        for app in others {
            app.terminate()
        }
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 2) {
            for app in others where app.isTerminated == false {
                app.forceTerminate()
            }
        }
    }
}

/// A fresh session. `URLSession.shared` in a long-lived app can sit on the download
/// panel until the system timeout, which is days.
enum UpdateTransfer {
    private static func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 600
        config.waitsForConnectivity = false
        config.httpAdditionalHeaders = ["User-Agent": "ConnectingCaptions"]
        return URLSession(configuration: config, delegate: nil, delegateQueue: nil)
    }

    static func download(from url: URL, to destination: URL) async throws {
        do {
            try await self.transfer(from: url, to: destination)
        } catch {
            try await self.transfer(from: url, to: destination)
        }
    }

    static func data(from url: URL) async throws -> Data {
        let session = self.session()
        defer { session.finishTasksAndInvalidate() }
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw SimpleUpdateError.invalidResponse
        }
        return data
    }

    static func text(from url: URL) async throws -> String {
        let data = try await self.data(from: url)
        guard let text = String(data: data, encoding: .utf8) else {
            throw SimpleUpdateError.checksumMissing
        }
        return text
    }

    private static func transfer(from url: URL, to destination: URL) async throws {
        let loader = FileDownload(destination: destination)
        try await loader.run(url)
    }
}

private final class FileDownload: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let destination: URL
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Error>?
    private var session: URLSession?
    private var storedFile = false

    init(destination: URL) {
        self.destination = destination
    }

    func run(_ url: URL) async throws {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 600
        config.waitsForConnectivity = false
        config.httpAdditionalHeaders = ["User-Agent": "ConnectingCaptions"]
        let session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        self.session = session
        defer {
            session.finishTasksAndInvalidate()
            self.session = nil
        }
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            self.lock.lock()
            self.continuation = cont
            self.lock.unlock()
            session.downloadTask(with: url).resume()
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        do {
            guard let http = downloadTask.response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode)
            else {
                let status = (downloadTask.response as? HTTPURLResponse)?.statusCode ?? 0
                throw SimpleUpdateError.downloadFailed("The server returned HTTP \(status).")
            }
            let folder = self.destination.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: self.destination.path) {
                try FileManager.default.removeItem(at: self.destination)
            }
            do {
                try FileManager.default.moveItem(at: location, to: self.destination)
            } catch {
                try FileManager.default.copyItem(at: location, to: self.destination)
            }
            self.lock.lock()
            self.storedFile = true
            self.lock.unlock()
        } catch {
            self.finish(.failure(error))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            self.finish(.failure(SimpleUpdateError.downloadFailed(error.localizedDescription)))
            return
        }
        self.lock.lock()
        let stored = self.storedFile
        self.lock.unlock()
        if stored {
            self.finish(.success(()))
        } else {
            self.finish(.failure(SimpleUpdateError.downloadFailed("The download did not finish.")))
        }
    }

    private func finish(_ result: Result<Void, Error>) {
        self.lock.lock()
        let continuation = self.continuation
        self.continuation = nil
        self.lock.unlock()
        continuation?.resume(with: result)
    }
}
