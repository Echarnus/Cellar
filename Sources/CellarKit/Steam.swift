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

    /// Launch flags. Deliberately empty: on Wine 10 the current client needs none, and the
    /// `-allosarches -cef-force-32bit -no-cef-sandbox` folklore is a no-op (the 64-bit CEF is used
    /// regardless — verified in webhelper.txt) or actively harmful.
    static let launchFlags: [String] = []

    public static func steamExecutable(in prefix: URL) -> URL {
        prefix.appendingPathComponent("drive_c/Program Files (x86)/Steam/steam.exe")
    }

    public static func steamDirectory(in prefix: URL) -> URL {
        prefix.appendingPathComponent("drive_c/Program Files (x86)/Steam")
    }

    /// Steam's own logs: bootstrap_log.txt, webhelper.txt, connection_log.txt, cef_log.txt…
    public static func logsDirectory(in prefix: URL) -> URL {
        steamDirectory(in: prefix).appendingPathComponent("logs")
    }

    public static func isInstalled(in prefix: URL) -> Bool {
        FileManager.default.fileExists(atPath: steamExecutable(in: prefix).path)
    }

    /// Whether the client has completed its first self-update (the installer only drops a ~9 MB
    /// bootstrapper; a real client has `steamclient64.dll`).
    public static func isClientUpdated(in prefix: URL) -> Bool {
        FileManager.default.fileExists(
            atPath: steamDirectory(in: prefix).appendingPathComponent("steamclient64.dll").path)
    }

    /// The account logged into this bottle's Steam, if any (from loginusers.vdf).
    public static func loggedInAccount(in prefix: URL) -> String? {
        let vdf = steamDirectory(in: prefix).appendingPathComponent("config/loginusers.vdf")
        guard let text = try? String(contentsOf: vdf, encoding: .utf8) else { return nil }
        let pattern = #""AccountName"\s*"([^"]+)""#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range])
    }

    /// Whether a Windows Steam client is running (in any bottle: Wine reports the Windows command
    /// line, which doesn't carry the prefix).
    public static var isRunning: Bool {
        Shell.run("/bin/sh", ["-c", "ps -axo command | grep -qi '[s]team\\.exe'"], environment: [:]).succeeded
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
        runner.waitForServer()
        guard isInstalled(in: runner.prefix) else {
            throw CellarError.ioFailure("SteamSetup.exe finished but steam.exe is missing from the bottle.")
        }
        progress("Steam installed. It downloads the full client (~1.4 GB) on first launch.")
    }

    /// Write steam.cfg so the bootstrapper stops self-updating. Only valid AFTER the first update:
    /// an inhibited bootstrapper with no client files exits after two seconds. Opt-in.
    public static func pinClientUpdates(in prefix: URL) {
        guard isClientUpdated(in: prefix) else { return }
        try? "BootStrapperInhibitAll=Enable\n".write(
            to: steamDirectory(in: prefix).appendingPathComponent("steam.cfg"), atomically: true, encoding: .utf8)
    }

    public static func unpinClientUpdates(in prefix: URL) {
        try? FileManager.default.removeItem(
            at: steamDirectory(in: prefix).appendingPathComponent("steam.cfg"))
    }

    /// Launch the in-bottle Steam client detached (for login / installing games via its UI).
    /// If a client is already up in the bottle, Steam hands the arguments (e.g. a steam:// URL) to it.
    public static func launchClient(runner: WineRunner, extraArgs: [String] = [], showHUD: Bool = false,
                                    gameEnv: [String: String] = [:]) throws {
        var extra = WineRunner.d3dMetalEnv(showHUD: showHUD)
        for (k, v) in gameEnv { extra[k] = v }
        if showHUD { extra["MTL_HUD_ENABLED"] = "1" }
        try runner.spawn([steamExecutable(in: runner.prefix).path] + launchFlags + extraArgs,
                         extraEnv: extra,
                         log: Paths.logs.appendingPathComponent("steam-\(runner.prefix.lastPathComponent).log"))
    }

    /// Open the install dialog for a specific app id inside the bottle's Steam.
    public static func installGame(runner: WineRunner, appID: Int) throws {
        try launchClient(runner: runner, extraArgs: ["steam://install/\(appID)"])
    }

    /// Launch an installed game through Steam (handles auth + DRM + overlay), with D3DMetal env.
    /// Steam is the parent of the game process, so the environment must be on Steam itself: if a
    /// client without the HUD/DXR env is already running, those settings apply after it restarts.
    ///
    /// `-silent` cold-starts the client straight to the tray — no main window, friends list or
    /// store popups — so on a fresh launch only the game's own window appears. (If a client is
    /// already up in the bottle, Steam just forwards the URL to it and the flag is a no-op.)
    public static func runGame(runner: WineRunner, appID: Int, showHUD: Bool = false,
                               gameEnv: [String: String] = [:]) throws {
        try launchClient(runner: runner, extraArgs: ["-silent", "steam://rungameid/\(appID)"],
                         showHUD: showHUD, gameEnv: gameEnv)
    }

    /// The game's install-directory name (from `appmanifest_<appid>.acf`'s `installdir`).
    public static func installDirectory(in prefix: URL, appID: Int) -> String? {
        let manifest = steamDirectory(in: prefix).appendingPathComponent("steamapps/appmanifest_\(appID).acf")
        guard let text = try? String(contentsOf: manifest, encoding: .utf8),
              let m = text.range(of: #""installdir"\s*"([^"]+)""#, options: .regularExpression) else { return nil }
        return String(text[m]).components(separatedBy: "\"").dropLast().last
    }

    /// Whether the game's own process (not Steam) is currently running in this bottle — matched by
    /// its install-directory path in the Windows command line.
    public static func isGameRunning(in prefix: URL, appID: Int) -> Bool {
        guard let dir = installDirectory(in: prefix, appID: appID) else { return false }
        let needle = "steamapps\\\\common\\\\\(dir)\\\\"
        return Shell.run("/bin/sh", ["-c",
            "ps -axo command | grep -vi grep | grep -qiF \"\(needle)\""]).succeeded
            || Shell.run("/bin/sh", ["-c",
            "ps -axo command | grep -vi grep | grep -qiF \"common/\(dir)/\""]).succeeded
    }

    /// Launch the game and supervise startup: D3DMetal 3.0 has an intermittent race that fast-fails
    /// the game ~5 s in (0xC0000409) before its window appears. Relaunch transparently until the
    /// game is up, so "launch and play" just works. Steam stays running between attempts (started
    /// once, silently), so retries are cheap.
    public static func runGameSupervised(runner: WineRunner, appID: Int, showHUD: Bool = false,
                                         gameEnv: [String: String] = [:], attempts: Int = 5,
                                         progress: (String) -> Void = { _ in }) throws {
        // Warm the client first: launching the game into a not-yet-ready Steam makes the D3DMetal
        // race fire almost every time. Start Steam silently (tray only) with the game's env, wait
        // for it to come up, then drive the game into the warm client.
        if !isRunning {
            progress("Starting Steam (silent) and waiting for it to be ready…")
            try launchClient(runner: runner, extraArgs: ["-silent"], showHUD: showHUD, gameEnv: gameEnv)
            for _ in 0..<20 {
                Thread.sleep(forTimeInterval: 2)
                if isRunning && isClientUpdated(in: runner.prefix) { break }
            }
            Thread.sleep(forTimeInterval: 6) // let login settle
        }

        for attempt in 1...attempts {
            // Clean slate: kill any half-dead game / crash-reporter from a previous attempt and let
            // wineserver settle, or the next rungameid races even harder.
            killGameProcesses(in: runner.prefix, appID: appID)
            if attempt > 1 { Thread.sleep(forTimeInterval: 8) }

            try launchClient(runner: runner, extraArgs: ["steam://rungameid/\(appID)"],
                             showHUD: showHUD, gameEnv: gameEnv)

            // Wait up to ~24 s for the game process to appear.
            var appeared = false
            for _ in 0..<12 {
                Thread.sleep(forTimeInterval: 2)
                if isGameRunning(in: runner.prefix, appID: appID) { appeared = true; break }
            }
            if !appeared {
                progress("Attempt \(attempt): game didn't start; retrying…")
                continue
            }
            // It started — did it survive the startup race? Watch for ~16 s.
            var survived = true
            for _ in 0..<8 {
                Thread.sleep(forTimeInterval: 2)
                if !isGameRunning(in: runner.prefix, appID: appID) { survived = false; break }
            }
            if survived {
                if attempt > 1 { progress("Up after \(attempt) attempts.") }
                return
            }
            progress("Attempt \(attempt): hit the D3DMetal startup race; cleaning up and retrying…")
        }
        throw CellarError.ioFailure(
            "Planet Coaster 2 kept hitting the D3DMetal startup race after \(attempts) attempts. Try `cellar launch` again.")
    }

    /// Kill the game's own process and its crash reporter in this bottle (not Steam itself), so a
    /// stuck instance from a failed startup doesn't poison the next attempt.
    public static func killGameProcesses(in prefix: URL, appID: Int) {
        var patterns = ["crash_reporter.exe"]
        if let dir = installDirectory(in: prefix, appID: appID) { patterns.append("common/\(dir)/") }
        for p in patterns {
            Shell.run("/usr/bin/pkill", ["-9", "-f", p])
        }
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
