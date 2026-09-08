import Foundation

/// Installs and drives the **Battle.net desktop app** inside a Wine bottle — the way Blizzard
/// titles (Diablo IV, Overwatch 2, WoW…) are installed, authenticated and launched.
///
/// ## How this differs from `SteamBottle`
///
/// It is tempting to treat every store the same. Battle.net does not let you, and the differences
/// are load-bearing rather than cosmetic:
///
/// 1. **The installer is not silent.** `SteamSetup.exe /S` installs Steam with nobody watching.
///    `Battle.net-Setup.exe` has no silent switch at all — `--lang` and `--installpath` only
///    pre-fill its dialog. Setup therefore *has to* put a window in front of the player, so Cellar
///    says so up front instead of appearing to hang.
/// 2. **There are two executables.** `Battle.net Launcher.exe` is the bootstrapper that updates and
///    starts the client; `Battle.net.exe` is the client itself and the only one that accepts
///    `--exec`. Launching a game means: bring the *client* up first, then hand it the command.
/// 3. **Sign-in is not observable.** Steam writes `loginusers.vdf`, so Cellar can say "signed in as
///    kenneth". Battle.net keeps its session opaque, so Cellar does not guess — the readiness ladder
///    folds sign-in into "open Battle.net" (see `GameStore.descriptor.canDetectSignIn`).
/// 4. **Games are addressed by product code, not AppID.** Diablo IV is `Fen` (from its "Fenris"
///    codename), and the launch verb is `--exec="launch Fen"`.
/// 5. **The client renders itself with an embedded browser.** That CEF layer is the single biggest
///    source of Wine failures (a spinning logo with no login form, a white window). Disabling the
///    client's hardware acceleration is the documented cure, so Cellar writes that config for the
///    player rather than waiting for them to hit the bug.
///
/// Sources for the facts above are recorded in `docs/RESEARCH.md`.
public enum BattleNetBottle {
    /// Blizzard's own installer endpoint. Unversioned: the downloaded stub fetches the current
    /// client, so there is nothing to pin and nothing to keep up to date.
    static let installerURL =
        "https://www.battle.net/download/getInstallerForGame?os=win&version=LIVE&gameProgram=BATTLENET_APP"

    /// Where the client is installed inside the bottle. Passed to the installer explicitly so the
    /// path is ours to rely on rather than whatever the dialog defaulted to.
    static let windowsInstallPath = #"C:\Program Files (x86)\Battle.net"#
    static let relativeInstallPath = "drive_c/Program Files (x86)/Battle.net"

    /// Command-line fragments that identify the client's processes. `Agent.exe` is Blizzard's
    /// update agent and `Battle.net Helper.exe` its browser subprocesses — both outlive the client
    /// and both have to go when the bottle is shut down.
    public static let clientProcesses = [
        "Battle.net.exe",
        "Battle.net Launcher.exe",
        "Battle.net Helper.exe",
        "Agent.exe",
    ]

    // MARK: - Locations

    public static func directory(in prefix: URL) -> URL {
        prefix.appendingPathComponent(relativeInstallPath)
    }

    /// The bootstrapper. This is what you start; it updates the client and runs it.
    public static func launcherExecutable(in prefix: URL) -> URL {
        directory(in: prefix).appendingPathComponent("Battle.net Launcher.exe")
    }

    /// The client itself — the only executable that understands `--exec="launch <product>"`.
    public static func clientExecutable(in prefix: URL) -> URL {
        directory(in: prefix).appendingPathComponent("Battle.net.exe")
    }

    /// The client's own logs, for diagnosing a login window that never appears.
    public static func logsDirectory(in prefix: URL) -> URL {
        prefix.appendingPathComponent("drive_c/ProgramData/Battle.net/Setup")
    }

    /// Every real Windows user directory in the bottle (Wine names one after the macOS user, and
    /// some builds add `steamuser` / `crossover`). `Public` is not a person.
    static func userDirectories(in prefix: URL) -> [URL] {
        let users = prefix.appendingPathComponent("drive_c/users", isDirectory: true)
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: users, includingPropertiesForKeys: [.isDirectoryKey]) else { return [] }
        return entries.filter { $0.lastPathComponent != "Public" }
    }

    /// `Battle.net.config` — the client's settings, JSON, in the roaming profile.
    static func configFiles(in prefix: URL, existingOnly: Bool) -> [URL] {
        let candidates = userDirectories(in: prefix).map {
            $0.appendingPathComponent("AppData/Roaming/Battle.net/Battle.net.config")
        }
        return existingOnly ? candidates.filter { FileManager.default.fileExists(atPath: $0.path) } : candidates
    }

    // MARK: - State

    public static func isInstalled(in prefix: URL) -> Bool {
        FileManager.default.fileExists(atPath: launcherExecutable(in: prefix).path)
    }

    /// Whether the bootstrapper has finished pulling down the real client. Until `Battle.net.exe`
    /// exists there is nothing that can be told to launch a game.
    public static func isClientUpdated(in prefix: URL) -> Bool {
        FileManager.default.fileExists(atPath: clientExecutable(in: prefix).path)
    }

    /// Whether a Battle.net client is up (in any bottle — Wine's command lines carry no prefix).
    public static var isRunning: Bool {
        ProcessWatch.isRunning("Battle.net.exe")
    }

    /// Best effort at "who is signed in". Battle.net has no `loginusers.vdf` equivalent, so this
    /// reads the remembered-login hint out of `Battle.net.config` and returns nil whenever it
    /// cannot be sure. Callers must treat nil as *unknown*, never as "nobody is signed in" —
    /// which is exactly why the Battle.net readiness ladder never gates on it.
    public static func rememberedAccount(in prefix: URL) -> String? {
        for file in configFiles(in: prefix, existingOnly: true) {
            guard let data = try? Data(contentsOf: file),
                  let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  let client = root["Client"] as? [String: Any],
                  let saved = client["Saved"] as? [String: Any] else { continue }
            for key in ["AccountsExport", "LastLoginAddress", "Email"] {
                guard let value = saved[key] as? String, !value.isEmpty else { continue }
                let first = value.split(separator: ",").first.map(String.init) ?? value
                let trimmed = first.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return trimmed }
            }
        }
        return nil
    }

    // MARK: - Install

    /// Download and run Blizzard's installer inside the bottle.
    ///
    /// Unlike Steam's, this installer **cannot** be run unattended, so this call is interactive by
    /// design: a Battle.net window appears and the player clicks through it. `progress` is used to
    /// warn them before that happens, because an unexplained multi-minute pause reads as a hang.
    public static func install(runner: WineRunner, progress: (String) -> Void = { _ in }) throws {
        if isInstalled(in: runner.prefix) {
            progress("Battle.net is already installed in this bottle.")
            return
        }

        let setup = Paths.cache.appendingPathComponent("Battle.net-Setup.exe")
        progress("Downloading the Battle.net installer from Blizzard…")
        try Downloader.fetch(installerURL, to: setup)
        guard WindowsInstaller.isPortableExecutable(setup) else {
            try? FileManager.default.removeItem(at: setup)
            throw CellarError.ioFailure(
                "The Battle.net download wasn't a Windows executable — Blizzard's CDN may be having a moment. Try again.")
        }

        progress("Starting the Battle.net installer — a window will open. Click through it, then leave the app open.")
        progress("(Blizzard ships no silent installer, so this step needs you. Cellar waits here.)")
        runner.runExecutable(setup.path,
                             args: ["--lang=enUS", "--installpath=\(windowsInstallPath)"],
                             inheritIO: true)

        // The installer hands off to the bootstrapper, which downloads the real client. Wait for
        // that to land rather than for wineserver to go quiet: Battle.net deliberately stays up.
        progress("Waiting for Battle.net to finish downloading its client…")
        guard waitForClient(in: runner.prefix, seconds: 900, progress: progress) else {
            throw CellarError.ioFailure(
                "Battle.net didn't finish installing. Re-run setup, or check \(logsDirectory(in: runner.prefix).path).")
        }

        // Settle the bottle before writing config: the client rewrites Battle.net.config on exit
        // and would clobber what we put there.
        progress("Applying Cellar's Battle.net settings (hardware acceleration off — it is what makes the login window appear under Wine).")
        killClientProcesses()
        Thread.sleep(forTimeInterval: 3)
        try writeClientConfig(in: runner.prefix)

        progress("Battle.net installed.")
    }

    /// Poll for `Battle.net.exe` (i.e. a real client, not just the bootstrapper), reporting in so a
    /// long download never looks like a freeze.
    @discardableResult
    static func waitForClient(in prefix: URL, seconds: Int, progress: (String) -> Void) -> Bool {
        let start = Date()
        var announcedHalfMinutes = 0
        while Date().timeIntervalSince(start) < TimeInterval(seconds) {
            if isClientUpdated(in: prefix) { return true }
            Thread.sleep(forTimeInterval: 5)
            let elapsed = Int(Date().timeIntervalSince(start))
            if elapsed / 30 > announcedHalfMinutes {
                announcedHalfMinutes = elapsed / 30
                progress("Still installing… (\(elapsed / 60) min \(elapsed % 60) s)")
            }
        }
        return isClientUpdated(in: prefix)
    }

    /// Write the settings that make Battle.net behave under Wine, merged into whatever the client
    /// has already saved so a remembered login survives.
    ///
    /// - `HardwareAcceleration = false` — the client draws its UI with an embedded Chromium. GPU
    ///   accelerated, that renders as a spinning logo with no login form, or a white window.
    /// - `Streaming.StreamingEnabled = false` — "stream while you download" black-screens games.
    /// - `Client.GameLaunchWindowBehavior = 2` — keep the client up when a game starts; Cellar
    ///   needs it alive because it is the game's parent process.
    /// - `Sound.Enabled = false` — the client's UI sounds are pure crackle through Wine.
    ///
    /// Battle.net stores these as JSON *strings*, not booleans. Writing real booleans is ignored.
    public static func writeClientConfig(in prefix: URL) throws {
        let settings: [String: Any] = [
            "Client": ["GameLaunchWindowBehavior": "2"],
            "GameSearch": ["BackgroundSearch": "true"],
            "HardwareAcceleration": "false",
            "Sound": ["Enabled": "false"],
            "Streaming": ["StreamingEnabled": "false"],
        ]

        let fm = FileManager.default
        var wrote = false
        for file in configFiles(in: prefix, existingOnly: false) {
            let existing = (try? Data(contentsOf: file))
                .flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any] ?? [:]
            let merged = merge(settings, into: existing)
            let data = try JSONSerialization.data(withJSONObject: merged, options: [.prettyPrinted, .sortedKeys])
            try fm.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: file, options: .atomic)
            wrote = true
        }
        guard wrote else {
            throw CellarError.ioFailure("The bottle has no Windows user directory to write Battle.net.config into.")
        }
    }

    /// Recursive dictionary merge — `new` wins on leaves, `old` keeps everything we don't set.
    static func merge(_ new: [String: Any], into old: [String: Any]) -> [String: Any] {
        var result = old
        for (key, value) in new {
            if let nested = value as? [String: Any], let existing = result[key] as? [String: Any] {
                result[key] = merge(nested, into: existing)
            } else {
                result[key] = value
            }
        }
        return result
    }

    // MARK: - Launch

    /// Open the Battle.net client in the bottle (sign in, browse, install games).
    /// Starts the *bootstrapper*, which is what updates and then runs the client.
    ///
    /// `dock` says whether the client is the thing the player asked for: `.visible` when they chose
    /// to open it (that window needs a Dock icon to come back to), `.hidden` when Cellar is only
    /// standing it up so a game can start.
    public static func launchClient(runner: WineRunner, showHUD: Bool = false,
                                    gameEnv: [String: String] = [:],
                                    dock: DockPresence = .visible) throws {
        var extra = WineRunner.d3dMetalEnv(showHUD: showHUD)
        for (key, value) in gameEnv { extra[key] = value }
        for (key, value) in DockShim.environment(for: .battlenet, dock: dock) { extra[key] = value }
        try runner.spawn([launcherExecutable(in: runner.prefix).path],
                         extraEnv: extra,
                         log: Paths.logs.appendingPathComponent("battlenet-\(runner.prefix.lastPathComponent).log"))
    }

    /// Bring the client up and wait until it can take commands. `--exec` is silently dropped when
    /// no client is running, so every launch has to go through this first.
    @discardableResult
    public static func ensureClientRunning(runner: WineRunner, showHUD: Bool = false,
                                           gameEnv: [String: String] = [:],
                                           dock: DockPresence = .visible,
                                           progress: (String) -> Void = { _ in }) throws -> Bool {
        if isRunning { return true }
        progress("Starting Battle.net and waiting for it to be ready…")
        try launchClient(runner: runner, showHUD: showHUD, gameEnv: gameEnv, dock: dock)
        let up = ProcessWatch.waitToAppear(["Battle.net.exe"], seconds: 120)
        if up { Thread.sleep(forTimeInterval: 8) }   // let it finish authenticating
        return up
    }

    /// Ask the running client to launch a product, e.g. `Fen` for Diablo IV.
    public static func execLaunch(runner: WineRunner, product: String, showHUD: Bool = false,
                                 gameEnv: [String: String] = [:],
                                 dock: DockPresence = .visible) throws {
        var extra = WineRunner.d3dMetalEnv(showHUD: showHUD)
        for (key, value) in gameEnv { extra[key] = value }
        for (key, value) in DockShim.environment(for: .battlenet, dock: dock) { extra[key] = value }
        try runner.spawn([clientExecutable(in: runner.prefix).path, "--exec=launch \(product)"],
                         extraEnv: extra,
                         log: Paths.logs.appendingPathComponent("battlenet-exec-\(product).log"))
    }

    /// Launch a Blizzard game and supervise its startup, retrying through the D3DMetal race the
    /// same way the Steam path does.
    ///
    /// `gameNeedles` are command-line fragments that identify the *game's own* process — its exe
    /// name and install directory — so the client's own processes are never mistaken for the game.
    public static func runGameSupervised(runner: WineRunner, product: String, gameNeedles: [String],
                                         showHUD: Bool = false, gameEnv: [String: String] = [:],
                                         attempts: Int = 6,
                                         progress: (String) -> Void = { _ in }) throws {
        guard isClientUpdated(in: runner.prefix) else {
            throw CellarError.invalidArgument(
                "Battle.net hasn't finished installing in this bottle. Run: cellar battlenet open <slug>")
        }
        guard try ensureClientRunning(runner: runner, showHUD: showHUD, gameEnv: gameEnv,
                                      dock: .hidden, progress: progress) else {
            throw CellarError.ioFailure("Battle.net didn't come up. Open it manually: cellar battlenet open <slug>")
        }

        try ProcessWatch.superviseStart(
            attempts: attempts,
            cleanup: { ProcessWatch.kill(gameNeedles) },
            start: { try execLaunch(runner: runner, product: product, showHUD: showHUD,
                                    gameEnv: gameEnv, dock: .hidden) },
            isUp: { ProcessWatch.isRunningAny(gameNeedles) },
            progress: progress)
    }

    // MARK: - Teardown

    /// Kill the client and everything it spawned. Battle.net has no documented "quit" verb, and a
    /// surviving `Agent.exe` is what makes the next session show a greyed-out Install button.
    public static func killClientProcesses() {
        ProcessWatch.kill(clientProcesses)
    }

    /// Shut the whole bottle down — what makes "quit the game and the layer closes too" true here.
    public static func shutdown(runner: WineRunner) {
        killClientProcesses()
        for _ in 0..<10 where isRunning { Thread.sleep(forTimeInterval: 1) }
        runner.killServer()
    }
}
