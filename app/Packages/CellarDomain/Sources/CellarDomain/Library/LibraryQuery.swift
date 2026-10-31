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
