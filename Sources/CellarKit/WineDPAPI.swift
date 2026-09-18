import CommonCrypto
import Foundation

/// Wine's `CryptProtectData` / `CryptUnprotectData` (`dlls/crypt32/protectdata.c`), reproduced so a
/// blob a Windows program in a bottle will accept can be written from outside Wine.
///
/// Wine does not use a machine secret: the key is SHA-1 of the Wine user name (as `GetUserNameA`
/// returns it, NUL included), a fixed string, the blob's salt and the caller's entropy, expanded to
/// a 3DES key the way rsaenh's `CryptDeriveKey` does. Checked against the WineForge runner in both
/// directions — a blob from here decrypts in the bottle, and one from the bottle decrypts here.
enum WineDPAPI {
    /// `"Wine Crypt32 ok"` with its NUL — Wine's stand-in for the provider GUID, 16 bytes.
    static let magic = Data("Wine Crypt32 ok".utf8) + [0]
    private static let secret = Data("I'm hunting wabbits".utf8)
    private static let calg3DES: UInt32 = 0x6603
    private static let calgSHA1: UInt32 = 0x8004

    static func protect(_ plain: Data, user: String, entropy: Data?, salt: Data? = nil) -> Data? {
        let salt = salt ?? randomSalt()
        guard salt.count == 16,
              let cipher = tripleDES(CCOperation(kCCEncrypt), key: key(user: user, salt: salt, entropy: entropy), plain)
        else { return nil }
        var blob = dword(1) + magic + dword(1) + magic + dword(0)
        blob += lengthPrefixed(Data([0, 0]))                         // empty UTF-16 description
        blob += dword(calg3DES) + dword(168) + lengthPrefixed(magic) + dword(0)
        blob += dword(calgSHA1) + dword(160)
        blob += lengthPrefixed(salt) + lengthPrefixed(cipher) + lengthPrefixed(sha1(plain))
        return blob
    }

    static func unprotect(_ blob: Data, user: String, entropy: Data?) -> Data? {
        var reader = BlobReader(bytes: [UInt8](blob))
        guard reader.dword() == 1, reader.raw(16) == magic, reader.dword() == 1, reader.raw(16) == magic,
              reader.dword() == 0, reader.prefixed() != nil,
              reader.dword() == calg3DES, reader.dword() == 168, reader.prefixed() == magic, reader.dword() == 0,
              reader.dword() == calgSHA1, reader.dword() == 160,
              let salt = reader.prefixed(), let cipher = reader.prefixed(), let fingerprint = reader.prefixed(),
              let plain = tripleDES(CCOperation(kCCDecrypt), key: key(user: user, salt: salt, entropy: entropy), cipher),
              sha1(plain) == fingerprint
        else { return nil }
        return plain
    }

    // MARK: - Key

    /// `CryptDeriveKey(CALG_3DES)` over a SHA-1 hash: 20 bytes is short of the 24 a 3DES key needs,
    /// so rsaenh derives it from the hash padded with ipad and opad.
    static func key(user: String, salt: Data, entropy: Data?) -> Data {
        var material = Data(user.utf8) + [0]
        material += secret
        material += salt
        if let entropy { material += entropy }
        let hash = sha1(material)
        func padded(_ c: UInt8) -> Data { Data((0..<64).map { c ^ ($0 < hash.count ? hash[$0] : 0) }) }
        return (sha1(padded(0x36)) + sha1(padded(0x5c))).prefix(24)
    }

    // MARK: - Primitives

    private static func sha1(_ data: Data) -> Data {
        var digest = [UInt8](repeating: 0, count: Int(CC_SHA1_DIGEST_LENGTH))
        data.withUnsafeBytes { _ = CC_SHA1($0.baseAddress, CC_LONG(data.count), &digest) }
        return Data(digest)
    }

    private static func tripleDES(_ operation: CCOperation, key: Data, _ input: Data) -> Data? {
        var output = Data(count: input.count + kCCBlockSize3DES)
        let capacity = output.count
        var moved = 0
        let iv = Data(count: kCCBlockSize3DES)
        let status = output.withUnsafeMutableBytes { out in
            input.withUnsafeBytes { inp in
                key.withUnsafeBytes { k in
                    iv.withUnsafeBytes { v in
                        CCCrypt(operation, CCAlgorithm(kCCAlgorithm3DES), CCOptions(kCCOptionPKCS7Padding),
                                k.baseAddress, kCCKeySize3DES, v.baseAddress,
                                inp.baseAddress, input.count, out.baseAddress, capacity, &moved)
                    }
                }
            }
        }
        return status == kCCSuccess ? output.prefix(moved) : nil
    }

    private static func randomSalt() -> Data {
        var bytes = [UInt8](repeating: 0, count: 16)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            return Data((0..<16).map { _ in UInt8.random(in: .min ... .max) })
        }
        return Data(bytes)
    }

    private static func dword(_ value: UInt32) -> Data { withUnsafeBytes(of: value.littleEndian) { Data($0) } }
    private static func lengthPrefixed(_ data: Data) -> Data { dword(UInt32(data.count)) + data }

    private struct BlobReader {
        let bytes: [UInt8]
        var index = 0

        mutating func dword() -> UInt32? {
            guard index + 4 <= bytes.count else { return nil }
            defer { index += 4 }
            return bytes[index..<index + 4].reversed().reduce(0) { $0 << 8 | UInt32($1) }
        }

        mutating func raw(_ count: Int) -> Data? {
            guard count >= 0, index + count <= bytes.count else { return nil }
            defer { index += count }
            return Data(bytes[index..<index + count])
        }

        mutating func prefixed() -> Data? {
            guard let count = dword() else { return nil }
            return raw(Int(count))
        }
    }
}
