import Foundation
import Security

/// 32-byte history key in the login keychain. Debug and Release share this
/// account so a local build can still open history encrypted by the signed app.
enum TranscriptKey {
    private static let service = "com.connectingcaptions.history-vault"
    private static let account = "history-vault"
    /// Earlier Debug builds stored the key here. Keep reading it so a file
    /// those builds already encrypted still opens.
    private static let legacyDebugAccount = "history-vault-debug"
    private static let lock = NSLock()

    static func load() -> Data? {
        self.lock.lock()
        defer { self.lock.unlock() }
        switch self.read(self.account) {
        case let .found(data):
            return data
        case .unavailable:
            return nil
        case .missing:
            if case let .found(legacy) = self.read(self.legacyDebugAccount) {
                if !self.store(legacy), case let .found(data) = self.read(self.account) {
                    return data
                }
                return legacy
            }
            let created = self.randomKey()
            if self.store(created) {
                return created
            }
            // Another caller stored the key between the read and the add.
            if case let .found(data) = self.read(self.account) { return data }
            return nil
        }
    }

    private static func randomKey() -> Data {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        if status == errSecSuccess { return Data(bytes) }
        return Data((0 ..< 32).map { _ in UInt8.random(in: .min ... .max) })
    }

    private enum ReadResult {
        case found(Data)
        case missing
        case unavailable
    }

    private static func read(_ account: String) -> ReadResult {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: self.service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data, data.count == 32 else { return .unavailable }
            return .found(data)
        case errSecItemNotFound:
            return .missing
        default:
            return .unavailable
        }
    }

    private static func store(_ data: Data) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: self.service,
            kSecAttrAccount as String: self.account,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: data,
        ]
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }
}
