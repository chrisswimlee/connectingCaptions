import Darwin
import Foundation
import OpenDirectory

/// When this Mac was first signed in. Copied files from an older machine are dated before this.
enum MacFirstSignOn {
    private static let setupAssistantPath = "/var/db/.AppleSetupDone"
    /// Unix timestamps for this century sit above this. Smaller values are CFAbsoluteTime.
    private static let unixTimestampFloor: TimeInterval = 1_200_000_000

    /// When this Mac was set up. The home folder is not included: a restored folder can be newer than the files inside it.
    static func date(fileManager: FileManager = .default) -> Date? {
        if let setup = self.setupAssistantDate(fileManager: fileManager) {
            return setup
        }
        if let account = self.accountCreationDate() {
            return account
        }
        return self.homeCreationDate(fileManager: fileManager)
    }

    /// Wall-clock time this process was created. A file written on this launch is newer than this.
    static func processStart() -> Date? {
        var info = proc_bsdinfo()
        let size = proc_pidinfo(getpid(), PROC_PIDTBSDINFO, 0, &info, Int32(MemoryLayout<proc_bsdinfo>.size))
        guard size == MemoryLayout<proc_bsdinfo>.size else { return nil }
        let seconds = TimeInterval(info.pbi_start_tvsec) + TimeInterval(info.pbi_start_tvusec) / 1_000_000
        guard seconds > 0 else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }

    static func date(fromPolicyTimestamp timestamp: TimeInterval) -> Date? {
        guard timestamp > 0, timestamp < 4_000_000_000 else { return nil }
        if timestamp >= self.unixTimestampFloor {
            return Date(timeIntervalSince1970: timestamp)
        }
        return Date(timeIntervalSinceReferenceDate: timestamp)
    }

    private static func setupAssistantDate(fileManager: FileManager) -> Date? {
        self.creationDate(at: URL(fileURLWithPath: self.setupAssistantPath), fileManager: fileManager)
    }

    private static func homeCreationDate(fileManager: FileManager) -> Date? {
        self.creationDate(at: fileManager.homeDirectoryForCurrentUser, fileManager: fileManager)
    }

    private static func creationDate(at url: URL, fileManager: FileManager) -> Date? {
        guard let attributes = try? fileManager.attributesOfItem(atPath: url.path) else { return nil }
        return attributes[.creationDate] as? Date
    }

    private static func accountCreationDate() -> Date? {
        guard let raw = self.accountPolicyTimestamp() else { return nil }
        return self.date(fromPolicyTimestamp: raw)
    }

    private static func accountPolicyTimestamp() -> TimeInterval? {
        do {
            let node = try ODNode(session: ODSession.default(), name: "/Local/Default")
            let record = try node.record(
                withRecordType: kODRecordTypeUsers,
                name: NSUserName(),
                attributes: nil
            )
            let values = try record.values(forAttribute: "dsAttrTypeNative:accountPolicyData")
            for value in values {
                if let timestamp = self.timestamp(inPolicyValue: value) {
                    return timestamp
                }
            }
        } catch {
            return nil
        }
        return nil
    }

    private static func timestamp(inPolicyValue value: Any) -> TimeInterval? {
        let data: Data?
        if let bytes = value as? Data {
            data = bytes
        } else if let text = value as? String {
            data = Data(text.utf8)
        } else {
            data = nil
        }
        guard let data,
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else {
            return nil
        }
        if let number = plist["creationTime"] as? TimeInterval {
            return number
        }
        if let number = plist["creationTime"] as? NSNumber {
            return number.doubleValue
        }
        return nil
    }
}
