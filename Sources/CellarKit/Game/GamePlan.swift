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
    public let env: [String: String]
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
    public var launchEnv: [String: String] {
        let exe = launchExe.map { [($0 as NSString).lastPathComponent] } ?? []
        var env = DockShim.environment(naming: name, executables: exe)
        for (key, value) in self.env { env[key] = value }
        return env
    }

    public var gameProcessNeedles: [String] {
        var needles: [String] = []
        if let launchExe { needles.append((launchExe as NSString).lastPathComponent) }
        if let installDir { needles += ["\\\(installDir)\\", "/\(installDir)/"] }
        return needles
    }
}
