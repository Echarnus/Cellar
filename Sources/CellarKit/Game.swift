import Foundation

/// Resolved launch plan for a game profile.
public struct GamePlan {
    public let slug: String
    public let name: String
    public let bottleName: String
    public let runnerID: String
    public let appID: Int?
    public let backend: String

    public var prefix: URL { Paths.prefixes.appendingPathComponent(bottleName, isDirectory: true) }
}

/// High-level orchestration tying runners, bottles, Wine, and Steam together.
public enum Game {
    public static func plan(slug: String) throws -> GamePlan {
        guard let ref = ProfileStore.find(slug) else {
            throw CellarError.invalidArgument("No profile '\(slug)'. Try: cellar profiles list")
        }
        let fields = ProfileStore.fields(ref)
        return GamePlan(
            slug: slug,
            name: fields["name"] ?? slug,
            bottleName: slug,
            runnerID: fields["id"] ?? "gptk",
            appID: fields["steam_appid"].flatMap { Int($0) },
            backend: fields["backend"] ?? "d3dmetal"
        )
    }

    /// The bottle's Wine runner, if the runner is installed.
    public static func wineRunner(_ plan: GamePlan) -> WineRunner? {
        guard let install = RunnerManager.find(id: plan.runnerID) else { return nil }
        return WineRunner(install: install, prefix: plan.prefix)
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

        let install = try RunnerManager.install(spec, progress: progress)
        let wine = WineRunner(install: install, prefix: plan.prefix)

        if !FileManager.default.fileExists(atPath: plan.prefix.path) {
            progress("Creating bottle '\(plan.bottleName)'…")
            try PrefixManager.create(
                name: plan.bottleName,
                backend: GraphicsBackend(rawValue: plan.backend) ?? .d3dmetal,
                runner: plan.runnerID)
        }

        let registry = plan.prefix.appendingPathComponent("system.reg")
        if !FileManager.default.fileExists(atPath: registry.path) {
            progress("Initialising the Wine prefix…")
            try wine.initializePrefix()
            try wine.setWindowsVersion("win10")
        } else {
            progress("Wine prefix already initialised.")
        }

        try SteamBottle.install(runner: wine, progress: progress)
        return wine
    }
}
