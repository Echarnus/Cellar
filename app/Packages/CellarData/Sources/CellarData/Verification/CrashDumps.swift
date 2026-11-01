import Foundation

/// Crash dumps a game wrote while `cellar verify` watched it (#210).
///
/// The PC2 pilot showed a game can die, start its own crash reporter after the process table was
/// last read, and leave nothing in any text log: the only evidence was a Windows minidump under the
/// bottle's `AppData`. Frontier writes the reason (a Lua error and its callstack, which named the
/// failed account call) into the dump's comment stream. So verify looks for dumps written during the
/// run and reads those comments.
public enum CrashDumps {
    public struct Dump: Equatable, Sendable {
        public let path: String
        /// The minidump's `CommentStreamA`, if it has one.
        public let comment: String?
    }

    /// Every `.dmp` under the bottle's user folders written at or after `since`, oldest first.
    public static func written(in prefix: URL, since: Date) -> [Dump] {
        let users = prefix.appendingPathComponent("drive_c/users", isDirectory: true)
        let fm = FileManager.default
        guard let walk = fm.enumerator(at: users, includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
                                       options: [.skipsPackageDescendants]) else { return [] }
        var found: [(Date, Dump)] = []
        for case let url as URL in walk where url.pathExtension.lowercased() == "dmp" {
            guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey]),
                  values.isRegularFile == true, let modified = values.contentModificationDate, modified >= since else { continue }
            let data = try? Data(contentsOf: url, options: .mappedIfSafe)
            found.append((modified, Dump(path: url.path, comment: data.flatMap(comment(ofMinidump:)))))
        }
        return found.sorted { $0.0 < $1.0 }.map(\.1)
    }

    static let commentStreamA: UInt32 = 10

    /// The ASCII comment a minidump carries (stream type 10), or nil if it has none or isn't one.
    ///
    /// The layout is `MINIDUMP_HEADER` (`MDMP`, version, stream count at 8, directory RVA at 12)
    /// followed by `MINIDUMP_DIRECTORY` entries of type, size and RVA, all little-endian.
    public static func comment(ofMinidump data: Data) -> String? {
        let bytes = [UInt8](data)
        func u32(_ offset: Int) -> UInt32? {
            guard offset >= 0, offset + 4 <= bytes.count else { return nil }
            return UInt32(bytes[offset]) | UInt32(bytes[offset + 1]) << 8
                | UInt32(bytes[offset + 2]) << 16 | UInt32(bytes[offset + 3]) << 24
        }
        guard bytes.count >= 32, bytes[0] == 0x4D, bytes[1] == 0x44, bytes[2] == 0x4D, bytes[3] == 0x50,
              let count = u32(8), let directory = u32(12), count < 4096 else { return nil }
        for index in 0..<Int(count) {
            let entry = Int(directory) + index * 12
            guard let type = u32(entry), let size = u32(entry + 4), let rva = u32(entry + 8) else { return nil }
            guard type == commentStreamA else { continue }
            let start = Int(rva), end = start + Int(size)
            guard start >= 0, end <= bytes.count, start < end else { return nil }
            var text = bytes[start..<end]
            while text.last == 0 { text = text.dropLast() }
            return String(decoding: text, as: UTF8.self)
        }
        return nil
    }
}
