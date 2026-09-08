import ArgumentParser
import CellarKit

struct Setup: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "One-command setup: install the runner, create the bottle, install the game's store client.",
        discussion: """
        The minimal-setup path to play a game. Downloads the Wine runner (Wine + Apple D3DMetal),
        creates an isolated bottle, initialises it, and installs whichever client the game's profile
        names — Windows Steam, or Blizzard's Battle.net. A standalone (DRM-free) profile skips the
        client entirely.

        Battle.net's installer is not silent: a window will open and want a few clicks. That is
        Blizzard's installer, not a hang.
        """
    )

    @Option(help: "Profile slug to set up.")
    var profile: String = "planet-coaster-2"

    @Flag(name: [.customLong("open-client"), .customLong("open-steam")],
          help: "Open the bottle's store client when finished (so you can sign in + install the game).")
    var openClient = false

    func run() throws {
        let plan = try Game.plan(slug: profile)
        let store = plan.store
        print(Term.bold("Setting up \(plan.name)")
            + Term.dim("  (store: \(store.displayName), bottle: \(plan.bottleName), runner: \(plan.runnerID), backend: \(plan.backend))"))
        if !store.descriptor.hasSilentInstaller {
            print(Term.yellow("Heads up: ")
                + "\(store.displayName) has no silent installer — its window will open partway through and needs a few clicks from you.")
        }
        print("")

        let wine = try Game.setUp(plan) { print("  " + Term.dim($0)) }

        if store != .standalone {
            let clientApp = try AppBundle.generateStoreClient(
                store: store, bottle: plan.bottleName, slug: profile,
                cellarBinary: AppBundle.resolveCellarBinary())
            print("  " + Term.dim("\(store.displayName) launcher: \(clientApp.app.path)"))
        }

        print("")
        print(Term.green("Setup complete.") + " Next steps:")
        var step = 1
        func next(_ command: String, _ note: String) {
            print("  \(step). " + Term.bold(command) + Term.dim("   — \(note)"))
            step += 1
        }

        switch store {
        case .steam:
            next("cellar steam open \(profile)", "opens Steam in the bottle; sign in (Steam Guard / 2FA works).")
            if let appID = plan.appID {
                next("cellar steam install \(profile)", "opens the install dialog for \(plan.name) (AppID \(appID)).")
            }
        case .battlenet:
            next("cellar battlenet open \(profile)", "opens Battle.net in the bottle; sign in, then install \(plan.name).")
            print("     " + Term.dim("Blizzard has no install URL a launcher can drive, so that download starts from inside the client."))
        case .standalone:
            next("cellar fetch-depot \(profile) --username <steam-account>", "downloads the game's files. No client needed.")
        }
        next("cellar launch \(profile)", "play.")
        if store == .steam {
            print("  • " + Term.bold("cellar steam add \(profile)")
                + Term.dim("   — add it to your native Steam library + ~/Applications."))
        }

        if openClient && store != .standalone {
            print("")
            print(Term.dim("Opening \(store.displayName) in the bottle… (a window will appear; sign in and install your game)"))
            switch store {
            case .steam:      try SteamBottle.launchClient(runner: wine, gameEnv: plan.env)
            case .battlenet:  try BattleNetBottle.launchClient(runner: wine, gameEnv: plan.env)
            case .standalone: break
            }
        }
    }
}
