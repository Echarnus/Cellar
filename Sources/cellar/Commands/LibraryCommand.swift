import ArgumentParser
import CellarKit

/// `cellar library` — the games this player may actually play, and nothing else.
///
/// The CLI half of the app's main screen, and the reason the rule lives in `CellarKit`: a game is
/// shown when the store that gates it is connected and the player is not known not to own it. If
/// the two surfaces ever disagree about which games those are, one of them is lying to somebody.
struct LibraryCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "library",
        abstract: "Show the games you own, per store — and how to see the rest.",
        discussion: """
        Cellar lists your games, not its catalogue. A store's games appear once you have connected
        it (cellar accounts), and only the ones the store confirms you own:

          Steam       exact, once Cellar can ask — a Web API key (cellar steam key) or a public
                      profile. Until then only the games already installed can be confirmed.
          GOG         exact. One call returns your whole library.
          Battle.net  Blizzard publishes no library at all, so Cellar cannot check and says so
                      instead of guessing.
        """)

    @Flag(name: .long, help: "Ask each connected store for your library again before listing.")
    var refresh = false

    @Flag(name: .long, help: "List every profile Cellar ships, including games you may not own.")
    var all = false

    func run() throws {
        if refresh {
            for store in [GameStore.steam, .gog] where StoreLibrary.status(store).isConnected {
                do {
                    _ = try StoreLibrary.refresh(store) { print(Term.dim("  \($0)")) }
                } catch {
                    print(Term.yellow("  \(store.displayName): ") + "\(error.localizedDescription)")
                }
            }
        }

        let access = StoreLibrary.access()
        let games = Game.summaries()

        if all {
            print(Term.bold("Every profile Cellar ships") + Term.dim("  (not a claim that you own them)"))
            for game in games.sorted(by: { $0.name < $1.name }) {
                let mark = access.isVisible(game) ? Term.green("✓") : Term.dim("·")
                print("  \(mark) \(pad(game.name, 30)) \(Term.dim(game.store.displayName))")
            }
            return
        }

        print(Term.bold("Your library"))

        if access.hasNoConnection {
            print()
            print("  Nothing yet — Cellar shows games once you connect the store they came from.")
            print()
            print("    " + Term.bold("cellar steam login") + Term.dim("        Steam, by QR code from your phone"))
            print("    " + Term.bold("cellar gog login") + Term.dim("          GOG, in a browser window"))
            print("    " + Term.bold("cellar battlenet connect") + Term.dim("  Battle.net, which publishes nothing to check"))
            return
        }

        var shown = 0
        for store in GameStore.allCases.sorted(by: { $0.sortIndex < $1.sortIndex }) where store != .standalone {
            let status = access.status(store)
            let inStore = games.filter { $0.gatingStore == store }
            guard status.isConnected || !inStore.isEmpty else { continue }

            print()
            print("  " + storeHeading(store, status: status))
            guard status.isConnected else {
                print("      " + Term.dim(signInHint(store)))
                continue
            }

            let visible = inStore.filter { access.isVisible($0) }.sorted { $0.name < $1.name }
            shown += visible.count
            for game in visible {
                print("      \(pad(game.name, 30)) \(Term.dim(game.statusWord))")
            }
            // Only claim "none of them" when the store gave a complete answer. Before that the note
            // below is the truth: Cellar hasn't looked, which is not the same as nothing being there.
            if visible.isEmpty, status.library?.isComplete == true {
                print("      " + Term.dim("None of the games Cellar supports are in your \(store.displayName) library."))
            }
            if let note = status.libraryNote {
                print("      " + Term.yellow(note))
                if store == .steam, !SteamWebAPI.hasKey {
                    print("      " + Term.dim("cellar steam key --set <key>   from \(SteamWebAPI.keyPage)"))
                }
            }
        }

        print()
        let storeCount = access.connectedStores.count
        print(Term.dim("\(shown) game\(shown == 1 ? "" : "s") · \(storeCount) connected store\(storeCount == 1 ? "" : "s")"))
    }

    /// A store's line: mark, name, and the honest account/library summary beside it.
    private func storeHeading(_ store: GameStore, status: StoreStatus) -> String {
        let mark = status.isConnected ? Term.green("✓") : Term.yellow("•")
        var detail: [String] = []
        if let account = status.accountName { detail.append("signed in as \(account)") }
        else if status.isConnected { detail.append("connected") }
        if let library = status.library, library.isComplete {
            detail.append("\(library.totalCount) game\(library.totalCount == 1 ? "" : "s") in \(library.source)")
        }
        guard !detail.isEmpty else { return "\(mark) \(store.displayName)" }
        return "\(mark) \(pad(store.displayName, 12)) \(Term.dim(detail.joined(separator: " · ")))"
    }

    private func signInHint(_ store: GameStore) -> String {
        switch store {
        case .steam:      return "not connected — cellar steam login"
        case .gog:        return "not connected — cellar gog login"
        case .battlenet:  return "not connected — cellar battlenet connect"
        case .standalone: return ""
        }
    }

    private func pad(_ text: String, _ width: Int) -> String {
        text.count >= width ? text : text + String(repeating: " ", count: width - text.count)
    }
}
