import Foundation

/// Resolved launch plan for a game profile.
public struct GamePlan {
    public let slug: String
    public let name: String
    public let bottleName: String
    public let runnerID: String
    public let appID: Int?
    public let backend: String
    /// `[env]` from the profile — applied to the game and the Steam client that spawns it.
    public let env: [String: String]

    public var prefix: URL { Paths.prefixes.appendingPathComponent(bottleName, isDirectory: true) }
    public var graphicsBackend: GraphicsBackend { GraphicsBackend(rawValue: backend) ?? .d3dmetal }
}

/// A game's readiness, for the GUI to decide what to show (and which button to offer next).
public struct GameSummary: Identifiable, Sendable {
    public let slug: String
    public let name: String
    public let appID: Int?
    public let iconPath: String?      // .icns, if one could be produced
    public let runnerInstalled: Bool  // the profile's Wine runner is present
    public let steamInstalled: Bool   // Windows Steam installed in the bottle
    public let account: String?       // logged-in Steam account, if any
    public let gameInstalled: Bool    // the game's files are fully installed
    public let running: Bool          // a Windows Steam client is up in the bottle

    public var id: String { slug }

    /// The single most useful next action given the current state.
    public enum NextStep: String, Sendable {
        case setup = "Set up"          // no runner / no Steam yet
        case login = "Log in to Steam" // Steam there, nobody logged in
        case install = "Install"       // logged in, game not installed
        case play = "Play"             // ready
    }
    public var nextStep: NextStep {
        if !runnerInstalled || !steamInstalled { return .setup }
        if account == nil { return .login }
        if !gameInstalled { return .install }
        return .play
    }
}

/// High-level orchestration tying runners, bottles, Wine, and Steam together.
public enum Game {
    /// A readiness summary for every known profile — the GUI's data source.
    public static func summaries() -> [GameSummary] {
        ProfileStore.all().compactMap { ref in
            guard let plan = try? plan(slug: ref.slug) else { return nil }
            let installed = SteamBottle.isInstalled(in: plan.prefix)
            return GameSummary(
                slug: plan.slug,
                name: plan.name,
                appID: plan.appID,
                iconPath: AppBundle.resolveGameICNS(slug: plan.slug, prefix: plan.prefix, appID: plan.appID)?.path,
                runnerInstalled: RunnerManager.find(id: plan.runnerID) != nil,
                steamInstalled: installed,
                account: installed ? SteamBottle.loggedInAccount(in: plan.prefix) : nil,
                gameInstalled: plan.appID.map { SteamBottle.isGameInstalled(in: plan.prefix, appID: $0) } ?? false,
                running: SteamBottle.isRunning)
        }
    }

    public static func plan(slug: String) throws -> GamePlan {
        guard let ref = ProfileStore.find(slug) else {
            throw CellarError.invalidArgument("No profile '\(slug)'. Try: cellar profiles list")
        }
        let fields = ProfileStore.fields(ref)
        return GamePlan(
            slug: slug,
            name: fields["name"] ?? slug,
            // Several games can share one bottle (one Steam login, one download cache); a profile
            // opts in with `bottle = "<name>"`. Default: one bottle per game.
            bottleName: fields["bottle"] ?? slug,
            runnerID: fields["id"] ?? RunnerCatalog.defaultID,
            appID: fields["steam_appid"].flatMap { Int($0) },
            backend: fields["backend"] ?? "d3dmetal",
            env: ProfileStore.env(ref)
        )
    }

    /// The bottle's Wine runner, if the runner is installed.
    public static func wineRunner(_ plan: GamePlan) -> WineRunner? {
        guard let install = RunnerManager.find(id: plan.runnerID) else { return nil }
        return WineRunner(install: install, prefix: plan.prefix, backend: plan.graphicsBackend)
    }

    /// Minimal-setup pipeline: ensure runner → bottle → initialised prefix → Windows Steam.
    /// Idempotent: safe to re-run; skips steps already done.
    @discardableResult
    public static func setUp(_ plan: GamePlan, progress: (String) -> Void) throws -> WineRunner {
        guard SystemEnvironment.isAppleSilicon else {
            throw CellarError.invalidArgument("Cellar requires an Apple Silicon Mac.")
        }
        guard SystemEnvironment.rosettaWorks else {
            throw CellarError.invalidArgument(
                "Rosetta 2 is required. Install it: softwareupdate --install-rosetta --agree-to-license")
        }
        guard let spec = RunnerCatalog.spec(forID: plan.runnerID) else {
            throw CellarError.invalidArgument("Unknown runner '\(plan.runnerID)'.")
        }
        if let why = spec.deprecated {
            progress("Warning: runner '\(spec.id)' is deprecated — \(why)")
        }

        let install = try RunnerManager.install(spec, progress: progress)
        let wine = WineRunner(install: install, prefix: plan.prefix, backend: plan.graphicsBackend)

        if !FileManager.default.fileExists(atPath: plan.prefix.path) {
            progress("Creating bottle '\(plan.bottleName)'…")
            try PrefixManager.create(name: plan.bottleName, backend: plan.graphicsBackend, runner: plan.runnerID)
        }

        let registry = plan.prefix.appendingPathComponent("system.reg")
        if !FileManager.default.fileExists(atPath: registry.path) {
            progress("Initialising the Wine prefix (64-bit + WoW64)…")
            try wine.initializePrefix()
            try wine.setWindowsVersion("win10")
            let x86 = plan.prefix.appendingPathComponent("drive_c/Program Files (x86)")
            guard FileManager.default.fileExists(atPath: x86.path) else {
                throw CellarError.ioFailure(
                    "The prefix has no 'Program Files (x86)' — the runner is not a WoW64 build, and the 32-bit Steam client can't install into it.")
            }
        } else {
            progress("Wine prefix already initialised.")
        }

        try SteamBottle.install(runner: wine, progress: progress)
        return wine
    }
}
