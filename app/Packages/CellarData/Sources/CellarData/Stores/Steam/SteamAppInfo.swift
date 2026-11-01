import CellarDomain
import Foundation

/// Reading Steam's own cache of app info (`appcache/appinfo.vdf`), which a signed-in client keeps
/// for every app the account owns.
///
/// Cellar needs one fact from it: the **build id** Steam is serving on a branch. An appmanifest
/// Cellar writes for a copy it downloaded has to name that build, or Steam takes the copy for an
/// old one and starts "updating" it the moment it starts.
///
/// The file is binary key-values behind a short header. Version 28 spells keys inline; version 29
/// (the current client) keeps them in a string table at the end and refers to them by index.
/// Anything that does not parse is nil, never a guess.
public enum SteamAppInfo {
    /// `appcache/appinfo.vdf` in a Steam install.
    public static func cacheFile(steamDirectory: URL) -> URL {
        steamDirectory.appendingPathComponent("appcache/appinfo.vdf")
    }

    /// The build id Steam serves for `appID` on `branch`, from the client's cache.
    public static func buildID(appID: Int, branch: String = "public", steamDirectory: URL) -> UInt64? {
        guard let data = try? Data(contentsOf: cacheFile(steamDirectory: steamDirectory), options: .mappedIfSafe) else {
            return nil
        }
        return buildID(appID: appID, branch: branch, in: data)
    }

    /// The same, from the file's bytes — split out so it can be tested without a Steam install.
    static func buildID(appID: Int, branch: String = "public", in data: Data) -> UInt64? {
        guard let info = appInfo(appID: appID, in: data),
              let value = info.value(at: ["appinfo", "depots", "branches", branch, "buildid"]) else { return nil }
        return value
    }

    // MARK: - The file

    static let magic28: UInt32 = 0x0756_4428
    static let magic29: UInt32 = 0x0756_4429

    /// The key-values for one app, or nil when the cache has no entry for it or does not parse.
    static func appInfo(appID: Int, in data: Data) -> BinaryKV? {
        let bytes = [UInt8](data)
        var reader = ByteReader(bytes)
        guard let magic = reader.u32(), magic == magic28 || magic == magic29, reader.u32() != nil else { return nil }
        var strings: [String]?
        if magic == magic29 {
            guard let offset = reader.i64(), offset > 0, offset < bytes.count,
                  let table = stringTable(bytes, at: Int(offset)) else { return nil }
            strings = table
        }
        while let id = reader.u32(), id != 0 {
            guard let size = reader.u32() else { return nil }
            let start = reader.position
            let end = start + Int(size)
            guard end <= bytes.count else { return nil }
            if id == UInt32(clamping: appID) {
                // infoState u32, lastUpdated u32, picsToken u64, sha1[20], changeNumber u32,
                // binarySha1[20] — then the key-values.
                let header = 4 + 4 + 8 + 20 + 4 + 20
                guard start + header < end else { return nil }
                var kv = ByteReader(Array(bytes[(start + header)..<end]))
                return BinaryKV.parse(&kv, strings: strings)
            }
            reader.position = end
        }
        return nil
    }

    static func stringTable(_ bytes: [UInt8], at offset: Int) -> [String]? {
        var reader = ByteReader(bytes)
        reader.position = offset
        guard let count = reader.u32(), Int(count) <= bytes.count else { return nil }
        var table: [String] = []
        table.reserveCapacity(Int(count))
        for _ in 0..<count {
            guard let s = reader.cString() else { return nil }
            table.append(s)
        }
        return table
    }

    // MARK: - Binary key-values

    /// Steam's binary KeyValues: a type byte, a key, a value — nested blocks closed by `0x08`.
    /// Only what Cellar reads is kept typed; every other value is skipped by its known width.
    struct BinaryKV: Equatable {
        var children: [String: BinaryKV] = [:]
        var number: UInt64?
        var string: String?

        func value(at path: [String]) -> UInt64? {
            guard let first = path.first else { return number ?? string.flatMap { UInt64($0) } }
            // Steam's keys are case-insensitive; the cache spells them as the app's author did.
            let child = children[first] ?? children.first { $0.key.caseInsensitiveCompare(first) == .orderedSame }?.value
            return child?.value(at: Array(path.dropFirst()))
        }

        static func parse(_ reader: inout ByteReader, strings: [String]?, depth: Int = 0) -> BinaryKV? {
            guard depth < 64 else { return nil }
            var node = BinaryKV()
            while let type = reader.u8() {
                if type == 0x08 || type == 0x0B { return node }
                let key: String
                if let strings {
                    guard let index = reader.u32(), Int(index) < strings.count else { return nil }
                    key = strings[Int(index)]
                } else {
                    guard let k = reader.cString() else { return nil }
                    key = k
                }
                switch type {
                case 0x00:
                    guard let child = parse(&reader, strings: strings, depth: depth + 1) else { return nil }
                    node.children[key] = child
                case 0x01:
                    guard let s = reader.cString() else { return nil }
                    node.children[key] = BinaryKV(string: s)
                case 0x02, 0x04, 0x06:      // int32, pointer, colour
                    guard let v = reader.u32() else { return nil }
                    node.children[key] = BinaryKV(number: UInt64(v))
                case 0x03:                  // float32
                    guard reader.u32() != nil else { return nil }
                case 0x07, 0x0A:            // uint64, int64
                    guard let v = reader.u64() else { return nil }
                    node.children[key] = BinaryKV(number: v)
                default:
                    return nil
                }
            }
            // Ran out of bytes before the block closed.
            return depth == 0 ? node : nil
        }
    }

    /// Little-endian reads over a byte array, nil past the end.
    struct ByteReader {
        let bytes: [UInt8]
        var position = 0

        init(_ bytes: [UInt8]) { self.bytes = bytes }

        mutating func u8() -> UInt8? {
            guard position < bytes.count else { return nil }
            defer { position += 1 }
            return bytes[position]
        }

        mutating func u32() -> UInt32? {
            guard position + 4 <= bytes.count else { return nil }
            var v: UInt32 = 0
            for i in 0..<4 { v |= UInt32(bytes[position + i]) << (8 * UInt32(i)) }
            position += 4
            return v
        }

        mutating func u64() -> UInt64? {
            guard position + 8 <= bytes.count else { return nil }
            var v: UInt64 = 0
            for i in 0..<8 { v |= UInt64(bytes[position + i]) << (8 * UInt64(i)) }
            position += 8
            return v
        }

        mutating func i64() -> Int64? { u64().map { Int64(bitPattern: $0) } }

        mutating func cString() -> String? {
            guard let end = bytes[position...].firstIndex(of: 0) else { return nil }
            defer { position = end + 1 }
            return String(decoding: bytes[position..<end], as: UTF8.self)
        }
    }
}
