import Foundation

/// Archive and disk-image helpers built on the system `tar`, `unzip`, and `hdiutil`.
public enum Archive {
    /// Extract a .tar.gz / .tar.xz / .tar into `directory`.
    public static func extractTar(_ archive: URL, to directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let result = Shell.run("/usr/bin/tar", ["-xf", archive.path, "-C", directory.path])
        guard result.succeeded else {
            throw CellarError.ioFailure("tar failed for \(archive.lastPathComponent): \(result.stderr)")
        }
    }

    /// Extract a .zip into `directory`.
    public static func unzip(_ archive: URL, to directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let result = Shell.run("/usr/bin/unzip", ["-q", "-o", archive.path, "-d", directory.path])
        guard result.succeeded else {
            throw CellarError.ioFailure("unzip failed for \(archive.lastPathComponent): \(result.stderr)")
        }
    }

    /// Mount a .dmg, hand the mount point to `body`, then always detach.
    @discardableResult
    public static func withMountedDMG<T>(_ dmg: URL, _ body: (URL) throws -> T) throws -> T {
        let attach = Shell.run("/usr/bin/hdiutil",
            ["attach", "-nobrowse", "-noverify", "-plist", dmg.path])
        guard attach.succeeded else {
            throw CellarError.ioFailure("hdiutil attach failed: \(attach.stderr)")
        }
        guard let mountPoint = parseMountPoint(attach.stdout) else {
            throw CellarError.ioFailure("Could not determine mount point for \(dmg.lastPathComponent)")
        }
        defer { Shell.run("/usr/bin/hdiutil", ["detach", "-quiet", mountPoint]) }
        return try body(URL(fileURLWithPath: mountPoint))
    }

    /// Parse the `mount-point` from `hdiutil attach -plist` output.
    private static func parseMountPoint(_ plist: String) -> String? {
        guard let data = plist.data(using: .utf8),
              let obj = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
              let dict = obj as? [String: Any],
              let entities = dict["system-entities"] as? [[String: Any]] else { return nil }
        for entity in entities {
            if let mountPoint = entity["mount-point"] as? String, !mountPoint.isEmpty {
                return mountPoint
            }
        }
        return nil
    }
}
