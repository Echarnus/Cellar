import Foundation

/// Canonical on-disk locations for Cellar's state.
/// Everything lives under ~/Library/Application Support/Cellar.
public enum Paths {
    public static var appSupport: URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
        return base.appendingPathComponent("Cellar", isDirectory: true)
    }

    /// Installed Wine runners (LGPL Wine builds Cellar runs games through).
    public static var runners: URL { appSupport.appendingPathComponent("runners", isDirectory: true) }

    /// Per-game bottles (isolated WINEPREFIX + bottle.toml).
    public static var prefixes: URL { appSupport.appendingPathComponent("prefixes", isDirectory: true) }

    /// Downloads and extracted artifacts.
    public static var cache: URL { appSupport.appendingPathComponent("cache", isDirectory: true) }

    /// Run logs / diagnostics.
    public static var logs: URL { appSupport.appendingPathComponent("logs", isDirectory: true) }

    /// User-installed game profiles (synced from the community registry in Phase 2).
    public static var userProfiles: URL { appSupport.appendingPathComponent("profiles", isDirectory: true) }

    /// Where the user-supplied Apple D3DMetal framework is copied to (never bundled/redistributed).
    public static var d3dmetalCache: URL { cache.appendingPathComponent("d3dmetal", isDirectory: true) }

    public static func ensureBaseDirectories() throws {
        for dir in [appSupport, runners, prefixes, cache, logs, userProfiles] {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    /// Search order for the profiles shipped with the repo/binary, plus user/registry profiles.
    public static var profileSearchPaths: [URL] {
        var paths: [URL] = []
        if let env = ProcessInfo.processInfo.environment["CELLAR_PROFILES_DIR"], !env.isEmpty {
            paths.append(URL(fileURLWithPath: env, isDirectory: true))
        }
        paths.append(userProfiles)
        // Repo-relative — supports `swift run cellar ...` from the project root during development.
        paths.append(URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("profiles", isDirectory: true))
        return paths
    }
}
