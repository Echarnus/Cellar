import ArgumentParser
import CellarKit

/// The Battle.net plugin — the sibling of `cellar steam`, deliberately shaped the same way so the
/// two stores are learned once. Where the wording differs, it is because Battle.net genuinely
/// behaves differently (no silent installer, no readable sign-in state, product codes not AppIDs);
/// see `BattleNetBottle` for the details and `docs/RESEARCH.md` for the sources.
struct BattleNetCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "battlenet",
        abstract: "The Battle.net plugin: open Blizzard's client in a bottle, install games, surface them natively.",
        subcommands: [Add.self, Forget.self, Open.self, Install.self, Status.self, App.self, Configure.self]
    )

    // MARK: add / forget

    /// The one thing a player can tell Cellar about Battle.net, since Blizzard tells it nothing.
    ///
    /// Not called `login`: Cellar never sees a Battle.net password and never holds a session, so a
    /// command named after signing in would promise something it cannot do. This only says "I have
    /// an account there" — which is exactly what the library needs to know before listing Blizzard's
    /// games as yours.
    struct Add: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "add",
            abstract: "Tell Cellar you have a Battle.net account, so its games are listed.",
            discussion: """
            Blizzard publishes neither who is signed in nor what they own, so Cellar cannot check
            this and never claims to. Adding the account only puts Blizzard's games in your library;
            you still sign in inside Battle.net itself, the first time it opens.
            """)

        func run() throws {
            try StoreLibrary.BattleNetAccount.add()
            print(Term.green("✓") + " Battle.net added. Its games are in your library now.")
            print(Term.dim("  Cellar can't check this one — you sign in inside Battle.net when it opens."))
            print(Term.dim("  cellar library"))
        }
    }

    struct Forget: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "forget",
            abstract: "Forget that you have a Battle.net account, and hide its games again.")

        func run() throws {
            try StoreLibrary.BattleNetAccount.forget()
            print("Battle.net forgotten. Its games are no longer listed.")
            print(Term.dim("  Nothing was uninstalled — cellar battlenet add puts them back."))
        }
    }

    // MARK: status

    struct Status: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Report the bottle's Battle.net state: client installed, game installed, running.")
        @Argument(help: "Profile slug.") var slug: String

        func run() throws {
            let plan = try Game.plan(slug: slug)
            try requireBattleNetProfile(plan)
            let prefix = plan.prefix

            func row(_ label: String, _ ok: Bool, _ text: String) {
                print("  \(ok ? Term.green("✓") : Term.yellow("•")) "
                    + "\(label.padding(toLength: 16, withPad: " ", startingAt: 0)) \(text)")
            }

            print(Term.bold("Battle.net in bottle '\(plan.bottleName)'") + Term.dim("  (\(prefix.path))"))
            row("runner", RunnerManager.find(id: plan.runnerID) != nil, plan.runnerID)
            let installed = BattleNetBottle.isInstalled(in: prefix)
            row("client", installed,
                installed
                    ? (BattleNetBottle.isClientUpdated(in: prefix)
                        ? "installed and updated"
                        : "bootstrapper only — it downloads the client on first launch")
                    : "not installed — cellar setup --profile \(slug)")
            // Deliberately not a ✓/✗ check: Blizzard exposes no reliable signed-in state, and a
            // red cross next to a player who *is* signed in would be a lie.
            print("  \(Term.dim("·")) \("account".padding(toLength: 16, withPad: " ", startingAt: 0)) "
                + (BattleNetBottle.rememberedAccount(in: prefix)
                    ?? Term.dim("not detectable — Battle.net keeps its session private; sign in inside the client")))
            row("running", BattleNetBottle.isRunning, BattleNetBottle.isRunning ? "yes" : "no")
            if let product = plan.productCode {
                let ready = Game.isGameInstalled(plan)
                row("game", ready,
                    ready ? "\(plan.name) installed (product \(product))"
                          : "\(plan.name) not installed — cellar battlenet install \(slug)")
            }
            print(Term.dim("  logs: \(Paths.logs.path)"))
        }
    }

    // MARK: open

    struct Open: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Open the Battle.net client inside a game's bottle (sign in, browse, install).")
        @Argument(help: "Profile slug.") var slug: String

        func run() throws {
            let plan = try Game.plan(slug: slug)
            try requireBattleNetProfile(plan)
            print(Term.dim("Opening Battle.net in bottle '\(plan.bottleName)'. A window will appear — sign in and install your games."))
            try Game.openStoreClient(plan)
        }
    }

    // MARK: install

    struct Install: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Open Battle.net so you can install the profile's game.",
            discussion: """
            Blizzard publishes no per-game install URL that a launcher can drive, so Cellar opens
            the client rather than pretending it can start the download for you. Pick the game in
            Battle.net, install it, and `cellar launch <slug>` takes over from there.
            """)
        @Argument(help: "Profile slug.") var slug: String

        func run() throws {
            let plan = try Game.plan(slug: slug)
            try requireBattleNetProfile(plan)
            try Game.installGame(plan) { print("  " + Term.dim($0)) }
            print(Term.dim("When the download finishes: cellar launch \(slug)"))
        }
    }

    // MARK: app

    struct App: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Create 'Battle.net (<bottle>).app' in ~/Applications that opens the bottle's client.")
        @Argument(help: "Profile slug.") var slug: String

        func run() throws {
            let plan = try Game.plan(slug: slug)
            try requireBattleNetProfile(plan)
            let bundle = try AppBundle.generateStoreClient(
                store: .battlenet, bottle: plan.bottleName, slug: slug,
                cellarBinary: AppBundle.resolveCellarBinary())
            print(Term.green("Created ") + bundle.app.path)
        }
    }

    // MARK: configure

    struct Configure: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Re-apply Cellar's Battle.net settings (hardware acceleration off, streaming off).",
            discussion: """
            The client rewrites its own config on exit and an update can undo these. If the login
            window comes up blank, spinning or white, run this and reopen Battle.net.
            """)
        @Argument(help: "Profile slug.") var slug: String

        func run() throws {
            let plan = try Game.plan(slug: slug)
            try requireBattleNetProfile(plan)
            guard BattleNetBottle.isInstalled(in: plan.prefix) else {
                throw CellarError.invalidArgument(
                    "Battle.net isn't installed in this bottle. Run: cellar setup --profile \(slug)")
            }
            if BattleNetBottle.isRunning {
                print(Term.yellow("Quit Battle.net first") + " — it rewrites its config on exit and would undo this.")
                return
            }
            try BattleNetBottle.writeClientConfig(in: plan.prefix)
            print(Term.green("Applied.") + Term.dim("  Hardware acceleration off, streaming off, client stays open on launch."))
        }
    }
}

/// Guard: this command group only makes sense for a profile that actually comes from Battle.net.
/// Saying so plainly beats a confusing failure three steps later.
private func requireBattleNetProfile(_ plan: GamePlan) throws {
    guard plan.store == .battlenet else {
        let alternative = plan.store == .steam ? "cellar steam open \(plan.slug)"
                                              : "cellar launch \(plan.slug)"
        throw CellarError.invalidArgument(
            "'\(plan.slug)' is a \(plan.store.displayName) game, not a Battle.net one. Try: \(alternative)")
    }
}
