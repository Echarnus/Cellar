import ArgumentParser
import CellarKit
import Foundation

struct Launch: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "launch",
        abstract: "Launch a game. Runs the exe directly (no Steam) when the game allows it, else through the bottle's silent Steam."
    )

    @Argument(help: "Profile slug to launch, e.g. 'planet-coaster-2'.")
    var slug: String

    @Flag(help: "Show the Metal performance HUD (FPS / frametime).")
    var hud = false

    @Flag(name: .customLong("steam"), help: "Force the Steam launch path even if a direct launch is possible.")
    var forceSteam = false

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

        // Steam-free path: no live-session DRM and the exe is present → run it directly, no Steam.
        if plan.canLaunchSteamFree && !forceSteam {
            print(Term.dim("Launching \(plan.name) directly (no Steam) — \(plan.directLaunchExe!.lastPathComponent), backend \(plan.backend)…"))
            try Game.launchDirect(plan, showHUD: hud)
            print(Term.green("\(plan.name) launched.") + Term.dim(" Log: \(Paths.logs.path)/game-\(slug).log"))
            return
        }

        // Steam path (DRM / Steamworks games): silent Steam + supervised auto-retry.
        guard SteamBottle.isInstalled(in: plan.prefix) else {
            let hint = plan.installMethod == "depot"
                ? "This game needs a live Steam session; set up the bottle: cellar setup --profile \(slug)"
                : "Windows Steam isn't installed in this bottle. Run: cellar setup --profile \(slug)"
            throw CellarError.invalidArgument(hint)
        }
        guard let appID = plan.appID else {
            throw CellarError.invalidArgument("Profile '\(slug)' has no steam_appid to launch.")
        }
        if SteamBottle.loggedInAccount(in: plan.prefix) == nil {
            print(Term.yellow("Nobody is logged into this bottle's Steam yet.")
                + " Run: cellar steam open \(slug)  and sign in first.")
        }

        print(Term.dim("Launching \(plan.name) via Steam (AppID \(appID)) — runner \(plan.runnerID), backend \(plan.backend)…"))
        try SteamBottle.runGameSupervised(runner: wine, appID: appID, showHUD: hud, gameEnv: plan.env) {
            print("  " + Term.dim($0))
        }
        print(Term.green("\(plan.name) is up.") + Term.dim(" Logs: \(SteamBottle.logsDirectory(in: plan.prefix).path)"))
    }
}
