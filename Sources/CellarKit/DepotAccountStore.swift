import Compression
import Foundation

/// Reads the **account names** out of DepotDownloader's `account.config` — never the tokens.
///
/// A QR sign-in has only one place the account name reliably appears: the key the refresh token is
/// stored under. DepotDownloader's `Success! … -username <name>` line is printed only when Steam
/// also hands back new Steam Guard data, which an ordinary approval in the mobile app does not — so
/// waiting for that line left a completed sign-in looking like one that never happened.
///
/// The file is a protobuf-net `AccountSettingsStore` written through a raw `DeflateStream`
/// (DepotDownloader 3.4.0, `AccountSettingsStore.cs`): field 4 is `LoginTokens`, a
/// `map<string, string>` from account name to token. Only the map keys are decoded; the values are
/// skipped without being copied into a string.
enum DepotAccountStore {
    /// Account names holding a token, in file order. Empty for anything that doesn't parse — an
    /// unreadable store is "no names", never a crash.
    static func accountNames(in file: URL) -> [String] {
        guard let data = try? Data(contentsOf: file) else { return [] }
        return accountNames(inCompressed: data)
    }

    static func accountNames(inCompressed data: Data) -> [String] {
        guard let raw = inflate(data) else { return [] }
        var names: [String] = []
        var reader = ProtoReader(raw)
        while let (field, wire) = reader.tag() {
            guard wire == 2, let entry = reader.lengthDelimited() else {
                guard reader.skip(wire) else { return names }
                continue
            }
            guard field == 4 else { continue }
            var inner = ProtoReader(entry)
            while let (key, kwire) = inner.tag() {
                if key == 1, kwire == 2, let bytes = inner.lengthDelimited() {
                    if let name = String(bytes: bytes, encoding: .utf8), !name.isEmpty { names.append(name) }
                } else if !inner.skip(kwire) {
                    break
                }
            }
        }
        return names
    }

    /// Raw deflate (no zlib header), which is what .NET's `DeflateStream` writes and what Apple's
    /// `COMPRESSION_ZLIB` means.
    private static func inflate(_ data: Data) -> Data? {
        guard !data.isEmpty else { return nil }
        var capacity = max(4096, data.count * 8)
        while capacity <= 16 << 20 {
            var out = Data(count: capacity)
            let written = out.withUnsafeMutableBytes { dst in
                data.withUnsafeBytes { src in
                    compression_decode_buffer(
                        dst.bindMemory(to: UInt8.self).baseAddress!, capacity,
                        src.bindMemory(to: UInt8.self).baseAddress!, data.count,
                        nil, COMPRESSION_ZLIB)
                }
            }
            if written == 0 { return nil }
            if written < capacity { return out.prefix(written) }
            capacity *= 4                                   // filled the buffer: may be truncated
        }
        return nil
    }
}

/// Just enough protobuf to walk a message: varints, length-delimited fields, and skipping the rest.
private struct ProtoReader {
    private let bytes: [UInt8]
    private var index = 0

    init(_ data: Data) { bytes = [UInt8](data) }

    mutating func tag() -> (field: UInt64, wire: UInt64)? {
        guard index < bytes.count, let v = varint() else { return nil }
        return (v >> 3, v & 7)
    }

    mutating func varint() -> UInt64? {
        var result: UInt64 = 0
        var shift: UInt64 = 0
        while index < bytes.count, shift < 64 {
            let b = bytes[index]; index += 1
            result |= UInt64(b & 0x7f) << shift
            if b & 0x80 == 0 { return result }
            shift += 7
        }
        return nil
    }

    mutating func lengthDelimited() -> Data? {
        guard let n = varint(), n <= UInt64(bytes.count - index) else { return nil }
        defer { index += Int(n) }
        return Data(bytes[index..<index + Int(n)])
    }

    mutating func skip(_ wire: UInt64) -> Bool {
        switch wire {
        case 0: return varint() != nil
        case 1: guard index + 8 <= bytes.count else { return false }; index += 8; return true
        case 2: return lengthDelimited() != nil
        case 5: guard index + 4 <= bytes.count else { return false }; index += 4; return true
        default: return false
        }
    }
}
