import CellarDomain
import Foundation
import Testing
@testable import CellarKit

/// What the library sidebar shows. This used to live inside the app's `Library` view model, where
/// checking it meant launching the app; it is pure now, so it is checked here.
@Suite
struct LibraryQueryTests {

    private func game(_ slug: String, store: GameStore = .steam, installed: Bool = true,
                      draft: Bool = false, lastPlayed: Date? = nil,
                      ownership: Ownership = .owned) -> GameSummary {
        var summary = GameSummary(
            slug: slug, name: slug.capitalized, store: store, appID: 1, iconPath: nil,
            runnerInstalled: true, clientInstalled: true, account: "kenneth", gameInstalled: installed,
            bottleExists: true, running: false, productCode: nil, ownership: ownership,
            artworkAppID: nil, artPortraitURL: nil, artHeroURL: nil, needsClientAtRuntime: true,
            facts: GameFacts(developer: nil, released: nil, engine: nil, graphicsAPI: nil,
                             anticheat: nil, drm: nil, online: nil, requiresAccount: nil,
                             status: nil, notes: nil),
            runnerID: "wineforge", backend: "d3dmetal", bottleName: slug)
        summary.isDraft = draft
        if let lastPlayed { summary.playtime = Playtime.Record(lastPlayed: lastPlayed) }
        return summary
    }

    private var library: [GameSummary] {
        [game("planet", store: .steam),
         game("fallout", store: .steam, installed: false),
         game("diablo", store: .battlenet),
         game("witcher", store: .gog, installed: false),
         game("guessed", store: .steam, draft: true)]
    }

    // MARK: - Filtering

    @Test("Search matches the name, ignoring case")
    func search() {
        let shown = LibraryQuery(text: "PLAN").filtered(library).map(\.slug)
        #expect(shown == ["planet"])
    }

    @Test("Installed and Not installed split the library between them")
    func installedFilter() {
        let installed = Set(LibraryQuery(filter: .installed).filtered(library).map(\.slug))
        let missing = Set(LibraryQuery(filter: .notInstalled).filtered(library).map(\.slug))
        #expect(installed == ["planet", "diablo", "guessed"])
        #expect(missing == ["fallout", "witcher"])
        #expect(installed.isDisjoint(with: missing))
    }

    @Test("A store scope shows only that store's games")
    func storeScope() {
        #expect(LibraryQuery(store: .gog).filtered(library).map(\.slug) == ["witcher"])
    }

    @Test("Only a narrowed list offers to clear its filters")
    func isFiltered() {
        #expect(!LibraryQuery().isFiltered)
        #expect(LibraryQuery(text: "x").isFiltered)
        #expect(LibraryQuery(filter: .installed).isFiltered)
        #expect(LibraryQuery(store: .steam).isFiltered)
        #expect(!LibraryQuery(sort: .recent).isFiltered, "sorting hides nothing")
    }

    // MARK: - Sections and order

    @Test("Sections follow the stores' fixed order, and guessed profiles come after every tested one")
    func sections() {
        let ids = LibraryQuery().sections(library).map(\.id)
        #expect(ids == ["steam", "battlenet", "gog", "steam-guessed"])
    }

    @Test("A store with no game has no section and no filter chip")
    func emptyStores() {
        let steamOnly = library.filter { $0.store == .steam }
        #expect(LibraryQuery().sections(steamOnly).allSatisfy { $0.store == .steam })
        #expect(LibraryQuery.presentStores(in: steamOnly) == [.steam])
    }

    @Test("Recently played puts the latest first, and a game never played after every played one")
    func recentSort() {
        let now = Date()
        let games = [game("alpha"), game("bravo", lastPlayed: now.addingTimeInterval(-3600)),
                     game("charlie", lastPlayed: now)]
        #expect(LibraryQuery(sort: .recent).ordered(games).map(\.slug) == ["charlie", "bravo", "alpha"])
        #expect(LibraryQuery(sort: .name).ordered(games).map(\.slug) == ["alpha", "bravo", "charlie"])
    }

    @Test("The sort's raw values are what the app has stored since before this type existed")
    func sortRawValues() {
        #expect(LibraryQuery.Sort(rawValue: "Name") == .name)
        #expect(LibraryQuery.Sort(rawValue: "Recently played") == .recent)
    }

    // MARK: - Keyboard

    @Test("↑ and ↓ stop at the ends rather than wrapping, as Finder does")
    func moving() {
        let order = ["a", "b", "c"]
        #expect(LibraryQuery.moving("b", by: 1, in: order) == "c")
        #expect(LibraryQuery.moving("c", by: 1, in: order) == "c")
        #expect(LibraryQuery.moving("a", by: -1, in: order) == "a")
        #expect(LibraryQuery.moving(nil, by: 1, in: order) == "a")
        #expect(LibraryQuery.moving(nil, by: -1, in: order) == "c")
        #expect(LibraryQuery.moving("gone", by: 1, in: order) == "a")
        #expect(LibraryQuery.moving("b", by: 1, in: []) == "b")
    }

    // MARK: - Why the library is empty

    private func snapshot(withheld: [GameSummary], steam: SteamAccount.State = .signedOut,
                          gogSignedIn: Bool = false) -> LibrarySnapshot {
        LibrarySnapshot(games: [], withheld: withheld, steam: steam,
                        hasConnectedStore: false, gogSignedIn: gogSignedIn)
    }

    @Test("Battle.net alone asks for the player's word, not a sign-in")
    func battleNetReason() {
        let reason = snapshot(withheld: [game("diablo", store: .battlenet, ownership: .unknown("x"))]).signInReason
        #expect(reason.hasPrefix("Blizzard publishes nothing"))
    }

    @Test("Unchecked Steam games with Steam signed out name the Steam sign-in")
    func steamReason() {
        let state = SteamAccount.State.signedOut
        let reason = snapshot(withheld: [game("planet", ownership: .unknown("x"))], steam: state).signInReason
        #expect(reason == state.summary)
    }

    @Test("Unchecked GOG games ask for the GOG sign-in only while signed out")
    func gogReason() {
        let witcher = game("witcher", store: .gog, ownership: .unknown("x"))
        #expect(snapshot(withheld: [witcher]).signInReason.hasPrefix("Not signed in to GOG"))
        #expect(!snapshot(withheld: [witcher], gogSignedIn: true).signInReason.hasPrefix("Not signed in"))
    }

    @Test("Games a store said no to never tell a signed-in player to sign in")
    func notOwnedReason() {
        let reason = snapshot(withheld: [game("planet", ownership: .notOwned)]).signInReason
        #expect(reason == "Nothing your stores confirmed you own is supported yet.")
    }
}
