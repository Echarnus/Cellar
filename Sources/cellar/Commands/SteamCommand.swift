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
        subcommands: [Open.self, Login.self, Key.self, Share.self, Install.self, Status.self, App.self, Add.self,
                      EnableWindowsPlatform.self, DisableWindowsPlatform.self]
    )

    // MARK: key (the Web API key that makes "which games do I own?" answerable)

    struct Key: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Store your Steam Web API key, so Cellar can list the games you own.",
            discussion: """
            Steam has no OAuth for entitlements, and an anonymous request for a library is refused
            unless the profile's game details are public. A key issued to your own account answers
            for your own library either way — it is free, it takes one page, and Cellar keeps it in
            your keychain beside the sign-in tokens.

            Get one at https://steamcommunity.com/dev/apikey, then:
              cellar steam key --set <key>
              cellar library --refresh

            Without a key Cellar still works; it just cannot list Steam games it has not seen
            installed, and says so rather than showing you games you may not own.
            """)

        @Option(name: .long, help: "The 32-character key from steamcommunity.com/dev/apikey.")
        var set: String?

        @Flag(name: .long, help: "Forget the stored key.")
        var forget = false

        func run() throws {
            if forget {
                try SteamWebAPI.forgetKey()
                StoreLibrary.clearCache(.steam)
                print(Term.green("Forgotten.") + Term.dim(" Cellar will list only the Steam games it can see installed."))
                return
            }
            guard let set else {
                if SteamWebAPI.hasKey {
                    print(Term.green("✓ ") + "A Steam Web API key is stored."
                        + Term.dim("  Replace it with --set, remove it with --forget."))
                } else {
                    print(Term.yellow("• ") + "No key stored. Get one at " + SteamWebAPI.keyPage
                        + ", then: cellar steam key --set <key>")
                }
                return
            }
            try SteamWebAPI.setKey(set)
            print(Term.green("Saved to your keychain."))
            if let library = try StoreLibrary.refresh(.steam, progress: { print(Term.dim("  " + $0)) }) {
                print(Term.green("✓ ") + "\(library.totalCount) games in \(library.source).")
            }
        }
    }

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

    // MARK: login (QR device flow, for the download path)

    struct Login: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Sign in to Steam by QR code, for downloads that skip the Windows client.",
            discussion: """
            Uses Steam's own device-authorization flow — the same QR the real client shows. Cellar
            never sees a password: you approve the sign-in in the Steam mobile app, and Steam hands
            back a token that every later `cellar fetch-depot` reuses silently.

            This signs in the *download* path. A game with Steamworks or Denuvo DRM also talks to a
            running Steam client when it launches, and that client has its own sign-in — one window,
            once, shared by every bottle: cellar steam open <slug>
            """)

        @Flag(help: "Sign out instead: forget the stored download session.")
        var forget = false

        func run() throws {
            if forget {
                try DepotTool.forgetSession()
                print(Term.green("Signed out.") + " Downloads will ask again: cellar steam login")
                return
            }
            if DepotTool.hasStoredSession {
                print(Term.green("Already signed in for downloads.")
                    + Term.dim(" Replace it by signing out first: cellar steam login --forget"))
                return
            }
            print(Term.bold("Sign in to Steam"))
            print(Term.dim("  Scan the QR code below with the Steam mobile app. Nothing to type."))
            try DepotTool.signIn(credentials: .qr) { print("  " + $0) }
            if DepotTool.hasStoredSession {
                print(Term.green("Signed in.") + " Downloads won't ask again: cellar fetch-depot <slug>")
            } else {
                print(Term.yellow("Sign-in didn't complete.") + " Run it again: cellar steam login")
            }
        }
    }

    // MARK: share (one Steam install for every bottle)

    struct Share: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Point every bottle at one shared Steam install — one sign-in, one download.",
            discussion: """
            A bottle is per-game so each game keeps its own registry, runner and Wine version. The
            Steam *client* is not per-game — it belongs to your account — so Cellar keeps one copy in
            ~/Library/Application Support/Cellar/shared/steam and links every bottle to it. One
            sign-in, one 1.4 GB client, and a game you own downloaded once instead of per bottle.

            Safe to re-run, and it never deletes a download: the richest existing install is promoted
            into the shared one, and any other is moved aside with the path printed so you can
            reclaim the space yourself.
            """)

        func run() throws {
            print(Term.bold("Sharing one Steam install across every bottle"))
            let linked = try SteamBottle.adoptSharedInstall { print("  " + Term.dim($0)) }
            if linked == 0 {
                print(Term.green("Nothing to do.") + " Every bottle already uses the shared install.")
            } else {
                print(Term.green("Linked \(linked) bottle\(linked == 1 ? "" : "s").")
                    + " Sign in once with: cellar steam open <slug>")
            }
            print(Term.dim("  shared install: \(SteamBottle.sharedInstall.path)"))
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
