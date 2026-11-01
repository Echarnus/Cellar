import CellarDomain
import Foundation

/// Installs the **Rockstar Games Launcher** inside a Wine bottle, for the Rockstar games Cellar
/// gets from Steam (Red Dead Redemption, Red Dead Redemption 2, Grand Theft Auto V).
///
/// ## Why Cellar installs it
///
/// Steam's copies of Rockstar's games do not start the game: Steam runs a small stub
/// (`PlayRDR2.exe`, `PlayGTAV.exe`) that hands off to the Rockstar Games Launcher, which signs the
/// player in to a Rockstar Games account and then starts the game itself. On Windows, Steam installs
/// that launcher the first time the game is played, from the game's install script. Cellar downloads
/// a game from the Steam depot instead, so that script never runs, and without the launcher the stub
/// has nothing to hand off to. So setup does what Steam would have done: it runs Rockstar's own
/// installer, fetched from Rockstar, inside the game's bottle. Nothing of Rockstar's is bundled.
///
/// ## What it costs the player
///
/// 1. **The installer is treated as interactive.** Community installers that run it under Wine
///    (Lutris's GTA V script) do not run it silently, and no silent switch is documented by Rockstar,
///    so Cellar does not pretend one exists: it says a window will open before it opens.
/// 2. **The sign-in is Rockstar's, and Cellar cannot see it.** The launcher keeps its session to
///    itself, the way Battle.net does. So Cellar never shows a ✓ or ✗ for it. The first Play opens
///    the launcher's window, the player signs in there, and the launcher starts the game. Cellar
///    never sees, stores or logs the Rockstar password: it is typed into Rockstar's window only.
/// 3. **The sign-in window is the fragile part.** It is drawn by an embedded Chromium
///    (`SocialClubHelper.exe`), the most common thing to fail under Wine and Proton
///    (ValveSoftware/Proton#3291). That is why every profile using it says `untested` until it has
///    been run on a Mac.
public enum RockstarLauncher {
    /// Rockstar's own download. Unversioned: the installer fetches the current launcher, so there
    /// is nothing to pin and nothing to keep up to date. The same address Lutris's scripts use.
    public static let installerURL = "https://gamedownloads.rockstargames.com/public/installer/Rockstar-Games-Launcher.exe"

    /// Where the installer puts the launcher: a 64-bit program, so `Program Files`, not `(x86)`.
    static let relativeInstallPath = "drive_c/Program Files/Rockstar Games/Launcher"

    /// How long setup waits for the launcher to land once the installer has been started. The
    /// installer downloads the launcher itself, so this is a download, not a copy.
    public static let installWaitSeconds = 900

    public static func directory(in prefix: URL) -> URL {
        prefix.appendingPathComponent(relativeInstallPath, isDirectory: true)
    }

    /// The launcher itself — the file whose presence means "installed".
    public static func executable(in prefix: URL) -> URL {
        directory(in: prefix).appendingPathComponent("Launcher.exe")
    }

    public static func isInstalled(in prefix: URL) -> Bool {
        FileManager.default.fileExists(atPath: executable(in: prefix).path)
    }

    /// Whether any of the launcher's processes is up (in any bottle: Wine's command lines carry no prefix).
    public static var isRunning: Bool {
        ProcessWatch.isRunningAny(PublisherLauncher.rockstar.processNeedles)
    }

    /// `pkill -f` patterns for the launcher's processes. `ProcessWatch.kill` takes regular
    /// expressions, not the literal needles `isRunning` matches on, so the folder is written with
    /// `.` standing in for either separator — a backslash would be an escape, not a path.
    static let killPatterns = [
        "Rockstar Games.Launcher.", "RockstarService.exe", "SocialClubHelper.exe", "LauncherPatcher.exe",
    ]

    public static func killProcesses() {
        ProcessWatch.kill(killPatterns)
    }

    /// Download Rockstar's installer and run it inside the bottle, then wait for the launcher to land.
    ///
    /// - Parameters:
    ///   - fetch: puts the installer at the given file. Rockstar's CDN by default; a test hands it a
    ///     local file so no network is involved.
    ///   - waitSeconds: how long to wait for `Launcher.exe` once the installer has run.
    public static func install(runner: WineRunner,
                               fetch: (URL) throws -> Void = { _ = try Downloader.fetch(installerURL, to: $0) },
                               waitSeconds: Int = installWaitSeconds,
                               progress: (String) -> Void = { _ in }) throws {
        if isInstalled(in: runner.prefix) {
            progress("Rockstar Games Launcher is already installed in this bottle.")
            return
        }

        let setup = Paths.cache.appendingPathComponent("Rockstar-Games-Launcher.exe")
        try FileManager.default.createDirectory(at: Paths.cache, withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: setup)
        progress("Downloading the Rockstar Games Launcher installer from Rockstar…")
        try fetch(setup)
        guard WindowsInstaller.isPortableExecutable(setup) else {
            try? FileManager.default.removeItem(at: setup)
            throw CellarError.ioFailure(
                "The Rockstar Games Launcher download wasn't a Windows program — Rockstar's download server may be having a moment. Try again.")
        }

        progress("Starting Rockstar's installer — a window will open. Click Install, and leave the app open.")
        progress("When the launcher asks you to sign in you can close it: it asks again the first time you press Play, and Cellar closes it for you once it is installed.")
        runner.runExecutable(setup.path, args: [], inheritIO: true)

        progress("Waiting for the Rockstar Games Launcher to finish installing…")
        guard waitForLauncher(in: runner.prefix, seconds: waitSeconds, progress: progress) else {
            throw CellarError.ioFailure(
                "The Rockstar Games Launcher didn't finish installing. Run setup again — if Rockstar's window closed early, that is where to look.")
        }

        // The installer starts the launcher when it finishes. Left up, its sign-in window would sit
        // on screen with nothing to do until Play, so Cellar closes it.
        killProcesses()
        try? FileManager.default.removeItem(at: setup)
        progress("Rockstar Games Launcher installed.")
    }

    /// Poll for `Launcher.exe`, reporting in so a long download never looks like a freeze.
    @discardableResult
    static func waitForLauncher(in prefix: URL, seconds: Int, progress: (String) -> Void) -> Bool {
        let start = Date()
        var announcedHalfMinutes = 0
        while Date().timeIntervalSince(start) < TimeInterval(seconds) {
            if isInstalled(in: prefix) { return true }
            Thread.sleep(forTimeInterval: 1)
            let elapsed = Int(Date().timeIntervalSince(start))
            if elapsed / 30 > announcedHalfMinutes {
                announcedHalfMinutes = elapsed / 30
                progress("Still installing… (\(elapsed / 60) min \(elapsed % 60) s)")
            }
        }
        return isInstalled(in: prefix)
    }
}

public extension PublisherLauncher {
    /// Whether this launcher is in the bottle at `prefix`.
    func isInstalled(in prefix: URL) -> Bool {
        switch self {
        case .rockstar: return RockstarLauncher.isInstalled(in: prefix)
        }
    }

    /// Whether this launcher is up now.
    var isRunning: Bool {
        switch self {
        case .rockstar: return RockstarLauncher.isRunning
        }
    }

    /// Set it up in the bottle — the step of `cellar setup` after the store's client.
    func install(runner: WineRunner, progress: (String) -> Void) throws {
        switch self {
        case .rockstar: try RockstarLauncher.install(runner: runner, progress: progress)
        }
    }
}
