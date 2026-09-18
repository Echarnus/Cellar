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
    /// bootstrapper). See `SteamClientUpdate.isComplete` for why that is not `steamclient64.dll`.
    public static func isClientUpdated(in prefix: URL) -> Bool {
        SteamClientUpdate.isComplete(inSteamDirectory: steamDirectory(in: prefix))
    }

    /// Bring a bootstrapper-only install up to a real client, with Steam's own update window kept
    /// off screen and its progress handed to `fraction` instead. A no-op once it has been done.
    public static func updateClient(runner: WineRunner, progress: (String) -> Void = { _ in },
                                    fraction: (Double?) -> Void = { _ in }) throws {
        guard isInstalled(in: runner.prefix), !isClientUpdated(in: runner.prefix) else { return }
        try SteamClientUpdate.run(runner: runner, steamDirectory: steamDirectory(in: runner.prefix),
                                  fraction: fraction, progress: progress)
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
                                         game: String = "the game", expectsSignIn: Bool = false,
                                         progress: (String) -> Void = { _ in },
                                         stage: (LaunchStage) -> Void = { _ in }) throws {
        // Warm the client first: launching the game into a not-yet-ready Steam makes the D3DMetal
        // race fire almost every time. Start Steam silently (tray only) with the game's env, wait
        // for it to come up, then drive the game into the warm client.
        if !isRunning {
            stage(.client)
            progress("Starting Steam (silent) and waiting for it to be ready…")
            let mark = connectionLogMark(in: runner.prefix)
            try launchClient(runner: runner, extraArgs: ["-silent"], showHUD: showHUD, gameEnv: gameEnv,
                             dock: .hidden)
            for _ in 0..<20 {
                Thread.sleep(forTimeInterval: 2)
                if isRunning && isClientUpdated(in: runner.prefix) { break }
            }
            if expectsSignIn {
                try waitForClientLogon(runner: runner, since: mark, game: game, showHUD: showHUD,
                                       gameEnv: gameEnv, progress: progress, stage: stage)
            }
            Thread.sleep(forTimeInterval: 6) // let login settle
        }

        for attempt in 1...attempts {
            // Clean slate: kill any half-dead game / crash-reporter from a previous attempt and let
            // wineserver settle, or the next rungameid races even harder.
            killGameProcesses(in: runner.prefix, appID: appID)
            if attempt > 1 { Thread.sleep(forTimeInterval: 8) }

            stage(.starting)
            try launchClient(runner: runner, extraArgs: ["steam://rungameid/\(appID)"],
                             showHUD: showHUD, gameEnv: gameEnv, dock: .hidden)
            stage(.waiting)

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

    /// Whether the **client's own copy** of an app is really installed in this bottle.
    ///
    /// An appmanifest is Steam's claim, not proof, and a claim Cellar must not take at face value:
    /// a client that has just signed in writes a manifest saying `StateFlags "4"` for a game whose
    /// files it does not have, and believing it sent the launch down `steam://rungameid`, where
    /// Steam answered with its 33 GB install dialog for a game already on the disk. So the files
    /// are checked too — `steamapps/common/<installdir>` has to exist and hold something.
    public static func isGameInstalled(in prefix: URL, appID: Int) -> Bool {
        let manifest = steamDirectory(in: prefix)
            .appendingPathComponent("steamapps/appmanifest_\(appID).acf")
        guard let text = try? String(contentsOf: manifest, encoding: .utf8),
              text.range(of: #""StateFlags"\s*"4""#, options: .regularExpression) != nil,
              let directory = installDirectory(in: prefix, appID: appID)
        else { return false }
        return hasFiles(steamDirectory(in: prefix).appendingPathComponent("steamapps/common/\(directory)"))
    }

    /// Whether a directory exists and is not empty. A manifest for an empty folder is a claim about
    /// nothing.
    static func hasFiles(_ directory: URL) -> Bool {
        let contents = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return contents.contains { $0 != ".DS_Store" }
    }
}

/// Telling a Steamworks game which app it is when Cellar, not Steam, started it.
///
/// This is not a DRM workaround and does not weaken one. `steam_appid.txt` is Valve's own developer
/// file: `steam_api` reads it to learn the app id, then talks to the **running, signed-in** Steam
/// client, which must hold a licence for that app or the game refuses to start. Cellar downloads
/// games with the player's own credentials and runs their DRM untouched (docs/LEGAL.md).
public enum SteamDRM {
    /// Drop `steam_appid.txt` beside a downloaded game so it can find the live session.
    public static func markAppDirectory(_ directory: URL, appID: Int) {
        try? "\(appID)\n".write(to: directory.appendingPathComponent("steam_appid.txt"),
                                atomically: true, encoding: .utf8)
    }
}

public extension SteamBottle {
    /// Launch a game Cellar downloaded itself, with the Steam client up beside it for its DRM.
    ///
    /// Steam has no appmanifest for this copy, so `steam://rungameid` would find nothing. Bringing
    /// the client up silently first and then starting the exe gives a Steamworks or Denuvo title
    /// exactly what it asks for — a live session belonging to an account that owns the game — while
    /// keeping the download path free of the client's install dialog.
    static func launchAlongside(runner: WineRunner, exe: URL, appID: Int, showHUD: Bool = false,
                                gameEnv: [String: String] = [:],
                                game: String = "the game", expectsSignIn: Bool = false,
                                attempts: Int = 8,
                                progress: (String) -> Void = { _ in },
                                stage: (LaunchStage) -> Void = { _ in }) throws {
        SteamDRM.markAppDirectory(exe.deletingLastPathComponent(), appID: appID)
        if !isRunning {
            stage(.client)
            progress("Starting Steam (silent) and waiting for it to be ready…")
            let mark = connectionLogMark(in: runner.prefix)
            try launchClient(runner: runner, extraArgs: ["-silent"], showHUD: showHUD, gameEnv: gameEnv)
            for _ in 0..<20 {
                Thread.sleep(forTimeInterval: 2)
                if isRunning && isClientUpdated(in: runner.prefix) { break }
            }
            if expectsSignIn {
                try waitForClientLogon(runner: runner, since: mark, game: game, showHUD: showHUD,
                                       gameEnv: gameEnv, progress: progress, stage: stage)
            }
            Thread.sleep(forTimeInterval: 6)   // let the sign-in settle before the game asks
        }
        var env = WineRunner.d3dMetalEnv(showHUD: showHUD)
        for (key, value) in gameEnv { env[key] = value }
        // What steam_api looks at when a game was not started by the client.
        env["SteamAppId"] = "\(appID)"
        env["SteamGameId"] = "\(appID)"
        let log = Paths.logs.appendingPathComponent("game-\(exe.deletingPathExtension().lastPathComponent).log")

        // The same supervision `runGameSupervised` gives the client's own route: D3DMetal 3.0 drops a
        // game a few seconds in, and without a retry a single Play ended with a dead game and a
        // crash reporter. Reported as attempts, because a launch that took three tries is not a
        // launch that took one.
        stage(.starting)
        for attempt in 1...attempts {
            if attempt > 1 {
                ProcessWatch.kill([exe.lastPathComponent, "crash_reporter.exe"])
                Thread.sleep(forTimeInterval: 8)
                progress("Attempt \(attempt): starting \(exe.lastPathComponent) again…")
            } else {
                progress("Launching \(exe.lastPathComponent)…")
            }
            try runner.spawn([exe.path], extraEnv: env, log: log)
            stage(.waiting)
            guard ProcessWatch.waitToAppear([exe.lastPathComponent], seconds: 40) else {
                progress("Attempt \(attempt): \(exe.lastPathComponent) didn't start; retrying…")
                continue
            }
            // Did it survive the startup race? ~16 s is where D3DMetal drops it.
            var survived = true
            for _ in 0..<8 {
                Thread.sleep(forTimeInterval: 2)
                if !ProcessWatch.isRunning(exe.lastPathComponent) { survived = false; break }
            }
            if survived {
                if attempt > 1 { progress("Up after \(attempt) attempts.") }
                return
            }
            progress("Attempt \(attempt): hit the D3DMetal startup race; cleaning up and retrying…")
        }
        throw CellarError.ioFailure(
            "\(game) kept stopping within seconds of starting, \(attempts) times — the D3DMetal startup race. Press Play again, and see the activity log for the game's own output.")
    }
}

public extension SteamBottle {
    // MARK: - The client signs in with Cellar's session

    /// Whether this bottle's Steam will sign in by itself — see `SteamClientSession`.
    static func clientSessionReadiness(in prefix: URL) -> SteamClientSession.Readiness {
        SteamClientSession.readiness(SteamClientSession.snapshot(
            prefix: prefix, steamDirectory: steamDirectory(in: prefix), wineUser: wineUser))
    }

    /// The Wine user the bottle runs as. `WineRunner.environment` inherits `USER` from Cellar's own
    /// process, so this is the name the client's `CryptProtectData` will be keyed with.
    internal static var wineUser: String {
        SteamClientSession.wineUser(environment: ProcessInfo.processInfo.environment)
    }

    /// Hand the bottle's client the session the player approved in Cellar, so it starts signed in
    /// instead of opening its login window. Only before the client starts — a running client
    /// rewrites these files — and never over an account somebody signed in to by hand.
    ///
    /// `.canHandOver` means it was handed over this time; `.remembered` that nothing was needed.
    @discardableResult
    static func handOverSession(runner: WineRunner, progress: (String) -> Void = { _ in }) -> SteamClientSession.Readiness {
        let prefix = runner.prefix
        let readiness = clientSessionReadiness(in: prefix)
        guard readiness == .canHandOver else { return readiness }
        guard !isRunning else { return .unavailable(.clientRunning) }
        let result = SteamClientSession.handOver(prefix: prefix, steamDirectory: steamDirectory(in: prefix),
                                                 wineUser: wineUser)
        guard result == .canHandOver, let account = SteamAccount.state.accountName else { return result }
        setAutoLogin(account: account, runner: runner)
        progress("Signing Steam in with the account you gave Cellar…")
        return .canHandOver
    }

    /// `HKCU\Software\Valve\Steam` `AutoLoginUser` + `RememberPassword`, as Steam's "Remember me"
    /// leaves them. Skipped when already set, because asking Wine costs a few seconds.
    internal static func setAutoLogin(account: String, runner: WineRunner) {
        let name = account.lowercased()
        let userReg = (try? String(contentsOf: runner.prefix.appendingPathComponent("user.reg"), encoding: .utf8)) ?? ""
        if userReg.contains("\"AutoLoginUser\"=\"\(name)\""), userReg.contains("\"RememberPassword\"=dword:00000001") {
            return
        }
        let key = #"HKCU\Software\Valve\Steam"#
        runner.run(["reg", "add", key, "/v", "AutoLoginUser", "/t", "REG_SZ", "/d", name, "/f"])
        runner.run(["reg", "add", key, "/v", "RememberPassword", "/t", "REG_DWORD", "/d", "1", "/f"])
    }

    /// How far `connection_log.txt` has got, so a logon can be read from what Steam writes after it.
    static func connectionLogMark(in prefix: URL) -> UInt64 {
        let log = logsDirectory(in: prefix).appendingPathComponent("connection_log.txt")
        return ((try? FileManager.default.attributesOfItem(atPath: log.path)[.size]) as? NSNumber)?.uint64Value ?? 0
    }

    /// Steam's answer to the most recent logon since `mark`, if it has given one.
    internal static func logonResult(in prefix: URL, since mark: UInt64) -> SteamClientSession.LogonResult? {
        let log = logsDirectory(in: prefix).appendingPathComponent("connection_log.txt")
        guard let handle = try? FileHandle(forReadingFrom: log) else { return nil }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        // Steam starts a fresh file when the old one grows too large; then all of it is new.
        try? handle.seek(toOffset: size >= mark ? mark : 0)
        guard let data = try? handle.readToEnd() else { return nil }
        return SteamClientSession.logonResult(inConnectionLog: String(decoding: data, as: UTF8.self))
    }

    /// Wait until the client Cellar expects to sign in by itself actually **has**, before the game is
    /// started beside it.
    ///
    /// Running is not signed in: Steam's logon lands twenty to forty seconds after its process does,
    /// and starting a Steamworks game into that gap gave "Unable to initialize SteamAPI. Please make
    /// sure Steam is running and you are logged in" — a dialog that looks like a broken game and is
    /// really a launch that went too early.
    ///
    /// A refusal takes the session back and falls back to the client's own sign-in window, so the
    /// game never starts against a client nobody is signed in to.
    internal static func waitForClientLogon(runner: WineRunner, since mark: UInt64, game: String,
                                            showHUD: Bool, gameEnv: [String: String],
                                            timeout: TimeInterval = 120,
                                            progress: (String) -> Void,
                                            stage: (LaunchStage) -> Void) throws {
        let deadline = Date().addingTimeInterval(timeout)
        var announced = false
        while Date() < deadline {
            switch logonResult(in: runner.prefix, since: mark) {
            case .loggedOn?:
                return
            case .refused(let reason)?:
                progress("Steam didn't accept the sign-in Cellar gave it (\(reason)), so its own window opens instead.")
                if let account = SteamAccount.state.accountName {
                    SteamClientSession.forget(account: account, prefix: runner.prefix,
                                              steamDirectory: steamDirectory(in: runner.prefix), wineUser: wineUser)
                }
                stage(.signIn)
                try waitForClientSignIn(runner: runner, game: game, showHUD: showHUD, gameEnv: gameEnv,
                                        progress: progress)
                return
            case nil:
                if !announced {
                    progress("Waiting for Steam to finish signing in — \(game)'s DRM needs it signed in, not just running.")
                    announced = true
                }
                Thread.sleep(forTimeInterval: 2)
            }
        }
        // Cellar cannot tell a slow Steam from a stuck one, so it says what it knows and goes on
        // rather than refusing a launch that may well work.
        progress("Steam hasn't reported a sign-in in \(Int(timeout)) s. Starting \(game) anyway — if it says SteamAPI isn't ready, press Play again.")
    }

    /// Open the client's own window and wait until the player has signed in to it.
    ///
    /// The fallback for when Cellar can't hand the client its session (`handOverSession`) or Steam
    /// refused it. Asking for that as a separate step on the game's page read as Cellar asking
    /// twice, so it is folded into Play instead: the window opens, and the game starts once
    /// `loginusers.vdf` names an account — a file Steam writes, rather than a hope that Steam
    /// queues a launch behind its login screen.
    ///
    /// Throws when the player closes Steam first, or never signs in, so the launch fails with the
    /// reason instead of starting a game that would die on its licence check.
    static func waitForClientSignIn(runner: WineRunner, game: String, showHUD: Bool = false,
                                    gameEnv: [String: String] = [:], timeout: TimeInterval = 15 * 60,
                                    progress: (String) -> Void = { _ in }) throws {
        guard loggedInAccount(in: runner.prefix) == nil else { return }
        progress("Opening Steam so you can sign in to it — once, for every Steam game…")
        // A client already up in the tray only needs its window brought forward; a cold start shows
        // the sign-in window by itself.
        try launchClient(runner: runner, extraArgs: isRunning ? ["steam://open/main"] : [],
                         showHUD: showHUD, gameEnv: gameEnv, dock: .visible)
        let deadline = Date().addingTimeInterval(timeout)
        var seenRunning = false
        var goneFor = 0
        while Date() < deadline {
            Thread.sleep(forTimeInterval: 2)
            if loggedInAccount(in: runner.prefix) != nil {
                progress("Signed in to Steam. Starting \(game)…")
                Thread.sleep(forTimeInterval: 6)   // let the client finish logging on
                return
            }
            if isRunning { seenRunning = true; goneFor = 0 } else if seenRunning { goneFor += 1 }
            // Several polls, not one: Steam restarts itself while it updates on first run.
            if goneFor >= 10 {
                throw CellarError.invalidArgument(
                    "Steam was closed before anyone signed in to it, so \(game) wasn't started. Press Play to try again.")
            }
        }
        throw CellarError.invalidArgument(
            "Nobody signed in to Steam, so \(game) wasn't started — its DRM needs the client signed in. Press Play to try again.")
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
