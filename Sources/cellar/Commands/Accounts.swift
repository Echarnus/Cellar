import ArgumentParser
import CellarKit

/// One screen for "who am I signed in as, everywhere" — the CLI half of the app's Accounts window.
///
/// Sign-in used to be something you discovered per game, which is how you end up signing in three
/// times for three Steam games. It is an account-level fact, so it gets an account-level command.
struct Accounts: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "accounts",
        abstract: "Show which stores you're signed in to, and how to sign in to the rest.",
        discussion: """
        Each store answers "who is signed in?" differently, and Cellar reports exactly what it can
        actually check — never a ✓ for a guess:

          Steam       one sign-in, by QR, held by Cellar. It covers what you own and what it can
                      download. Sessions expire; this says so when one has.
          GOG         Cellar holds the OAuth token, so it knows the account name.
          Battle.net  publishes nothing readable. Cellar never claims to know.
        """)

    func run() throws {
        print(Term.bold("Store accounts"))

        // Steam — one account, one row. It used to be three (the client's window, the download
        // token, a Web API key), which read as being asked to sign in to Steam three times.
        switch SteamAccount.state {
        case .signedIn(let account, _, _):
            row(state: .yes, store: "Steam", detail: "signed in as \(account)")
            print("    " + Term.dim(SteamAccount.state.summary))
        case .expired:
            row(state: .no, store: "Steam", detail: SteamAccount.state.summary)
            print("    " + Term.dim("cellar steam login"))
        case .signedOut:
            row(state: .no, store: "Steam", detail: "not signed in — cellar steam login")
        }
        // The in-bottle Windows client is not a second account: it is a runtime dependency of the
        // games whose DRM talks to it. Reported as a fact about the machine, not as a sign-in step.
        if let inBottle = SteamBottle.sharedLoggedInAccount {
            print("    " + Term.dim("Windows Steam client: signed in as \(inBottle), for games whose DRM needs it running"))
        }

        // GOG — a token Cellar owns, so the account name is a fact.
        if GOGAuth.isSignedIn {
            let name = (try? GOGAuth.username()) ?? GOGAuth.cachedUsername
            if let name {
                GOGAuth.cacheUsername(name)
                row(state: .yes, store: "GOG", detail: "signed in as \(name) — covers your whole library")
            } else {
                row(state: .unknown, store: "GOG", detail: "signed in, but the session is stale — cellar gog login")
            }
        } else {
            row(state: .no, store: "GOG", detail: "not signed in — cellar gog login")
        }

        // Battle.net — the honest row. Blizzard publishes no readable signed-in state, so this is a
        // `·` forever and never a ✓ or a ✗ (see skills/ux.md, "Honesty is a UX rule"). The only
        // thing that varies is whether the player has told Cellar the account exists, which is what
        // decides whether Blizzard's games are listed at all.
        if StoreLibrary.BattleNetAccount.isAdded {
            row(state: .unknown, store: "Battle.net",
                detail: "added by you — its games are listed. Cellar can't check it; you sign in inside the client")
            print("    " + Term.dim("cellar battlenet forget  to hide them again"))
        } else {
            row(state: .unknown, store: "Battle.net",
                detail: "not added — its games stay hidden. cellar battlenet add")
        }
    }

    private enum State { case yes, no, unknown }

    private func row(state: State, store: String, detail: String) {
        let mark: String
        switch state {
        case .yes:     mark = Term.green("✓")
        case .no:      mark = Term.yellow("•")
        case .unknown: mark = Term.dim("·")
        }
        print("  \(mark) \(store.padding(toLength: 17, withPad: " ", startingAt: 0)) \(detail)")
    }
}
