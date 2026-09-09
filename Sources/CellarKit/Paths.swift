import Foundation

/// Canonical on-disk locations for Cellar's state.
/// Everything lives under ~/Library/Application Support/Cellar.
public enum Paths {
    /// The root of everything Cellar owns on disk.
    ///
    /// `CELLAR_HOME` relocates it wholesale. That exists so a test run — or a second, throwaway
    /// installation — can create bottles, install runners and write logs without touching the
    /// player's real library. Nothing else in Cellar reads the environment for a path; if it needs
    /// a location, it derives it from here.
    public static var appSupport: URL {
        if let override = ProcessInfo.processInfo.environment["CELLAR_HOME"], !override.isEmpty {
            return URL(fileURLWithPath: (override as NSString).expandingTildeInPath, isDirectory: true)
        }
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

    /// State that belongs to a *store account* rather than to any one game: the single Windows
    /// Steam install every Steam bottle links to, downloaded installers, cached library metadata.
    ///
    /// This is the difference between signing in once and signing in per game. A bottle stays
    /// per-game (its own registry, runner and Wine version — that isolation is the whole point),
    /// but the store client and its library are the *account's*, not the game's, so they live here
    /// and are symlinked into each bottle at the Windows path the client expects.
    public static var shared: URL { appSupport.appendingPathComponent("shared", isDirectory: true) }

    /// The one Windows Steam install, shared by every Steam bottle. Holds `config/loginusers.vdf`
    /// (the sign-in) and `steamapps/` (the games), so both are downloaded and authenticated once.
    public static var sharedSteam: URL { shared.appendingPathComponent("steam", isDirectory: true) }


    /// Run logs / diagnostics.
    public static var logs: URL { appSupport.appendingPathComponent("logs", isDirectory: true) }

    /// User-installed game profiles (synced from the community registry in Phase 2).
    public static var userProfiles: URL { appSupport.appendingPathComponent("profiles", isDirectory: true) }

    /// Where the user-supplied Apple D3DMetal framework is copied to (never bundled/redistributed).
    public static var d3dmetalCache: URL { cache.appendingPathComponent("d3dmetal", isDirectory: true) }

    public static func ensureBaseDirectories() throws {
        for dir in [appSupport, runners, prefixes, cache, logs, userProfiles, shared] {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    /// Search order for profiles. First match by slug wins, so the list runs from most specific to
    /// most general: an explicit override, then the player's own edits, then the working directory
    /// during development, then the database shipped beside the binary.
    public static var profileSearchPaths: [URL] {
        var paths: [URL] = []
        if let env = ProcessInfo.processInfo.environment["CELLAR_PROFILES_DIR"], !env.isEmpty {
            paths.append(URL(fileURLWithPath: env, isDirectory: true))
        }
        paths.append(userProfiles)
        // Repo-relative — supports `swift run cellar ...` from the project root during development.
        paths.append(URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("profiles", isDirectory: true))
        paths.append(contentsOf: bundledProfiles)
        return paths
    }

    /// The profile database that ships with an installed Cellar, so the app and an installed CLI
    /// know about a game without the player having to copy TOML files around. Searched *last*:
    /// anything the player has put in `userProfiles` deliberately outranks what Cellar shipped.
    public static var bundledProfiles: [URL] {
        var paths: [URL] = []
        // Cellar.app/Contents/Resources/profiles
        if let resources = Bundle.main.resourceURL {
            paths.append(resources.appendingPathComponent("profiles", isDirectory: true))
        }
        // A CLI installed to <prefix>/bin/cellar keeps its database at <prefix>/share/cellar/profiles.
        if let argv0 = ProcessInfo.processInfo.arguments.first {
            let binDir = URL(fileURLWithPath: argv0).resolvingSymlinksInPath().deletingLastPathComponent()
            paths.append(binDir.appendingPathComponent("../share/cellar/profiles").standardizedFileURL)
        }
        return paths
    }
}
