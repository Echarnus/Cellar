import CellarDomain
import Foundation

/// Resolved launch plan for a game profile.
public struct GamePlan {
    public let slug: String
    public let name: String
    public let bottleName: String
    public let runnerID: String
    /// Which client has to exist inside the bottle for this game — the single fact that decides
    /// how it is set up, installed and launched. See `GameStore`.
    public let store: GameStore
    public let appID: Int?
    /// The backend this launch uses: the player's choice for the bottle when there is one, else the
    /// profile's. A `var` so `cellar launch --backend` can try another for one launch.
    public var backend: String
    /// What the profile names: the backend it was tested on, and the one to try when that fails.
    public let profileBackend: String
    public let fallbackBackend: String?
    /// The game's environment — the profile's `[env]` and switches, then the bottle's
    /// (`PerformanceSettings.resolve`) — applied to the game and to the store client that spawns it.
    /// A `var` so `cellar verify` can turn on the Wine log channels it reads, for its own run.
    public var env: [String: String]
    /// Install method: `windows-steam-in-bottle` (default), `battlenet-in-bottle`, or `depot`.
    public let installMethod: String
    /// Relative path (from the game's install dir) of the exe to run, e.g. `AoE2DE_s.exe`.
    /// Also the process Cellar watches to know the game is alive.
    public let launchExe: String?
    /// The game's own install-directory name, when the store doesn't tell us
    /// (Battle.net: `Diablo IV`). Steam gets this from its appmanifest instead.
    public let installDir: String?
    /// Battle.net product code — `Fen` for Diablo IV. The argument to `--exec="launch …"`.
    public let productCode: String?
    /// GOG's product id, the key to everything on their API (owned check, metadata, installers).
    public let gogProductID: Int?
    /// Whether the game needs a live store session at *runtime* (Denuvo / Steamworks / always-online).
    /// When false and `launchExe` resolves, Cellar launches the exe directly with no client at all.
    public let needsLiveSession: Bool
    /// Optional profile-supplied cover / banner art, for stores with no public artwork CDN.
    public let artPortraitURL: String?
    public let artHeroURL: String?
    /// What the profile says about the game itself — shown in the app's information panel.
    public let facts: GameFacts
    /// `metalfx_upscaling = true`: present the NVIDIA identity so the game's DLSS option becomes
    /// MetalFX. Only takes effect on D3DMetal with a runtime that ships the shims (`WineRunner.usesMetalFX`).
    public var metalFXUpscaling: Bool = false
    /// The language the game and its store client run in, and whether that is the Mac's or the
    /// player's choice. See `GameLanguage`.
    public var language = LanguageChoice.global()
    /// Every performance switch with the layer it came from, for `cellar perf`.
    public var performance = PerformanceSettings.resolve(profileFields: [:], profileEnv: [:],
                                                          bottleFields: [:], bottleEnv: [:])
    /// A profile Cellar wrote itself from the game's files (`DraftProfile`): every value a guess.
    public var isDraft = false
    /// A publisher's launcher the game starts through as well as its store — Rockstar's, for Red
    /// Dead Redemption and GTA V (`PublisherLauncher`). Setup installs it into the bottle.
    public var publisherLauncher: PublisherLauncher? = nil
    /// The program to *start*, when it isn't the game's own process: `PlayRDR2.exe`, the stub Steam
    /// runs, which hands off to Rockstar's launcher and exits. `launchExe` stays the game itself
    /// (`RDR2.exe`), because that is the process Cellar watches and shuts the layer down behind.
    public var startExe: String? = nil
    /// `env` as it would be with the profile's crash workarounds the player switched off put back
    /// (`PerformanceSettings.Resolved.crashWorkaroundsSwitchedOff`); nil when none were.
    public var workaroundEnv: [String: String]? = nil
    /// `online_hosts`: the servers the game itself talks to (`css-api.zaonce.net` for Planet Coaster
    /// 2), which `cellar verify` expects the game's own process to connect to. Not the addresses
    /// `network_check` probes from the bottle: those prove the bottle can reach a server, and only
    /// these prove the game did (#203).
    public var onlineHosts: [String] = []
    /// `crash_processes`: crash reporters of the game's own, beyond the ones `CrashSigns` knows.
    public var crashProcesses: [String] = []
    /// `online_errors`: words the game writes when an online call fails (Frontier's
    /// `ShowNetworkError`). `cellar verify` fails `game-online` when one shows up in the Wine log or
    /// a crash dump's comment: a connection that opened is not a call that worked (#210).
    public var onlineErrors: [String] = []
    /// `first_run_files`: settings files the game's own launcher would write before its first run,
    /// which Cellar writes instead because it starts the game itself (`FirstRunFiles`).
    public var firstRunFiles: [FirstRunFiles.Copy] = []
    /// `display_switch_file`: a file beside the game's exe that the game reads its command line from
    /// (Rockstar's `commandline.txt`), so the full screen or window choice reaches the game even when
    /// a launcher starts it. See `DisplaySwitchFile`.
    public var displaySwitchFile: String? = nil
    /// `display_ini`: the game's own settings file, relative to the Windows user folder, where its
    /// full screen or window setting lives (Skyrim's `SkyrimPrefs.ini`). See `DisplayIni`.
    public var displayIni: String? = nil

    public var prefix: URL { Paths.prefixes.appendingPathComponent(bottleName, isDirectory: true) }
    public var graphicsBackend: GraphicsBackend { GraphicsBackend(rawValue: backend) ?? .d3dmetal }
    /// The backend to offer when this one didn't bring the game up — see `BackendChoice.retry`.
    public var retryBackend: GraphicsBackend? {
        BackendChoice.retry(current: backend, primary: profileBackend, fallback: fallbackBackend)
    }

    /// Where DepotDownloader places this game's files inside the bottle.
    public var depotGameDir: URL { prefix.appendingPathComponent("drive_c/Games/\(slug)", isDirectory: true) }

    /// Every directory a game's files could plausibly live in, in search order. Stores install to
    /// different roots, and the player may have pointed the installer somewhere else again.
    public var installRoots: [URL] {
        var roots = [depotGameDir]
        if let installDir {
            roots += [
                prefix.appendingPathComponent("drive_c/Program Files (x86)/\(installDir)"),
                prefix.appendingPathComponent("drive_c/Program Files/\(installDir)"),
                prefix.appendingPathComponent("drive_c/Games/\(installDir)"),
                // Where the Windows Steam client puts a game it installed itself. Without this a
                // client-installed copy is invisible to every direct route, because Steam nests it
                // one directory deeper than the search below reaches.
                prefix.appendingPathComponent("drive_c/Program Files (x86)/Steam/steamapps/common/\(installDir)"),
            ]
        }
        roots.append(prefix.appendingPathComponent("drive_c/Program Files (x86)/Steam/steamapps/common"))
        return roots
    }

    /// The absolute exe to run for a direct launch, if one is configured and present on disk.
    public var directLaunchExe: URL? {
        guard let launchExe else { return nil }
        return installRoots
            .map { $0.appendingPathComponent(launchExe) }
            .first { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// The absolute program to start for a direct launch: `startExe` beside the game's exe when the
    /// profile names one and it is on disk, then `startExe` at the top of the game's folder, else the
    /// exe itself.
    ///
    /// The top of the folder is for an Unreal game whose Steam stub sits at the root while the game
    /// runs from deep inside it: the GTA Definitive Editions start `PlayGTASanAndreas.exe`, and the
    /// game is `Gameface/Binaries/Win64/SanAndreas.exe` (#290).
    public var directStartExe: URL? {
        guard let launchExe, let exe = directLaunchExe else { return nil }
        guard let startExe else { return exe }
        let fm = FileManager.default
        let beside = exe.deletingLastPathComponent().appendingPathComponent(startExe)
        if fm.fileExists(atPath: beside.path) { return beside }
        // The install root is what `launchExe` was found under: strip its components back off.
        var root = exe
        for _ in (launchExe as NSString).pathComponents { root.deleteLastPathComponent() }
        let atRoot = root.appendingPathComponent(startExe)
        return fm.fileExists(atPath: atRoot.path) ? atRoot : exe
    }

    /// Whether Cellar can start this game full screen or in a window (#306): its engine has a
    /// start-up switch Cellar knows, and Cellar is the one starting it. A publisher launcher sits
    /// between Steam's stub and the game and starts the game itself, dropping whatever it was given;
    /// Battle.net is always the one starting its games (`--exec`), and takes no arguments for them.
    /// A game that reads its switches from a file of its own (`displaySwitchFile`) gets them whoever
    /// starts it, launcher included.
    /// A game that keeps the choice in its own settings file (`displayIni`) gets it the same way.
    public var canChooseDisplayMode: Bool {
        guard store != .battlenet else { return false }
        if displayIni != nil, DisplayIni.supports(engine: facts.engine) { return true }
        guard DisplayMode.isChoosable(engine: facts.engine) else { return false }
        return displaySwitchFile != nil || publisherLauncher == nil
    }

    /// What goes on the game's command line after its exe for the player's `display_mode`: the
    /// engine's own switch, or nothing when the game decides, or when Cellar can't choose for it.
    public var displayArguments: [String] {
        guard canChooseDisplayMode, displaySwitchFile == nil, displayIni == nil else { return [] }
        return performance.displayMode.arguments(engine: facts.engine) ?? []
    }

    /// True when this store-installed game can be launched without its store's client running.
    public var canLaunchStoreFree: Bool { !needsLiveSession && directLaunchExe != nil }

    /// Who is being launched and by which route — what the launch stages are worded from.
    public var launchContext: LaunchContext {
        LaunchContext(game: name, store: store, throughClient: !canLaunchStoreFree,
                      signsInFirst: needsLiveSession && store.descriptor.installsClientInBottle
                          && store.descriptor.canDetectSignIn && Game.signedInAccount(self) == nil
                          // Not a step when Cellar signs the client in itself.
                          && !(store == .steam && SteamBottle.clientSessionReadiness(in: prefix).signsInByItself))
    }

    /// Command-line fragments that identify the *game's own* process, so a supervised launch never
    /// mistakes the store client for the game. Wine reports Windows command lines, hence both
    /// separators.
    /// `env`, plus what makes the running game show up as itself rather than as "wine" (`DockShim`).
    /// Every launch route starts its processes with this; opening the store client on its own
    /// uses `env`, because a client the player opened is not this game.
    public var launchEnv: [String: String] { launchEnv(over: env) }

    /// `launchEnv` with the profile's crash workarounds back on, for a launch that died as it
    /// started with them off. Nil when the player switched none off: then there is nothing to try.
    public var launchEnvWithWorkarounds: [String: String]? { workaroundEnv.map { launchEnv(over: $0) } }

    /// The crash workarounds the player switched off — what a launch that dies puts back.
    public var crashWorkaroundsSwitchedOff: [PerformanceSetting] { performance.crashWorkaroundsSwitchedOff }

    /// Give the profile back its say over the workarounds the player switched off, once a launch has
    /// shown the game needs them: the bottle's lines go, so the app's switches and `cellar perf`
    /// read "profile" again. The player can switch them off again; nothing else is touched.
    public func restoreCrashWorkarounds() {
        let file = BottleConfig.url(forBottle: bottleName)
        for setting in crashWorkaroundsSwitchedOff {
            do {
                try BottleConfig.unset(setting, in: file)
                CellarLog.warn(.launch, "\(name) died as it started with \(setting.key) off; "
                    + "it stayed up with the profile's \(setting.key) on, so the bottle's override is removed.", subject: slug)
            } catch {
                CellarLog.failure(.launch, "Couldn't put \(setting.key) back for \(name)", error, subject: slug)
            }
        }
    }

    /// The sentence a launch shows when it puts the workarounds back.
    public var restoringWorkaroundsMessage: String? {
        let names = crashWorkaroundsSwitchedOff.map(\.displayName)
        guard !names.isEmpty else { return nil }
        let list = names.joined(separator: " and ")
        return "\(name) crashed as it started with \(list) off. Its profile turns that on to stop exactly this crash, "
            + "so Cellar is turning it back on and trying again."
    }

    private func launchEnv(over env: [String: String]) -> [String: String] {
        // Every program of this launch that can show a window wears the game's name: the game, the
        // stub a store starts it through, and a publisher launcher in between. Anything left out
        // is called "wine" in the Dock, which no player should ever read (#266).
        var exe = launchExe.map { [($0 as NSString).lastPathComponent] } ?? []
        if !exe.isEmpty {
            if let startExe { exe.append((startExe as NSString).lastPathComponent) }
            exe += publisherLauncher?.windowedExecutables ?? []
        }
        var result = DockShim.environment(naming: name, executables: exe)
        for (key, value) in env { result[key] = value }
        return result
    }

    public var gameProcessNeedles: [String] {
        var needles: [String] = []
        if let launchExe { needles.append((launchExe as NSString).lastPathComponent) }
        if let installDir { needles += ["\\\(installDir)\\", "/\(installDir)/"] }
        return needles
    }
}
