import CellarDomain
import Foundation

/// Sizes on disk, and how to say them to a person.
public enum ByteSize {
    /// Bytes used by a file or, recursively, a directory. Symlinks are counted as themselves and
    /// never followed — the bottle's Steam link points at every other Steam game.
    public static func of(_ url: URL) -> Int64 {
        let fm = FileManager.default
        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return 0 }
        if Uninstall.isSymbolicLink(url) { return 0 }
        if !isDirectory.boolValue {
            let size = (try? fm.attributesOfItem(atPath: url.path))?[.size] as? NSNumber
            return size?.int64Value ?? 0
        }
        // Hidden files are counted: a Wine prefix and a Steam library are full of them, and a total
        // that quietly omits them would understate what the player is about to free.
        guard let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .isRegularFileKey],
                                             options: []) else { return 0 }
        var total: Int64 = 0
        for case let file as URL in enumerator {
            let values = try? file.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .isRegularFileKey])
            guard values?.isRegularFile == true else { continue }
            total += Int64(values?.totalFileAllocatedSize ?? 0)
        }
        return total
    }

    /// "12.4 GB". Human units, because nobody decides anything from 13 314 398 208.
    public static func describe(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useKB, .useMB, .useGB, .useTB]
        // Without this an empty directory reads "Zero KB", which looks like a bug in the tally.
        formatter.allowsNonnumericFormatting = false
        return formatter.string(fromByteCount: bytes)
    }
}
