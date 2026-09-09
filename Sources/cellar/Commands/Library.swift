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

        Battle.net publishes neither a sign-in state nor what you own, so its games are shown with
        that said out loud — hiding them would just mean pretending Battle.net doesn't exist.
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
            print(Term.bold("Nothing to show yet."))
            print("  " + SteamAccount.state.summary)
            print(Term.dim("  Sign in:  cellar steam login") )
            print(Term.dim("  Then:     cellar library --refresh"))
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

        // The gap is the point: a store that could answer and hasn't is where a player finds out
        // *why* their games are missing, so it gets a line rather than silence.
        for store in GameStore.allCases where store.canAnswerOwnership {
            // Grouped by who *answers*, not by who sold it: a DRM-free game bought on Steam is
            // filed under "no store" and is still waiting on the Steam sign-in.
            let hidden = games.filter { $0.gatingStore == store && !$0.isVisible }
            guard !hidden.isEmpty, !all else { continue }
            let unchecked = hidden.filter { if case .unknown = $0.ownership { return true }; return false }
            if !unchecked.isEmpty {
                print(Term.yellow("\(unchecked.count) \(store.displayName) game\(unchecked.count == 1 ? "" : "s") not checked.")
                      + " " + (StoreLibrary.verdict(store: store, ownership: unchecked[0].ownership).fix ?? ""))
            }
        }
    }

    private func sectionNote(for store: GameStore) -> String {
        switch store {
        case .steam:      return SteamAccount.state.accountName.map { "signed in as \($0)" } ?? "not signed in"
        case .gog:        return GOGAuth.isSignedIn ? "signed in" : "not signed in"
        case .battlenet:  return "Cellar can't check what you own here"
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
