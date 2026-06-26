import Foundation

/// Installs and drives the *Windows* Steam client inside a Wine bottle — the robust way to install
/// and play Windows-only games (like Planet Coaster 2) that the macOS Steam client refuses to install.
public enum SteamBottle {
    /// Valve's unversioned installer (self-updates on first launch). Mirrors in priority order.
    static let installerURLs = [
        "https://cdn.cloudflare.steamstatic.com/client/installer/SteamSetup.exe",
        "https://cdn.fastly.steamstatic.com/client/installer/SteamSetup.exe",
        "https://cdn.akamai.steamstatic.com/client/installer/SteamSetup.exe",
    ]

    /// The load-bearing macOS/Wine launch flags: Steam's CEF web helper must be forced to 32-bit,
    /// and Chromium's sandbox is incompatible with Wine.
    static let launchFlags = [
        "-allosarches", "-cef-force-32bit", "-no-cef-sandbox",
        "-cef-disable-gpu", "-noverifyfiles", "-tcp",
    ]

    public static func steamExecutable(in prefix: URL) -> URL {
        prefix.appendingPathComponent("drive_c/Program Files (x86)/Steam/steam.exe")
    }

    static func steamDirectory(in prefix: URL) -> URL {
        prefix.appendingPathComponent("drive_c/Program Files (x86)/Steam")
    }

    public static func isInstalled(in prefix: URL) -> Bool {
        FileManager.default.fileExists(atPath: steamExecutable(in: prefix).path)
    }

    /// Download SteamSetup.exe and silently install it into the bottle.
    public static func install(runner: WineRunner, progress: (String) -> Void = { _ in }) throws {
        if isInstalled(in: runner.prefix) {
            progress("Windows Steam already installed in this bottle.")
            return
        }
        let setup = Paths.cache.appendingPathComponent("SteamSetup.exe")
        var downloaded = false
        for url in installerURLs {
            let host = URL(string: url)?.host ?? url
            progress("Downloading Steam client (\(host))…")
            if (try? Downloader.fetch(url, to: setup)) != nil, isPE(setup) {
                downloaded = true
                break
            }
        }
        guard downloaded else {
            throw CellarError.ioFailure("Could not download a valid SteamSetup.exe from any Steam CDN.")
        }

        progress("Installing Windows Steam into the bottle (silent)…")
        runner.runExecutable(setup.path, args: ["/S"], inheritIO: true)

        // Pin the client so a bad self-update can't break CEF under Wine.
        pinClientUpdates(in: runner.prefix)
        progress("Steam installed. It will finish self-updating on first launch.")
    }

    /// Write steam.cfg so the bootstrapper doesn't self-update into a Wine-incompatible client.
    public static func pinClientUpdates(in prefix: URL) {
        let dir = steamDirectory(in: prefix)
        guard FileManager.default.fileExists(atPath: dir.path) else { return }
        try? "BootStrapperInhibitAll=Enable\n".write(
            to: dir.appendingPathComponent("steam.cfg"), atomically: true, encoding: .utf8)
    }

    /// Launch the in-bottle Steam client (for login / installing games via its UI).
    public static func launchClient(runner: WineRunner, extraArgs: [String] = []) {
        runner.runExecutable(steamExecutable(in: runner.prefix).path,
                             args: launchFlags + extraArgs,
                             extraEnv: ["MTL_HUD_ENABLED": "0"], inheritIO: true)
    }

    /// Open the install dialog for a specific app id inside the bottle's Steam.
    public static func installGame(runner: WineRunner, appID: Int) {
        runner.runExecutable(steamExecutable(in: runner.prefix).path,
                             args: launchFlags + ["steam://install/\(appID)"], inheritIO: true)
    }

    /// Launch an installed game through Steam (handles auth + DRM + overlay), with D3DMetal env.
    public static func runGame(runner: WineRunner, appID: Int, showHUD: Bool = false) {
        runner.runExecutable(steamExecutable(in: runner.prefix).path,
                             args: launchFlags + ["steam://rungameid/\(appID)"],
                             extraEnv: WineRunner.d3dMetalEnv(showHUD: showHUD), inheritIO: true)
    }

    /// Whether a given app id reports as fully installed (StateFlags=4) in its appmanifest.
    public static func isGameInstalled(in prefix: URL, appID: Int) -> Bool {
        let manifest = steamDirectory(in: prefix)
            .appendingPathComponent("steamapps/appmanifest_\(appID).acf")
        guard let text = try? String(contentsOf: manifest, encoding: .utf8) else { return false }
        // StateFlags 4 == fully installed.
        return text.range(of: #""StateFlags"\s*"4""#, options: .regularExpression) != nil
    }

    private static func isPE(_ file: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: file) else { return false }
        defer { try? handle.close() }
        let magic = handle.readData(ofLength: 2)
        return magic == Data([0x4D, 0x5A]) // "MZ"
    }
}

/// The kaon `steam_dev.cfg` trick: force the *native* macOS Steam client to show Install/Play for
/// Windows-only games. Advanced/opt-in only — it blocks Steam's self-update and can empty games
/// that have a macOS depot. The non-Steam-shortcut path (SteamShortcuts) is preferred.
public enum SteamPlatformTrick {
    public static var cfgPath: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Steam/Steam.AppBundle/Steam/Contents/MacOS/steam_dev.cfg")
    }

    public static var isEnabled: Bool {
        FileManager.default.fileExists(atPath: cfgPath.path)
    }

    public static func enable() throws {
        try FileManager.default.createDirectory(
            at: cfgPath.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "@sSteamCmdForcePlatformType windows\n".write(to: cfgPath, atomically: true, encoding: .utf8)
    }

    public static func disable() throws {
        if FileManager.default.fileExists(atPath: cfgPath.path) {
            try FileManager.default.removeItem(at: cfgPath)
        }
    }
}
