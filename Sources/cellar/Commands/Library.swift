import ArgumentParser
import CellarKit

/// Your games — not Cellar's catalogue.
struct LibraryCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "library",
        abstract: "List the games you own that Cellar can run.",
        discussion: """
        Nothing is listed until a store is signed in, and then only what that store confirms you
        own. Steam is asked with the same session that would do the downloading, so "owned" means
        "Cellar can install this" rather than "an id turned up in a list".

        Battle.net publishes neither a sign-in state nor what you own, so Cellar asks you instead:
        `cellar battlenet add` puts Blizzard's games in the library, and they are marked as
        unchecked, because that is what they are.
        """)

    @Flag(name: .long, help: "Ask the stores again instead of using the cached answers.")
    var refresh = false

    @Flag(name: .long, help: "Show every profile Cellar ships, owned or not.")
    var all = false

    func run() throws {
        if refresh {
            print(Term.dim("Asking your stores what you own…"))
            StoreLibrary.refreshAll { print("  " + Term.dim($0)) }
        }

        let games = Game.summaries()
        let visible = all ? games : games.filter(\.isVisible)

        if visible.isEmpty {
            // Three stores, three different ways in. Naming only Steam's here is how a GOG player
            // gets told to scan a QR code that has nothing to do with their missing games.
            print(Term.bold("Nothing to show yet."))
            print("  " + SteamAccount.state.summary)
            print(Term.dim("  cellar steam login      Steam, by QR code from your phone"))
            print(Term.dim("  cellar gog login        GOG, in a browser window"))
            print(Term.dim("  cellar battlenet add    Battle.net, which publishes nothing to check"))
            print(Term.dim("  cellar library --refresh"))
            return
        }

        for store in GameStore.allCases.sorted(by: { $0.sortIndex < $1.sortIndex }) {
            let inStore = visible.filter { $0.store == store }
            guard !inStore.isEmpty else { continue }
            print(Term.bold(store.descriptor.sectionTitle) + "  " + Term.dim(sectionNote(for: store)))
            for game in inStore {
                print("  \(mark(game.ownership)) \(game.name.padding(toLength: 38, withPad: " ", startingAt: 0))"
                      + Term.dim(detail(game)))
            }
        }

        // The gap is the point: a store Cellar hasn't been let into is where a player finds out
        // *why* their games are missing, so it gets a line rather than silence. Every store, not
        // just the ones that can answer about ownership — Battle.net's games are now withheld too,
        // and silence there is exactly the confusion this line exists to prevent.
        for store in GameStore.allCases where store != .standalone {
            // Grouped by who *answers*, not by who sold it: a DRM-free game bought on Steam is
            // filed under "no store" and is still waiting on the Steam sign-in.
            let hidden = games.filter { $0.gatingStore == store && !$0.isVisible }
            guard !hidden.isEmpty, !all else { continue }
            let unchecked = hidden.filter { if case .unknown = $0.ownership { return true }; return false }
            if !unchecked.isEmpty, let fix = unchecked[0].verdict.fix {
                let noun = "game\(unchecked.count == 1 ? "" : "s")"
                let why = StoreLibrary.isConnected(store) ? "not checked" : "waiting on \(store.displayName)"
                print(Term.yellow("\(unchecked.count) \(store.displayName) \(noun) \(why).") + " " + fix)
            }
        }
    }

    private func sectionNote(for store: GameStore) -> String {
        switch store {
        case .steam:      return SteamAccount.state.accountName.map { "signed in as \($0)" } ?? "not signed in"
        case .gog:        return GOGAuth.isSignedIn ? "signed in" : "not signed in"
        case .battlenet:  return "added by you — Cellar can't check what you own here"
        case .standalone: return "no store"
        }
    }

    /// Three marks, not two: a game Cellar *verified* you own is a different claim from one it
    /// could not check, and drawing both as ✓ would make the second a lie.
    private func mark(_ ownership: Ownership) -> String {
        switch ownership {
        case .owned:     return Term.green("✓")
        case .notOwned:  return Term.yellow("•")
        case .unknown:   return Term.dim("·")
        }
    }

    private func detail(_ game: GameSummary) -> String {
        switch game.ownership {
        case .notOwned: return "not in your library"
        case .unknown(let why): return why
        case .owned:
            if game.gameInstalled { return "installed — cellar launch \(game.slug)" }
            return "owned, not installed — cellar install \(game.slug)"
        }
    }
}
