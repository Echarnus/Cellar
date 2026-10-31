import CellarDomain
import Foundation

/// Files that hold a credential, or say whose account this is, kept readable by the player alone.
///
/// Not everything secret can live in the keychain: DepotDownloader keeps Steam's refresh token in
/// its own `account.config`, and the Windows Steam client in a bottle keeps its "Remember me" blob in
/// `local.vdf`, because those are the formats those programs read. Cellar cannot change where they
/// look, so it changes who else can: `0600` for the file, `0700` for a directory Cellar owns, and —
/// for a file that is a credential — out of Time Machine, for the same reason the keychain item is
/// `ThisDeviceOnly`: a backup restored onto another Mac should not arrive signed in.
///
/// Every function here is best-effort and silent. Tightening a mode must never be the reason a
/// sign-in, a download or a launch fails.
public enum PrivateFiles {
    public static let fileMode: Int16 = 0o600
    public static let directoryMode: Int16 = 0o700

    /// `0600` on a file. Holds whatever is in it; reading it is the player's business alone.
    public static func restrict(file url: URL) {
        try? FileManager.default.setAttributes([.posixPermissions: NSNumber(value: fileMode)],
                                               ofItemAtPath: url.path)
    }

    /// `0700` on a directory Cellar owns. Never used on a directory another program shares
    /// (isolated storage is every .NET program's), where only the file is Cellar's to tighten.
    public static func restrict(directory url: URL) {
        try? FileManager.default.setAttributes([.posixPermissions: NSNumber(value: directoryMode)],
                                               ofItemAtPath: url.path)
    }

    /// `0600` and out of backups: for a file that is itself a credential.
    public static func protectCredential(_ url: URL) {
        restrict(file: url)
        excludeFromBackup(url)
    }

    public static func excludeFromBackup(_ url: URL) {
        var url = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
    }

    /// Write `data` so that nobody else can read it at any point — created `0600` and then filled,
    /// rather than written with the default mode and tightened afterwards. Atomic: the old file is
    /// replaced in one step, so a crash leaves the old contents or the new, never half of either.
    public static func write(_ data: Data, to url: URL) throws {
        let fm = FileManager.default
        let directory = url.deletingLastPathComponent()
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        let staging = directory.appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString)")
        guard fm.createFile(atPath: staging.path, contents: nil,
                            attributes: [.posixPermissions: NSNumber(value: fileMode)]) else {
            throw CellarError.ioFailure("Could not write \(url.lastPathComponent).")
        }
        do {
            let handle = try FileHandle(forWritingTo: staging)
            try handle.write(contentsOf: data)
            try handle.close()
            if fm.fileExists(atPath: url.path) {
                _ = try fm.replaceItemAt(url, withItemAt: staging)
            } else {
                try fm.moveItem(at: staging, to: url)
            }
        } catch {
            try? fm.removeItem(at: staging)
            throw error
        }
        restrict(file: url)
    }

    /// The permission bits of `url`, for a test or a diagnosis. Nil when it does not exist.
    public static func mode(of url: URL) -> Int16? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.posixPermissions]
            .flatMap { ($0 as? NSNumber)?.int16Value }
    }

    public static func isExcludedFromBackup(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isExcludedFromBackupKey]))?.isExcludedFromBackup ?? false
    }
}
