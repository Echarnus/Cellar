import ArgumentParser
import CellarKit

struct SteamCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "steam",
        abstract: "The Steam plugin: open Windows Steam in a bottle, install games, surface them natively.",
        discussion: """
        Steam's half of the store layer. Its Battle.net counterpart is `cellar battlenet`, shaped
        the same way — the two differ only where the stores genuinely do (Steam installs silently
        and publishes who is signed in; Battle.net does neither).
        """,
        subcommands: [Open.self, Install.self, Status.self, App.self, Add.self, EnableWindowsPlatform.self, DisableWindowsPlatform.self]
    )

    // MARK: app (Steam client as a macOS .app)

    struct App: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Create 'Steam (<bottle>).app' in ~/Applications that opens the bottle's Windows Steam.")
        @Argument(help: "Profile slug.") var slug: String

        func run() throws {
            let plan = try Game.plan(slug: slug)
            try requireSteamProfile(plan)
            let bundle = try AppBundle.generateStoreClient(
                store: .steam, bottle: plan.bottleName, slug: slug,
                cellarBinary: AppBundle.resolveCellarBinary())
            print(Term.green("Created ") + bundle.app.path)
        }
    }

    // MARK: status

    struct Status: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Report the bottle's Steam state: client updated, who is logged in, game installed.")
        @Argument(help: "Profile slug.") var slug: String

        func run() throws {
            let plan = try Game.plan(slug: slug)
            try requireSteamProfile(plan)
            let prefix = plan.prefix
            func row(_ label: String, _ ok: Bool, _ text: String) {
                print("  \(ok ? Term.green("✓") : Term.yellow("•")) \(label.padding(toLength: 16, withPad: " ", startingAt: 0)) \(text)")
            }
            print(Term.bold("Steam in bottle '\(plan.bottleName)'") + Term.dim("  (\(prefix.path))"))
            row("runner", RunnerManager.find(id: plan.runnerID) != nil, plan.runnerID)
            row("client", SteamBottle.isInstalled(in: prefix),
                SteamBottle.isInstalled(in: prefix)
                    ? (SteamBottle.isClientUpdated(in: prefix) ? "installed, self-updated" : "bootstrapper only — updates on first launch")
                    : "not installed")
            let account = SteamBottle.loggedInAccount(in: prefix)
            row("account", account != nil, account ?? "nobody logged in — cellar steam open \(slug)")
            row("running", SteamBottle.isRunning, SteamBottle.isRunning ? "yes" : "no")
            if let appID = plan.appID {
                let installed = SteamBottle.isGameInstalled(in: prefix, appID: appID)
                row("game", installed, installed ? "\(plan.name) installed (AppID \(appID))" : "\(plan.name) not installed — cellar steam install \(slug)")
            }
            print(Term.dim("  logs: \(SteamBottle.logsDirectory(in: prefix).path)"))
        }
    }

    // MARK: open

    struct Open: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Open the Windows Steam client inside a game's bottle (log in, browse, install).")
        @Argument(help: "Profile slug.") var slug: String

        func run() throws {
            let plan = try Game.plan(slug: slug)
            try requireSteamProfile(plan)
            let wine = try requireReadyBottle(plan)
            print(Term.dim("Launching Steam in bottle '\(plan.bottleName)'. A window will open — log in and install your games."))
            try SteamBottle.launchClient(runner: wine)
        }
    }

    // MARK: install (open the game's install dialog)

    struct Install: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Open the install dialog for the profile's game in the bottle's Steam.")
        @Argument(help: "Profile slug.") var slug: String

        func run() throws {
            let plan = try Game.plan(slug: slug)
            try requireSteamProfile(plan)
            guard let appID = plan.appID else {
                throw CellarError.invalidArgument("Profile '\(slug)' has no steam_appid.")
            }
            let wine = try requireReadyBottle(plan)
            print(Term.dim("Asking the bottle's Steam to install \(plan.name) (AppID \(appID))…"))
            try SteamBottle.installGame(runner: wine, appID: appID)
        }
    }

    // MARK: add (native Steam shortcut + .app)

    struct Add: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Add the game to the native macOS Steam library and ~/Applications as a .app.")
        @Argument(help: "Profile slug.") var slug: String

        func run() throws {
            let plan = try Game.plan(slug: slug)
            try requireSteamProfile(plan)
            let bundle = try AppBundle.generate(
                name: plan.name, slug: plan.slug, cellarBinary: AppBundle.resolveCellarBinary(),
                prefix: plan.prefix, appID: plan.appID)
            print(Term.green("Created ") + bundle.app.path)

            guard let configDir = SteamShortcuts.userdataConfigDir() else {
                print(Term.yellow("No Steam userdata found.")
                    + " The .app is ready; couldn't add a Steam shortcut (is native Steam installed and logged in?).")
                return
            }
            if SteamShortcuts.steamRunning {
                print(Term.yellow("Quit Steam first") + " — it rewrites shortcuts.vdf on exit and would clobber the new entry, then re-run this.")
                return
            }
            let appid = try SteamShortcuts.add(
                SteamShortcutEntry(appName: plan.name, launcherBinary: bundle.launcher), to: configDir)
            print(Term.green("Added '\(plan.name)' to your Steam library ")
                + Term.dim("(shortcut appid \(appid)). Restart Steam to see it with a Play button."))
        }
    }

    // MARK: native-platform trick (advanced)

    struct EnableWindowsPlatform: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "enable-windows-platform",
            abstract: "[Advanced] Make the NATIVE macOS Steam show Install for Windows-only games.")

        func run() throws {
            try SteamPlatformTrick.enable()
            print(Term.green("Wrote ") + SteamPlatformTrick.cfgPath.path)
            print(Term.yellow("Warning: ")
                + "this blocks Steam's self-update and can empty games that ship a macOS depot. "
                + "Undo with: cellar steam disable-windows-platform")
        }
    }

    struct DisableWindowsPlatform: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "disable-windows-platform",
            abstract: "Undo enable-windows-platform (lets native Steam self-update again).")

        func run() throws {
            try SteamPlatformTrick.disable()
            print(Term.green("Removed steam_dev.cfg."))
        }
    }
}

/// Guard: this command group only makes sense for a profile that actually comes from Steam.
/// Saying so plainly beats a confusing failure three steps later.
private func requireSteamProfile(_ plan: GamePlan) throws {
    guard plan.store == .steam else {
        let alternative = plan.store == .battlenet ? "cellar battlenet open \(plan.slug)"
                                                  : "cellar launch \(plan.slug)"
        throw CellarError.invalidArgument(
            "'\(plan.slug)' is a \(plan.store.displayName) game, not a Steam one. Try: \(alternative)")
    }
}

/// Shared guard: the bottle must have an installed runner and Windows Steam.
private func requireReadyBottle(_ plan: GamePlan) throws -> WineRunner {
    guard let wine = Game.wineRunner(plan) else {
        throw CellarError.invalidArgument(
            "Runner '\(plan.runnerID)' isn't installed. Run: cellar setup --profile \(plan.slug)")
    }
    guard SteamBottle.isInstalled(in: plan.prefix) else {
        throw CellarError.invalidArgument(
            "Windows Steam isn't installed in this bottle. Run: cellar setup --profile \(plan.slug)")
    }
    return wine
}
