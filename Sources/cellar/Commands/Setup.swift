import ArgumentParser
import CellarKit

struct Setup: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "One-command setup: install the runner, create the bottle, install Windows Steam.",
        discussion: """
        The minimal-setup path to play a game. Downloads the Game Porting Toolkit Wine runner
        (Wine + Apple D3DMetal), creates an isolated bottle, initialises it, and installs the
        Windows Steam client inside it. Defaults to the Planet Coaster 2 profile.
        """
    )

    @Option(help: "Profile slug to set up.")
    var profile: String = "planet-coaster-2"

    @Flag(help: "Open the in-bottle Steam client when finished (so you can log in + install the game).")
    var openSteam = false

    func run() throws {
        let plan = try Game.plan(slug: profile)
        print(Term.bold("Setting up \(plan.name)")
            + Term.dim("  (bottle: \(plan.bottleName), runner: \(plan.runnerID), backend: \(plan.backend))"))
        print("")

        let wine = try Game.setUp(plan) { print("  " + Term.dim($0)) }

        print("")
        print(Term.green("Setup complete.") + " Next steps:")
        print("  1. " + Term.bold("cellar steam open \(profile)")
            + Term.dim("   — opens Steam in the bottle; log in (Steam Guard / 2FA works)."))
        if let appID = plan.appID {
            print("  2. " + Term.bold("cellar steam install \(profile)")
                + Term.dim("   — opens the install dialog for \(plan.name) (AppID \(appID))."))
        }
        print("  3. " + Term.bold("cellar launch \(profile)") + Term.dim("   — play."))
        print("  • " + Term.bold("cellar steam add \(profile)")
            + Term.dim("   — add it to your native Steam library + ~/Applications."))

        if openSteam {
            print("")
            print(Term.dim("Opening Steam in the bottle… (a window will appear; log in and install your game)"))
            SteamBottle.launchClient(runner: wine)
        }
    }
}
