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

    /// The Windows executables that make up the client itself. `steamwebhelper.exe` is the CEF
    /// process that draws Steam's whole interface, and — verified with `lsappinfo` — the one that
    /// actually takes the Dock icon; `steam.exe` claims one too once it has shown a window. The
    /// rest are short-lived helpers Steam runs at startup. Used to keep the client out of the Dock
    /// while a game is starting (`DockShim`). The game is deliberately not on this list.
    public static let clientProcesses = [
        "steam.exe",
        "steamwebhelper.exe",
        "steamservice.exe",
        "steamsysinfo.exe",
        "steamerrorreporter.exe",
        "steamerrorreporter64.exe",
        "gldriverquery.exe",
        "gldriverquery64.exe",
        "vulkandriverquery.exe",
        "vulkandriverquery64.exe",
    ]

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

    // MARK: - One Steam, every bottle

    // A bottle is per-game on purpose: its own registry, its own runner, its own Wine version.
    // The *Steam install* is not per-game — it is the account's. Giving each bottle its own copy
    // meant a 1.4 GB download and a fresh sign-in for every game, and a game bought once being
    // downloaded twice. So the client lives in `Paths.sharedSteam` and each bottle gets a symlink
    // at the Windows path Steam expects. Every reader below (`loggedInAccount`, `isGameInstalled`,
    // the appmanifest lookups) resolves through that link unchanged, and because the Windows path
    // is identical in every bottle, Steam's own registry keys and `libraryfolders.vdf` stay valid.

    /// The one Steam install shared by every Steam bottle.
    public static var sharedInstall: URL { Paths.sharedSteam }

    /// Whether the shared install has a real client in it (not just an empty directory).
    public static var isSharedInstallPresent: Bool {
        FileManager.default.fileExists(atPath: sharedInstall.appendingPathComponent("steam.exe").path)
    }

    /// Whether this bottle already points at the shared install.
    public static func isLinkedToSharedInstall(in prefix: URL) -> Bool {
        let path = steamDirectory(in: prefix).path
        guard let type = try? FileManager.default.attributesOfItem(atPath: path)[.type] as? FileAttributeType,
              type == .typeSymbolicLink else { return false }
        return (try? FileManager.default.destinationOfSymbolicLink(atPath: path))
            .map { URL(fileURLWithPath: $0).standardizedFileURL == sharedInstall.standardizedFileURL } ?? false
    }

    /// Point this bottle's `C:\Program Files (x86)\Steam` at the shared install.
    ///
    /// A bottle that already holds a real Steam directory is *adopted*, never deleted: if the shared
    /// install doesn't exist yet this one is promoted into it (a same-volume rename, so a 36 GB
    /// library moves instantly), and otherwise it is moved aside so the player can reclaim the space
    /// deliberately. Cellar never removes a game download on its own.
    @discardableResult
    public static func linkIntoBottle(prefix: URL, progress: (String) -> Void = { _ in }) throws -> URL {
        let fm = FileManager.default
        if isLinkedToSharedInstall(in: prefix) { return sharedInstall }

        let bottlePath = steamDirectory(in: prefix)
        try fm.createDirectory(at: bottlePath.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.createDirectory(at: Paths.shared, withIntermediateDirectories: true)

        // A stale symlink (pointing somewhere else, or nowhere) is just replaced.
        let attrs = try? fm.attributesOfItem(atPath: bottlePath.path)
        let isSymlink = (attrs?[.type] as? FileAttributeType) == .typeSymbolicLink
        if isSymlink {
            try fm.removeItem(at: bottlePath)
        } else if fm.fileExists(atPath: bottlePath.path) {
            if !isSharedInstallPresent {
                progress("Promoting this bottle's Steam install to the shared one (no re-download, no re-sign-in)…")
                try fm.moveItem(at: bottlePath, to: sharedInstall)
            } else {
                let stamp = ISO8601DateFormatter.filenameSafe.string(from: Date())
                let aside = bottlePath.deletingLastPathComponent()
                    .appendingPathComponent("Steam.superseded-\(stamp)")
                progress("This bottle had its own Steam. Moving it aside — the shared install takes over.")
                try fm.moveItem(at: bottlePath, to: aside)
                progress("Old copy kept at \(aside.path) — delete it when you're happy: rm -rf '\(aside.path)'")
            }
        }

        if !fm.fileExists(atPath: sharedInstall.path) {
            try fm.createDirectory(at: sharedInstall, withIntermediateDirectories: true)
        }
        try fm.createSymbolicLink(at: bottlePath, withDestinationURL: sharedInstall)
        return sharedInstall
    }

    /// Migrate an existing installation to the shared layout: link every Steam bottle, promoting
    /// the richest existing install (a signed-in one first, then the largest) so the player keeps
    /// their sign-in and their downloads.
    ///
    /// Idempotent, and safe to run when there is nothing to do.
    @discardableResult
    public static func adoptSharedInstall(progress: (String) -> Void = { _ in }) throws -> Int {
        let fm = FileManager.default
        // Only Steam bottles: a Battle.net or GOG bottle has no business gaining a Steam symlink.
        // A bottle qualifies if a Steam profile points at it, or if it already holds a Steam install
        // (which covers a bottle whose profile has since been renamed or removed).
        let steamBottles = Game.bottleNames(forStore: .steam)
        let bottles = ((try? PrefixManager.list()) ?? [])
            .map(\.url)
            .filter { prefix in
                guard fm.fileExists(atPath: prefix.appendingPathComponent("system.reg").path) else { return false }
                return steamBottles.contains(prefix.lastPathComponent)
                    || hasOwnSteamInstall(in: prefix)
            }

        // Promote the richest existing install: a signed-in one first, then the largest. Ordering
        // matters because whichever comes first *becomes* the shared install; the rest move aside.
        // The signed-in test short-circuits, so the expensive size walk only runs on a genuine tie.
        let ordered = bottles.sorted { a, b in
            let signedIn = (loggedInAccount(in: a) != nil, loggedInAccount(in: b) != nil)
            if signedIn.0 != signedIn.1 { return signedIn.0 }
            let own = (hasOwnSteamInstall(in: a), hasOwnSteamInstall(in: b))
            if own.0 != own.1 { return own.0 }
            guard own.0 else { return false }
            return directorySize(steamDirectory(in: a)) > directorySize(steamDirectory(in: b))
        }

        var linked = 0
        for prefix in ordered {
            guard !isLinkedToSharedInstall(in: prefix) else { continue }
            progress("Bottle '\(prefix.lastPathComponent)': linking to the shared Steam install…")
            try linkIntoBottle(prefix: prefix, progress: progress)
            linked += 1
        }
        if let account = sharedLoggedInAccount {
            progress("Signed in as \(account) — every Steam game now uses this sign-in.")
        }
        return linked
    }

    /// Whether this bottle holds a Steam directory of its own — a real directory, not the shared
    /// symlink. `attributesOfItem` is deliberate: `fileExists` follows symlinks and would say yes
    /// for a bottle that is already linked.
    /// `hasOwnSteamInstall` for callers outside CellarKit (the doctor's "wasted space" line).
    public static func hasOwnSteamInstallForDiagnostics(in prefix: URL) -> Bool {
        hasOwnSteamInstall(in: prefix)
    }

    static func hasOwnSteamInstall(in prefix: URL) -> Bool {
        let path = steamDirectory(in: prefix).path
        guard let type = try? FileManager.default.attributesOfItem(atPath: path)[.type] as? FileAttributeType
        else { return false }
        return type == .typeDirectory
    }

    /// The account signed in to the shared install, read directly rather than through a bottle.
    public static var sharedLoggedInAccount: String? {
        accountName(inSteamDirectory: sharedInstall)
    }

    /// Rough on-disk size, used only to pick the richest install to promote. Cheap enough: it walks
    /// file sizes without reading contents, and only runs during a one-off migration.
    static func directorySize(_ url: URL) -> Int64 {
        guard let e = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey],
                                                     options: [.skipsHiddenFiles]) else { return 0 }
        var total: Int64 = 0
        for case let f as URL in e {
            total += Int64((try? f.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
        return total
    }

    /// The account logged into this bottle's Steam, if any (from loginusers.vdf).
    public static func loggedInAccount(in prefix: URL) -> String? {
        accountName(inSteamDirectory: steamDirectory(in: prefix))
    }

    /// Parse `loginusers.vdf` in a Steam directory. Split out from `loggedInAccount(in:)` so the
    /// shared install can be read without pretending to be a bottle.
    static func accountName(inSteamDirectory dir: URL) -> String? {
        let vdf = dir.appendingPathComponent("config/loginusers.vdf")
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
        // Link before installing: the bottle's Windows Steam path becomes the shared install, so the
        // installer writes straight into it and every later bottle finds a client already there.
        try linkIntoBottle(prefix: runner.prefix, progress: progress)

        if isSharedInstallPresent {
            if let account = sharedLoggedInAccount {
                progress("Using the Steam you already set up — signed in as \(account). Nothing to download.")
            } else {
                progress("Using the Steam you already set up. Nothing to download.")
            }
            return
        }
        let setup = Paths.cache.appendingPathComponent("SteamSetup.exe")
        var downloaded = false
        for url in installerURLs {
            let host = URL(string: url)?.host ?? url
            progress("Downloading Steam client (\(host))…")
            if (try? Downloader.fetch(url, to: setup)) != nil, WindowsInstaller.isPortableExecutable(setup) {
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
        guard isSharedInstallPresent else {
            throw CellarError.ioFailure(
                "SteamSetup.exe finished but steam.exe is missing from \(sharedInstall.path). Run: cellar steam share --repair")
        }
        progress("Steam installed — shared by every Steam game, so this is the only time it downloads.")
        progress("It fetches the full client (~1.4 GB) on first launch.")
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
    ///
    /// `dock` says whether this client is the thing the player asked for. Opening Steam to sign in
    /// is `.visible` — that window needs a Dock icon to come back to. Starting it to run a game is
    /// `.hidden`, so the Dock shows Cellar and the game and nothing else.
    public static func launchClient(runner: WineRunner, extraArgs: [String] = [], showHUD: Bool = false,
                                    gameEnv: [String: String] = [:],
                                    dock: DockPresence = .visible) throws {
        var extra = WineRunner.d3dMetalEnv(showHUD: showHUD)
        for (k, v) in gameEnv { extra[k] = v }
        if showHUD { extra["MTL_HUD_ENABLED"] = "1" }
        for (k, v) in DockShim.environment(for: .steam, dock: dock) { extra[k] = v }
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
                         showHUD: showHUD, gameEnv: gameEnv, dock: .hidden)
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
                                         gameEnv: [String: String] = [:], attempts: Int = 8,
                                         progress: (String) -> Void = { _ in }) throws {
        // Warm the client first: launching the game into a not-yet-ready Steam makes the D3DMetal
        // race fire almost every time. Start Steam silently (tray only) with the game's env, wait
        // for it to come up, then drive the game into the warm client.
        if !isRunning {
            progress("Starting Steam (silent) and waiting for it to be ready…")
            try launchClient(runner: runner, extraArgs: ["-silent"], showHUD: showHUD, gameEnv: gameEnv,
                             dock: .hidden)
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
                             showHUD: showHUD, gameEnv: gameEnv, dock: .hidden)

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

    /// Whether any process whose command line contains `needle` is running (case-insensitive).
    public static func isProcessRunning(_ needle: String) -> Bool {
        ProcessWatch.isRunning(needle)
    }

    /// Block until a process matching `needle` (e.g. the game's exe name) is gone. Waits for it to
    /// appear first, so we don't return before it has started.
    public static func waitForExit(matching needle: String) {
        ProcessWatch.waitToExit([needle])
    }

    /// Block until the game's process is gone (it has been quit), polling every few seconds.
    public static func waitForGameExit(in prefix: URL, appID: Int) {
        for _ in 0..<10 { if isGameRunning(in: prefix, appID: appID) { break }; Thread.sleep(forTimeInterval: 1) }
        while isGameRunning(in: prefix, appID: appID) { Thread.sleep(forTimeInterval: 3) }
    }

    /// Shut the whole bottle down: ask Steam to exit, then stop wineserver so nothing lingers.
    /// This is what makes "quit the game → the Steam layer closes too".
    public static func shutdown(runner: WineRunner) {
        if isRunning {
            runner.runExecutable(steamExecutable(in: runner.prefix).path, args: ["-shutdown"], inheritIO: false)
            for _ in 0..<15 { if !isRunning { break }; Thread.sleep(forTimeInterval: 2) }
        }
        runner.killServer()
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

extension ISO8601DateFormatter {
    /// `2026-09-08T121314Z` — safe in a filename (no colons, which Finder shows as slashes).
    static let filenameSafe: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withYear, .withMonth, .withDay, .withTime, .withTimeZone, .withDashSeparatorInDate]
        return f
    }()
}
