import ArgumentParser
import CellarKit
import Foundation

struct GogCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "gog",
        abstract: "The GOG plugin: sign in once with OAuth, browse what you own, install and play.",
        discussion: """
        GOG is the store where signing in once actually covers everything. Steam and Battle.net both
        need their own client inside the bottle — a download, a window to drive, and a session the
        game talks to while it runs. GOG is an HTTP API and a token: its catalogue is DRM-free, so
        Cellar downloads the installer you own, runs it, and launches the game with nothing beside it.

          cellar gog login              sign in (opens gog.com, once, for your whole library)
          cellar gog library            everything you own that runs on Windows
          cellar gog install <slug>     download + install a profile's game
          cellar launch <slug>          play

        Cellar only ever downloads games you own, and GOG's own API is the only thing it talks to.
        """,
        subcommands: [Login.self, Logout.self, Status.self, Library.self, Install.self]
    )

    // MARK: login

    struct Login: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Sign in to GOG. Opens gog.com in your browser; paste back the address it lands on.",
            discussion: """
            GOG's sign-in ends by redirecting to an embed.gog.com address carrying a one-time code.
            There is no custom URL scheme to catch that in a terminal, so the honest flow is: sign in
            in your browser, then copy the address bar back here. The Cellar app does this in a window
            and catches the redirect for you.
            """)

        @Option(help: "The address GOG redirected to (or just the code), if you already have it.")
        var code: String?

        func run() throws {
            if GOGAuth.isSignedIn, let name = try? GOGAuth.username() {
                print(Term.green("Already signed in to GOG as \(name).")
                    + Term.dim(" Sign out with: cellar gog logout"))
                return
            }

            let pasted: String
            if let code {
                pasted = code
            } else {
                print(Term.bold("Sign in to GOG"))
                print("  Opening " + Term.dim("gog.com") + " in your browser.")
                print("  After signing in the page will look blank — that is expected.")
                print("  Copy the whole address from the address bar and paste it below.\n")
                Shell.run("/usr/bin/open", [GOG.authorizationURL.absoluteString])
                print(Term.dim("  If the browser didn't open: ") + GOG.authorizationURL.absoluteString + "\n")
                print("Address (or code): ", terminator: "")
                pasted = readLine() ?? ""
            }

            guard let authCode = GOG.authorizationCode(from: pasted) else {
                throw CellarError.invalidArgument(
                    "That doesn't contain a GOG sign-in code. Paste the full address the browser ended on — it contains 'code='.")
            }
            let name = try GOGAuth.signIn(authorizationCode: authCode)
            GOGAuth.cacheUsername(name)
            print(Term.green("Signed in as \(name).") + " This covers every GOG game — no per-game sign-in.")
            // Read the library straight away: the whole point of signing in is that your games
            // appear, and making the player run a second command for that is a step too many.
            if let library = try? StoreLibrary.refresh(.gog) {
                print(Term.dim("  \(library.totalCount) games in your GOG library."))
            }
            print(Term.dim("  See what you own: cellar library"))
        }
    }

    // MARK: logout

    struct Logout: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Sign out of GOG (removes the token from your keychain).")

        func run() throws {
            try GOGAuth.signOut()
            GOGAuth.cacheUsername(nil)
            // The cached library is that account's, so it goes with the sign-in. Leaving it behind
            // would show the next player at this Mac somebody else's games.
            StoreLibrary.clearCache(.gog)
            print(Term.green("Signed out of GOG.") + " Installed games keep working; downloads need a sign-in.")
        }
    }

    // MARK: status

    struct Status: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Whether you're signed in to GOG, and as whom.")

        func run() throws {
            guard GOGAuth.isSignedIn else {
                print(Term.yellow("• Not signed in to GOG.") + " Sign in with: cellar gog login")
                return
            }
            // Cellar holds this token, so it can name the account — and a stale one is worth saying.
            do {
                let name = try GOGAuth.username()
                GOGAuth.cacheUsername(name)
                print(Term.green("✓ Signed in to GOG as \(name)."))
            } catch {
                print(Term.yellow("• Signed in to GOG, but the session is stale.")
                    + " Sign in again: cellar gog login")
            }
        }
    }

    // MARK: library

    struct Library: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "List the GOG games you own that have a Windows build.")

        @Option(help: "Stop after this many (the API is one call per game for details).")
        var limit: Int = 40

        func run() throws {
            guard GOGAuth.isSignedIn else {
                throw CellarError.invalidArgument("Not signed in to GOG. Run: cellar gog login")
            }
            let owned = try GOGLibrary.ownedProductIDs()
            print(Term.bold("\(owned.count) games in your GOG library")
                + Term.dim(owned.count > limit ? "  (showing the first \(limit) — raise it with --limit)" : ""))

            var shown = 0
            for id in owned.prefix(limit) {
                guard let product = try? GOGLibrary.product(id: id) else {
                    print("  " + Term.dim("\(id) — GOG didn't answer for this one"))
                    continue
                }
                let mark = product.hasWindowsInstaller ? Term.green("✓") : Term.dim("·")
                let note = product.hasWindowsInstaller ? "" : Term.dim("  no Windows build")
                print("  \(mark) \(product.title)\(note)")
                print("    " + Term.dim("gog_product_id = \(product.id)   slug = \(product.slug)"))
                shown += 1
            }
            print(Term.dim("\n  A game needs a profile before Cellar can run it — copy profiles/witcher-3.toml"))
            print(Term.dim("  and set gog_product_id, exe and name. \(shown) listed."))
        }
    }

    // MARK: install

    struct Install: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Download an owned GOG game and install it into its bottle.")
        @Argument(help: "Profile slug.") var slug: String

        func run() throws {
            let plan = try Game.plan(slug: slug)
            guard plan.store == .gog else {
                throw CellarError.invalidArgument(
                    "'\(slug)' is a \(plan.store.displayName) game, not a GOG one.")
            }
            guard GOGAuth.isSignedIn else {
                throw CellarError.invalidArgument("Not signed in to GOG. Run: cellar gog login")
            }
            // Setup is idempotent, so running it here means "install" works from a cold start.
            print(Term.bold("Installing \(plan.name) from GOG"))
            _ = try Game.setUp(plan) { print("  " + Term.dim($0)) }
            try Game.installGame(plan) { print("  " + Term.dim($0)) }
            print(Term.green("Ready.") + " Play with: cellar launch \(slug)  (no store client at all)")
        }
    }
}
