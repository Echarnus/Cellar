import Foundation

/// What the library sidebar shows, worked out from the games and the player's search and filters —
/// no disk, no network, no SwiftUI, so every rule here is a unit test rather than something to
/// launch the app to see. The app's `LibraryStore` holds the state; this decides what it means.
public struct LibraryQuery: Equatable, Sendable {
    public enum Filter: String, CaseIterable, Identifiable, Sendable {
        case all = "All", installed = "Installed", notInstalled = "Not installed"
        public var id: String { rawValue }
    }

    /// Name, or most recently played first. The raw values are what the app remembers between
    /// launches, so they stay as they are.
    public enum Sort: String, CaseIterable, Identifiable, Sendable {
        case name = "Name", recent = "Recently played"
        public var id: String { rawValue }
    }

    public var text = ""
    public var filter: Filter = .all
    /// nil means "every store". The library's primary axis: which client a game needs decides what
    /// every button in the app will do next.
    public var store: GameStore?
    public var sort: Sort = .name

    public init(text: String = "", filter: Filter = .all, store: GameStore? = nil, sort: Sort = .name) {
        self.text = text
        self.filter = filter
        self.store = store
        self.sort = sort
    }

    /// Whether anything narrows the list, so "No games match" can offer the one way back.
    public var isFiltered: Bool { !text.isEmpty || filter != .all || store != nil }

    public func filtered(_ games: [GameSummary]) -> [GameSummary] {
        games.filter { game in
            (store == nil || game.store == store)
                && (text.isEmpty || game.name.localizedCaseInsensitiveContains(text))
                && {
                    switch filter {
                    case .all: return true
                    case .installed: return game.gameInstalled
                    case .notInstalled: return !game.gameInstalled
                    }
                }()
        }
    }

    /// Ordered by the chosen sort; a game never played sorts after every played one, by name.
    public func ordered(_ games: [GameSummary]) -> [GameSummary] {
        games.sorted { a, b in
            if sort == .recent, a.lastPlayed != b.lastPlayed {
                return (a.lastPlayed ?? .distantPast) > (b.lastPlayed ?? .distantPast)
            }
            return a.name < b.name
        }
    }

    /// The filtered library, grouped into store sections in a fixed order — never alphabetical,
    /// so a game doesn't move house when it is renamed.
    ///
    /// Games whose profile Cellar guessed (`DraftProfile`) come after every hand-made one, in
    /// sections of their own that say so — a guess never sits among the tested games.
    public func sections(_ games: [GameSummary]) -> [LibrarySection] {
        let shown = filtered(games)
        return [false, true].flatMap { guessed in
            GameStore.inLibraryOrder.compactMap { store in
                let inStore = ordered(shown.filter { $0.store == store && $0.isDraft == guessed })
                return inStore.isEmpty ? nil : LibrarySection(store: store, guessed: guessed, games: inStore)
            }
        }
    }

    /// Stores that actually have a game, so the filter never offers an empty result.
    public static func presentStores(in games: [GameSummary]) -> [GameStore] {
        GameStore.inLibraryOrder.filter { store in games.contains { $0.store == store } }
    }

    /// The ↑/↓ keys: the next game in the order the player sees them, stopping at either end rather
    /// than wrapping, as Finder does. With nothing selected, ↓ starts at the top and ↑ at the bottom.
    public static func moving(_ selected: String?, by offset: Int, in order: [String]) -> String? {
        guard !order.isEmpty else { return selected }
        guard let selected, let index = order.firstIndex(of: selected) else {
            return offset > 0 ? order.first : order.last
        }
        return order[min(max(index + offset, 0), order.count - 1)]
    }
}

/// One store's games in the sidebar — or the games of that store whose profile Cellar guessed.
public struct LibrarySection: Identifiable, Sendable {
    public let store: GameStore
    /// Profiles Cellar wrote itself from the games' files.
    public let guessed: Bool
    public let games: [GameSummary]
    public var id: String { "\(store.rawValue)\(guessed ? "-guessed" : "")" }
}

/// Everything the library reads from disk in one refresh — the `LoadLibrary` use case of
/// docs/APP-ARCHITECTURE.md. `current()` is the real read; a test builds one by hand.
public struct LibrarySnapshot: Sendable {
    /// The games the player's stores confirmed, or that a store which can never answer shows anyway.
    public var games: [GameSummary]
    /// Every profile Cellar ships that the player's stores did not confirm — kept only so the
    /// sidebar can say *how many* are withheld and why. Never rendered as a list: a list of games you
    /// don't own, presented in your library, is a claim no caption undoes.
    public var withheld: [GameSummary]
    /// The one Steam sign-in, so the empty state can name the fix rather than shrug.
    public var steam: SteamAccount.State
    /// Whether any store is signed in (or, for Battle.net, added).
    public var hasConnectedStore: Bool
    public var gogSignedIn: Bool

    public init(games: [GameSummary], withheld: [GameSummary], steam: SteamAccount.State,
                hasConnectedStore: Bool, gogSignedIn: Bool) {
        self.games = games
        self.withheld = withheld
        self.steam = steam
        self.hasConnectedStore = hasConnectedStore
        self.gogSignedIn = gogSignedIn
    }

    public static let empty = LibrarySnapshot(games: [], withheld: [], steam: .signedOut,
                                              hasConnectedStore: false, gogSignedIn: false)

    /// Reads the library as it is on disk now. Never asks a store anything over the network:
    /// `LoadLibrary` runs on every refresh.
    public static func current() -> LibrarySnapshot {
        let all = LoadLibrary().summaries()
        return LibrarySnapshot(games: all.filter(\.isVisible), withheld: all.filter { !$0.isVisible },
                               steam: SteamAccount.state, hasConnectedStore: StoreLibrary.hasConnectedStore,
                               gogSignedIn: GOGAuth.isSignedIn)
    }

    /// Why the library is empty, named per store rather than assumed to be Steam's fault. Cellar
    /// speaks to three stores; only one of them signs in with a QR code.
    public var signInReason: String {
        let allStores = Set(withheld.map(\.store))
        // Battle.net first, because it is the one store whose sentence is not about ownership at
        // all: Blizzard publishes nothing to check, so what is missing is the player's own word.
        if allStores == [.battlenet] {
            return "Blizzard publishes nothing Cellar can check, so it asks you instead. Add Battle.net and its games appear."
        }
        // Only games whose store was never *asked* say anything about signing in. A game the store
        // answered "no" to is withheld for a reason a sign-in cannot change — counting it here is
        // how a signed-in player gets told they are not signed in.
        let unasked = withheld.filter { game in
            if case .unknown = game.ownership { return game.store.canAnswerOwnership }
            return false
        }
        let stores = Set(unasked.map(\.store))
        if stores.contains(.steam), !steam.isUsable { return steam.summary }
        if stores == [.gog], !gogSignedIn {
            return "Not signed in to GOG. One sign-in covers your whole GOG library."
        }
        if stores.isEmpty {
            return "Nothing your stores confirmed you own is supported yet."
        }
        return "Cellar lists a game once its store confirms you own it, and it hasn't been able to ask yet."
    }
}

extension GameStore {
    /// The stores in the library's fixed order.
    public static var inLibraryOrder: [GameStore] { allCases.sorted { $0.sortIndex < $1.sortIndex } }
}
