import CellarDomain
import Compression
import Foundation

/// Reads DepotDownloader's `account.config`: the **account names** for every caller, and a single
/// account's refresh token for the one caller that needs it — `refreshToken(for:)`, which exists so
/// the Windows client in a bottle can be handed the session the player already approved
/// (`SteamClientSession`). `accountNames` still never copies a token out.
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
        var reader = ProtoReader([UInt8](raw))
        while let (field, wire) = reader.tag() {
            guard wire == 2, let entry = reader.lengthDelimited() else {
                guard reader.skip(wire: wire) else { return names }
                continue
            }
            guard field == 4 else { continue }
            var inner = ProtoReader(entry)
            while let (key, kwire) = inner.tag() {
                if key == 1, kwire == 2, let bytes = inner.lengthDelimited() {
                    if let name = String(bytes: bytes, encoding: .utf8), !name.isEmpty { names.append(name) }
                } else if !inner.skip(wire: kwire) {
                    break
                }
            }
        }
        return names
    }

    /// The refresh token stored for one account — the only reader that copies a token out, and only
    /// so the Windows client in a bottle can be handed the session the player already approved
    /// (`SteamClientSession`). The result must never reach a log, a report or an error message.
    static func refreshToken(for account: String, in file: URL) -> String? {
        guard let data = try? Data(contentsOf: file) else { return nil }
        return refreshToken(for: account, inCompressed: data)
    }

    static func refreshToken(for account: String, inCompressed data: Data) -> String? {
        guard let raw = inflate(data) else { return nil }
        var found: String?
        var reader = ProtoReader([UInt8](raw))
        while let (field, wire) = reader.tag() {
            guard wire == 2, let entry = reader.lengthDelimited() else {
                guard reader.skip(wire: wire) else { return found }
                continue
            }
            guard field == 4 else { continue }
            var inner = ProtoReader(entry)
            var name: String?, token: String?
            while let (key, kwire) = inner.tag() {
                if kwire == 2, key == 1 || key == 2, let bytes = inner.lengthDelimited() {
                    let text = String(bytes: bytes, encoding: .utf8)
                    if key == 1 { name = text } else { token = text }
                } else if !inner.skip(wire: kwire) {
                    break
                }
            }
            // Steam account names are case-insensitive; the last entry wins, as it does in .NET's map.
            if let name, name.caseInsensitiveCompare(account) == .orderedSame, let token, !token.isEmpty {
                found = token
            }
        }
        return found
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
