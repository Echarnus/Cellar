import ArgumentParser
import CellarKit

struct Launch: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "launch",
        abstract: "Launch a game from its profile (through the bottle's Steam, so DRM/auth/overlay work)."
    )

    @Argument(help: "Profile slug to launch, e.g. 'planet-coaster-2'.")
    var slug: String

    @Flag(help: "Show the Metal performance HUD (FPS / frametime).")
    var hud = false

    func run() throws {
        let plan = try Game.plan(slug: slug)

        guard let wine = Game.wineRunner(plan) else {
            throw CellarError.invalidArgument(
                "Runner '\(plan.runnerID)' isn't installed. Run: cellar setup --profile \(slug)")
        }
        guard SteamBottle.isInstalled(in: plan.prefix) else {
            throw CellarError.invalidArgument(
                "Windows Steam isn't installed in this bottle. Run: cellar setup --profile \(slug)")
        }
        guard let appID = plan.appID else {
            throw CellarError.invalidArgument("Profile '\(slug)' has no steam_appid to launch.")
        }

        if !SteamBottle.isGameInstalled(in: plan.prefix, appID: appID) {
            print(Term.yellow("\(plan.name) doesn't look installed yet.")
                + " Install it first: cellar steam open \(slug)  (or: cellar steam install \(slug))")
        }

        print(Term.dim("Launching \(plan.name) via Steam (AppID \(appID))…"))
        SteamBottle.runGame(runner: wine, appID: appID, showHUD: hud)
    }
}
