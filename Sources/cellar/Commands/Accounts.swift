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

          Steam       one shared client for every bottle, so one sign-in. Read from loginusers.vdf.
          GOG         Cellar holds the OAuth token, so it knows the account name.
          Battle.net  publishes nothing readable. Cellar never claims to know.

        Steam's account is one row. Indented under it is what that one account currently reaches —
        client-free downloads, and the full owned-games list — which are separate credentials Steam
        will not merge, but not separate accounts, and never shown as separate sign-ins.
        """)

    func run() throws {
        print(Term.bold("Store accounts"))

        // Steam — one account, one row. Its two extra credentials (the QR download session and the
        // Web API key) are capabilities of that account, so they are indented under it rather than
        // printed as two more sign-ins. See `AccountsView.steamCard` for the same shape in the app.
        let steamAccount = SteamBottle.sharedLoggedInAccount
        row(state: steamAccount != nil ? .yes : .no,
            store: "Steam",
            detail: steamAccount.map { "signed in as \($0) — shared by every Steam game" }
                ?? "not signed in — cellar steam open <slug>")
        if !SteamBottle.isSharedInstallPresent {
            print("    " + Term.dim("no shared Steam install yet — cellar steam share"))
        }

        capability(done: DepotTool.hasStoredSession,
                   name: "downloads",
                   detail: DepotTool.hasStoredSession
                    ? "no client needed — fetch-depot won't ask again"
                    : "sign in once to fetch game files without the client — cellar steam login")

        let steamLibrary = StoreLibrary.cached(.steam)
        if steamAccount == nil {
            capability(done: false, name: "your library",
                       detail: "sign in first — Cellar has to know whose library to ask about")
        } else if let steamLibrary, steamLibrary.isComplete {
            capability(done: true, name: "your library",
                       detail: "\(steamLibrary.totalCount) games, read from \(steamLibrary.source)")
        } else if let steamLibrary {
            let n = steamLibrary.keys.count
            capability(done: false, name: "your library",
                       detail: "only the \(n) installed game\(n == 1 ? "" : "s") can be confirmed — cellar steam key --set <key>")
        } else {
            capability(done: false, name: "your library",
                       detail: "not read yet — cellar library --refresh")
        }

        // GOG — a token Cellar owns, so the account name is a fact.
        if GOGAuth.isSignedIn {
            let name = (try? GOGAuth.username()) ?? GOGAuth.cachedUsername
            if let name {
                GOGAuth.cacheUsername(name)
                let owned = StoreLibrary.cached(.gog).map { " · \($0.totalCount) games" } ?? ""
                row(state: .yes, store: "GOG", detail: "signed in as \(name) — covers your whole library\(owned)")
            } else {
                row(state: .unknown, store: "GOG", detail: "signed in, but the session is stale — cellar gog login")
            }
        } else {
            row(state: .no, store: "GOG", detail: "not signed in — cellar gog login")
        }

        // Battle.net — the honest row. Blizzard publishes no readable signed-in state, so this is a
        // `·` forever and never a ✗ (see skills/ux.md, "Honesty is a UX rule"). Connecting it is the
        // player's word about having an account, which is a different claim from being signed in —
        // so it stays a `·` even then, and the detail says which of the two it is reporting.
        row(state: .unknown, store: "Battle.net",
            detail: BattleNetAccess.isConnected
                ? "you told Cellar you have an account — Blizzard publishes nothing to check"
                : "Blizzard publishes nothing to check — cellar battlenet connect")

        print()
        print(Term.dim("  Which games this lets you see: cellar library"))
    }

    private enum State { case yes, no, unknown }

    /// A capability of the account printed just above — indented, and marked with the same ✓/•
    /// vocabulary, so it reads as "this account can/cannot" rather than as another sign-in.
    private func capability(done: Bool, name: String, detail: String) {
        let mark = done ? Term.green("✓") : Term.yellow("•")
        print("      \(mark) \(name.padding(toLength: 13, withPad: " ", startingAt: 0)) " + Term.dim(detail))
    }

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
