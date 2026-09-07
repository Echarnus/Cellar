import ArgumentParser
import CellarKit
import Foundation

struct Launch: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "launch",
        abstract: "Launch a game from its profile (through the bottle's Steam, so DRM/auth/overlay work)."
    )

    @Argument(help: "Profile slug to launch, e.g. 'planet-coaster-2'.")
    var slug: String

    @Flag(help: "Show the Metal performance HUD (FPS / frametime). Applies when Steam (re)starts.")
    var hud = false

    @Flag(name: .customLong("print-env"), help: "Print the environment the game would get and exit (debugging).")
    var printEnv = false

    func run() throws {
        let plan = try Game.plan(slug: slug)

        guard let wine = Game.wineRunner(plan) else {
            throw CellarError.invalidArgument(
                "Runner '\(plan.runnerID)' isn't installed. Run: cellar setup --profile \(slug)")
        }
        if printEnv {
            var extra = WineRunner.d3dMetalEnv(showHUD: hud)
            for (k, v) in plan.env { extra[k] = v }
            for (k, v) in wine.environment(extra: extra).sorted(by: { $0.key < $1.key }) { print("\(k)=\(v)") }
            return
        }
        guard SteamBottle.isInstalled(in: plan.prefix) else {
            throw CellarError.invalidArgument(
                "Windows Steam isn't installed in this bottle. Run: cellar setup --profile \(slug)")
        }
        guard let appID = plan.appID else {
            throw CellarError.invalidArgument("Profile '\(slug)' has no steam_appid to launch.")
        }

        if SteamBottle.loggedInAccount(in: plan.prefix) == nil {
            print(Term.yellow("Nobody is logged into this bottle's Steam yet.")
                + " Run: cellar steam open \(slug)  and sign in first.")
        }
        if !SteamBottle.isGameInstalled(in: plan.prefix, appID: appID) {
            print(Term.yellow("\(plan.name) doesn't look installed yet.")
                + " Install it first: cellar steam install \(slug)")
        }
        if hud && SteamBottle.isRunning {
            print(Term.dim("Steam is already running without the HUD; quit it (Steam → Exit) and relaunch to see the HUD."))
        }

        print(Term.dim("Launching \(plan.name) via Steam (AppID \(appID)) — runner \(plan.runnerID), backend \(plan.backend)…"))
        try SteamBottle.runGame(runner: wine, appID: appID, showHUD: hud, gameEnv: plan.env)
        print(Term.green("Sent.") + Term.dim(" Logs: \(Paths.logs.path)  and  \(SteamBottle.logsDirectory(in: plan.prefix).path)"))
    }
}
