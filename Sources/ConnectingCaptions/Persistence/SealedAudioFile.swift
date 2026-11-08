import CryptoKit
import Foundation

enum SealedAudioFile {
    static let magic = Data("CCVAULT1".utf8)

    static func isSealed(at url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        return (try? handle.read(upToCount: self.magic.count)) == self.magic
    }

    static func sealInPlace(at url: URL, key: Data) throws {
        let plain = try Data(contentsOf: url)
        if plain.starts(with: self.magic) { return }
        let sealed = try self.seal(plain, key: key)
        let temporary = url.appendingPathExtension("sealing")
        try sealed.write(to: temporary, options: .atomic)
        _ = try FileManager.default.replaceItemAt(url, withItemAt: temporary)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    static func plaintext(at url: URL, key: Data) throws -> Data {
        let data = try Data(contentsOf: url)
        guard data.starts(with: self.magic) else { return data }
        let box = try AES.GCM.SealedBox(combined: data.dropFirst(self.magic.count))
        return try AES.GCM.open(box, using: SymmetricKey(data: key))
    }

    private static func seal(_ plain: Data, key: Data) throws -> Data {
        let box = try AES.GCM.seal(plain, using: SymmetricKey(data: key))
        guard let combined = box.combined else {
            throw DictationAudioHistoryError.audioMissing
        }
        return self.magic + combined
    }
}
