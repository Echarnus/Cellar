import CellarDomain
import Foundation

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
