import Foundation

/// **Which games the player may see, and why.**
///
/// Cellar's library used to be a catalogue: every profile shipped with the app, whether or not the
/// player had an account at that store or owned the game. That is the wrong shape — a launcher is
/// *your* games, not a list of what somebody else's Mac could run. So the library is now gated on
/// two facts, in this order:
///
/// 1. **Is the store connected?** No connection, no section. Signing in is the way in.
/// 2. **Does the player own it?** Asked of the store itself, not guessed.
///
/// The honesty rule from `skills/ux.md` decides what happens when a store won't answer the second
/// question, and the three stores are genuinely different here:
///
/// - **GOG** answers exactly — one call returns the whole owned library. Nothing is inferred.
/// - **Steam** answers exactly *once Cellar can ask*: with the player's own Web API key, or from a
///   public profile. Until then Cellar can only prove the games already installed in the shared
///   Steam library, so it shows those and says plainly that the rest are unchecked — it does not
///   pad the list with games it cannot justify.
/// - **Battle.net** cannot answer at all. Blizzard publishes neither who is signed in nor what they
///   own, so ownership there is `.unverifiable` forever, and the section says so rather than
///   implying Cellar checked.
///
/// Everything here is **local and cheap** except `refresh(_:)`. `Game.summaries()` runs on every
/// library refresh and must never make a network call, so ownership is read from a cache on disk
/// and only re-fetched when the player signs in, presses Refresh, or the cache goes stale.
public enum StoreLibrary {

    /// How long a cached library is trusted before Cellar quietly re-asks. A day: buying a game is
    /// rare, and a launcher that hammers a store's API on every window open is a bad citizen.
    public static let freshness: TimeInterval = 24 * 60 * 60

    // MARK: - Reading (local only)

    /// What Cellar knows about one store right now, from disk and the keychain alone.
    public static func status(_ store: GameStore) -> StoreStatus {
        switch store {
        case .steam:
            let account = SteamBottle.sharedLoggedInAccount
            // Two credentials, either of which means "this is my Steam": the Windows client's own
            // sign-in, and the QR device session used for client-free downloads. A player on a
            // fresh Mac has the second long before the first, and gating the library on the client
            // would mean no Steam game is visible until one has already been set up — a library you
            // cannot enter because you have not entered it.
            let connected = account != nil || DepotTool.hasStoredSession
            return StoreStatus(store: .steam,
                               isConnected: connected,
                               accountName: account,
                               library: connected ? cached(.steam) : nil)
        case .gog:
            return StoreStatus(store: .gog,
                               isConnected: GOGAuth.isSignedIn,
                               accountName: GOGAuth.cachedUsername,
                               library: GOGAuth.isSignedIn ? cached(.gog) : nil)
        case .battlenet:
            // Nothing readable exists, so the connection is the player's word — see `BattleNetAccess`.
            return StoreStatus(store: .battlenet,
                               isConnected: BattleNetAccess.isConnected,
                               accountName: nil,
                               library: nil)
        case .standalone:
            // A `standalone` profile has no storefront of its own. It is still gated, because the
            // *files* come from somewhere — see `GameSummary.gatingStore`.
            return StoreStatus(store: .standalone, isConnected: true, accountName: nil, library: nil)
        }
    }

    /// Every store's state in one snapshot, for a view that must decide what to draw in one pass.
    public static func access() -> LibraryAccess {
        var statuses: [GameStore: StoreStatus] = [:]
        for store in GameStore.allCases { statuses[store] = status(store) }
        return LibraryAccess(statuses: statuses)
    }

    // MARK: - Refreshing (network)

    /// Ask the store what the player owns, and cache the answer.
    ///
    /// Throws only when the store was reachable and still said no — a store that simply has no way
    /// to answer (Battle.net) returns nil, because that is not a failure the player can fix.
    @discardableResult
    public static func refresh(_ store: GameStore, progress: (String) -> Void = { _ in }) throws -> OwnedLibrary? {
        switch store {
        case .steam:
            let library = try SteamOwnership.read(progress: progress)
            write(library, for: .steam)
            return library
        case .gog:
            progress("Asking GOG what you own…")
            let owned = try GOGLibrary.ownedProductIDs()
            let library = OwnedLibrary(keys: Set(owned.map(String.init)),
                                       totalCount: owned.count,
                                       refreshedAt: Date(),
                                       source: "your GOG library",
                                       isComplete: true)
            write(library, for: .gog)
            return library
        case .battlenet, .standalone:
            return nil
        }
    }

    /// Every connected store whose cached library is missing or stale — what a background refresh
    /// should ask about, so the app never blocks a window on a network call it could have made earlier.
    public static func storesNeedingRefresh() -> [GameStore] {
        GameStore.allCases.filter { store in
            let status = status(store)
            guard status.isConnected, store.canReportOwnership else { return false }
            guard let library = status.library else { return true }
            return Date().timeIntervalSince(library.refreshedAt) > freshness
        }
    }

    // MARK: - Cache

    /// Cached libraries live beside the shared Steam install, under `shared/`, because an owned
    /// library belongs to the *account*, not to any one bottle — the same reason the Steam client
    /// moved there. Nothing secret is in them (ids and a count), so a plain file is right; the
    /// credentials that produce them stay in the keychain.
    static func cacheFile(_ store: GameStore) -> URL {
        Paths.storeLibraries.appendingPathComponent("\(store.rawValue).json")
    }

    public static func cached(_ store: GameStore) -> OwnedLibrary? {
        guard let data = try? Data(contentsOf: cacheFile(store)) else { return nil }
        return try? JSONDecoder().decode(OwnedLibrary.self, from: data)
    }

    static func write(_ library: OwnedLibrary, for store: GameStore) {
        try? FileManager.default.createDirectory(at: Paths.storeLibraries, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(library) else { return }
        try? data.write(to: cacheFile(store), options: .atomic)
    }

    /// Forget a store's library — part of signing out, so the next player on this Mac never sees
    /// the last one's games.
    public static func clearCache(_ store: GameStore) {
        try? FileManager.default.removeItem(at: cacheFile(store))
    }
}

// MARK: - The answer

/// What a store said the player owns, and how completely it said it.
public struct OwnedLibrary: Codable, Sendable {
    /// Store-native ids of everything owned: Steam AppIDs, GOG product ids, as strings. The *whole*
    /// library, not just the games Cellar has a profile for, so a profile added tomorrow is matched
    /// without another round trip.
    public var keys: Set<String>
    /// How big the player's library is at that store — "3 of 312" is more use than "3".
    public var totalCount: Int
    public var refreshedAt: Date
    /// Where the answer came from, in the player's words. Shown verbatim, because an exact answer
    /// and a partial one must not look alike.
    public var source: String
    /// False when `keys` is only the part Cellar could prove on its own. A game missing from an
    /// incomplete library is *unchecked*, never *unowned*.
    public var isComplete: Bool

    public init(keys: Set<String>, totalCount: Int, refreshedAt: Date, source: String, isComplete: Bool) {
        self.keys = keys
        self.totalCount = totalCount
        self.refreshedAt = refreshedAt
        self.source = source
        self.isComplete = isComplete
    }

    public func owns(_ key: String) -> Bool { keys.contains(key) }
}

/// Whether the player owns a game — with a third answer, because "we don't know" is the truth for
/// a whole store and pretending otherwise is the one thing this app must not do.
public enum Ownership: Sendable, Equatable {
    /// The store confirmed it.
    case owned
    /// The store gave a complete library and this game is not in it.
    case notOwned
    /// Nobody has said. Either the store publishes nothing (Battle.net), or Cellar has not been
    /// given what it needs to ask (Steam, before a key or a public profile).
    case unverifiable
}

/// One store's sign-in and library state, read once per refresh and never from a view body.
public struct StoreStatus: Sendable {
    public let store: GameStore
    /// Whether Cellar holds a credential for this store — or, for Battle.net, whether the player
    /// has said it is theirs.
    public let isConnected: Bool
    /// The account name, when the store lets Cellar read one. nil means "not published", not "none".
    public let accountName: String?
    /// The cached owned library, if this store has ever answered.
    public let library: OwnedLibrary?

    public init(store: GameStore, isConnected: Bool, accountName: String?, library: OwnedLibrary?) {
        self.store = store
        self.isConnected = isConnected
        self.accountName = accountName
        self.library = library
    }

    /// Whether this game is owned, as far as the store has been willing to say.
    public func ownership(of key: String?) -> Ownership {
        guard store.canReportOwnership else { return .unverifiable }
        guard let key, let library else { return .unverifiable }
        if library.owns(key) { return .owned }
        return library.isComplete ? .notOwned : .unverifiable
    }

    /// How many of the player's games Cellar has a profile for — the honest denominator for
    /// "3 of 312 supported".
    public func supportedCount(among games: [GameSummary]) -> Int {
        games.filter { ownership(of: $0.ownershipKey) == .owned }.count
    }

    /// One sentence for the state this store's library is in, or nil when it is simply fine.
    /// Shown in the library and in `cellar accounts`, so both say the same thing.
    public var libraryNote: String? {
        guard isConnected else { return nil }
        switch store {
        case .battlenet:
            return "Blizzard doesn't publish your library, so Cellar can't check which of these you own."
        case .standalone:
            return nil
        case .steam, .gog:
            guard let library else {
                return "Cellar hasn't read your \(store.displayName) library yet."
            }
            return library.isComplete ? nil
                : "Cellar can only see the \(store.displayName) games already installed. Connect your library to see the rest."
        }
    }
}

/// Every store's state at once, plus the two questions the library asks of each game.
public struct LibraryAccess: Sendable {
    public let statuses: [GameStore: StoreStatus]

    public init(statuses: [GameStore: StoreStatus]) { self.statuses = statuses }

    /// A store Cellar has never looked at reads as "not connected" — the safe direction, since the
    /// consequence is offering a sign-in rather than showing somebody a game they may not own.
    public func status(_ store: GameStore) -> StoreStatus {
        statuses[store] ?? StoreStatus(store: store, isConnected: false, accountName: nil, library: nil)
    }

    /// Stores with a real account behind them. `standalone` is not one: it is the *absence* of a
    /// store, so it never appears as something to sign in to.
    public var connectedStores: [GameStore] {
        GameStore.allCases
            .filter { $0 != .standalone && status($0).isConnected }
            .sorted { $0.sortIndex < $1.sortIndex }
    }

    /// True when the player has connected nothing — the first-run state the app opens on.
    public var hasNoConnection: Bool { connectedStores.isEmpty }

    public func ownership(of game: GameSummary) -> Ownership {
        status(game.gatingStore).ownership(of: game.ownershipKey)
    }

    /// **The rule the library is built on.** A game is shown when the store that gates it is
    /// connected and the player is not known *not* to own it.
    ///
    /// The `.unverifiable` case splits on whether the store *could* ever tell us:
    /// Battle.net never can, so hiding Diablo IV would only mean the store does not exist in this
    /// app — it is shown, with the section saying Cellar cannot check. Steam can, so a game it has
    /// not confirmed stays hidden and the section says exactly how to let Cellar ask. Hiding what
    /// is knowable-but-unknown is what keeps "these are your games" true.
    public func isVisible(_ game: GameSummary) -> Bool {
        isVisible(store: game.gatingStore, key: game.ownershipKey)
    }

    /// The rule itself, over nothing but a store and an id — so it can be checked in `cellar
    /// selftest` without building a whole game, and so there is exactly one copy of it.
    public func isVisible(store: GameStore, key: String?) -> Bool {
        let gate = status(store)
        guard gate.isConnected else { return false }
        switch gate.ownership(of: key) {
        case .owned:         return true
        case .notOwned:      return false
        case .unverifiable:  return !store.canReportOwnership
        }
    }
}

// MARK: - Battle.net: the store that publishes nothing

/// Battle.net's connection, which is the player's word rather than something Cellar read.
///
/// Blizzard publishes no signed-in state and no entitlements (their OAuth scopes are game-profile
/// data — see `docs/ROADMAP.md`). Cellar therefore has exactly two honest options: never show a
/// Battle.net game, or ask. It asks, once, in Accounts — and never puts a ✓ beside it, because a
/// ✓ would claim a check that did not happen.
///
/// Kept as a marker file under `shared/` rather than in `UserDefaults`, so the CLI and the app —
/// two binaries with two defaults domains — agree about it.
public enum BattleNetAccess {
    static var marker: URL { Paths.storeLibraries.appendingPathComponent("battlenet-connected") }

    public static var isConnected: Bool {
        FileManager.default.fileExists(atPath: marker.path)
    }

    public static func connect() throws {
        try FileManager.default.createDirectory(at: Paths.storeLibraries, withIntermediateDirectories: true)
        try Data().write(to: marker)
    }

    public static func disconnect() throws {
        guard isConnected else { return }
        try FileManager.default.removeItem(at: marker)
    }
}

// MARK: - Steam: asking Steam what you own

/// The player's Steam Web API key — the one thing that makes "which Steam games do I own?" an exact
/// question rather than a guess.
///
/// Steam has no OAuth for entitlements (`docs/ROADMAP.md` records why), and a profile whose game
/// details are private answers an anonymous request with a redirect to the login page. A key issued
/// to the player's own account answers for their own library regardless. It is free, it is one page,
/// and it is optional — Cellar works without it, it just cannot list the games it has not seen.
///
/// The key is a credential, so it lives in the keychain beside the sign-in tokens, never in a file.
public enum SteamWebAPI {
    static let keychainAccount = "web-api-key"

    /// Where the player gets one. Named here so every surface points at the same page.
    public static let keyPage = "https://steamcommunity.com/dev/apikey"

    public static var key: String? {
        Keychain.get(account: keychainAccount, store: .steam)
    }

    public static var hasKey: Bool { key != nil }

    /// Store a key, after checking it is one. A silently-wrong key would show up much later as an
    /// empty library, which reads as "Cellar lost my games".
    public static func setKey(_ raw: String) throws {
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard key.count == 32, key.allSatisfy({ $0.isHexDigit }) else {
            throw CellarError.invalidArgument(
                "That doesn't look like a Steam Web API key — they are 32 letters and digits. Get yours at \(keyPage).")
        }
        try Keychain.set(key, account: keychainAccount, store: .steam)
    }

    public static func forgetKey() throws {
        try Keychain.remove(account: keychainAccount, store: .steam)
    }

    /// `IPlayerService/GetOwnedGames` for the signed-in player. Their own key reading their own
    /// library, which is the only use Cellar has for it.
    static func ownedAppIDs(steamID: String, key: String) throws -> [Int] {
        let url = "https://api.steampowered.com/IPlayerService/GetOwnedGames/v1/"
            + "?key=\(key)&steamid=\(steamID)&include_appinfo=0&include_played_free_games=1&format=json"
        let json = try Downloader.json(url)
        guard let response = json["response"] as? [String: Any] else {
            throw CellarError.ioFailure("Steam didn't answer with a library. Check your key at \(keyPage).")
        }
        guard let games = response["games"] as? [[String: Any]] else {
            // An empty `response` object is Steam's way of saying the key isn't allowed to read
            // this account — the most common cause is a key issued to a different Steam account.
            throw CellarError.ioFailure(
                "Steam returned no library for this account. Make sure the key came from the Steam account you're signed in to (\(keyPage)).")
        }
        return games.compactMap { $0["appid"] as? Int }
    }
}

/// Works out which Steam games the player owns, from the best source available.
enum SteamOwnership {
    /// The ladder, best first. Every rung is exact except the last, and the last says so.
    static func read(progress: (String) -> Void = { _ in }) throws -> OwnedLibrary {
        let installed = SteamBottle.installedAppIDs.map(String.init)

        if let steamID = SteamBottle.sharedSteamID64 {
            if let key = SteamWebAPI.key {
                progress("Asking Steam what you own…")
                let owned = try SteamWebAPI.ownedAppIDs(steamID: steamID, key: key)
                return OwnedLibrary(keys: Set(owned.map(String.init)).union(installed),
                                    totalCount: owned.count,
                                    refreshedAt: Date(),
                                    source: "your Steam library",
                                    isComplete: true)
            }
            // No key: a public profile still publishes the list, and costs the player nothing.
            if let owned = try? publicProfileAppIDs(steamID: steamID), !owned.isEmpty {
                progress("Read your Steam library from your public profile.")
                return OwnedLibrary(keys: Set(owned.map(String.init)).union(installed),
                                    totalCount: owned.count,
                                    refreshedAt: Date(),
                                    source: "your public Steam profile",
                                    isComplete: true)
            }
        }

        // Nothing would answer. What is left is what Cellar can prove by itself: the games actually
        // installed in the shared Steam library. Marked incomplete, so nothing downstream reads a
        // missing game as one the player doesn't own.
        return OwnedLibrary(keys: Set(installed),
                            totalCount: installed.count,
                            refreshedAt: Date(),
                            source: "the games installed in your Steam library",
                            isComplete: false)
    }

    /// Steam's own community endpoint, which needs no key — but only answers when the player's game
    /// details are public. A private profile is redirected to the login page, which parses as no
    /// games, which is why the caller treats an empty result as "didn't answer".
    static func publicProfileAppIDs(steamID: String) throws -> [Int] {
        let xml = try Downloader.string("https://steamcommunity.com/profiles/\(steamID)/games?tab=all&xml=1")
        return xml.components(separatedBy: "<appID>").dropFirst().compactMap { chunk in
            guard let end = chunk.range(of: "</appID>") else { return nil }
            return Int(chunk[chunk.startIndex..<end.lowerBound])
        }
    }
}

// MARK: - What a game is gated on

public extension GameSummary {
    /// **Which store's sign-in decides whether this game may be shown.**
    ///
    /// Usually the game's own store. The exception is a `standalone` profile that still names a
    /// Steam AppID — Stardew Valley is the reference case: it is DRM-free and runs with no client at
    /// all, but its *files* are fetched from the player's own Steam account with DepotDownloader.
    /// So Steam is what gates it, and it is listed under Steam's connection rather than floating
    /// free in a library that is supposed to be games you own.
    var gatingStore: GameStore {
        GameStore.gate(for: store, hasSteamAppID: appID != nil)
    }

    /// This game's id in its gating store's vocabulary — the key an owned library is checked against.
    var ownershipKey: String? {
        switch gatingStore {
        case .steam:      return appID.map(String.init)
        case .gog:        return gogProductID.map(String.init)
        case .battlenet:  return productCode          // no library to check it against, but its identity
        case .standalone: return nil
        }
    }
}

// MARK: - Per-store facts this file needs

public extension GameStore {
    /// Whether the store can ever tell Cellar what the player owns. False for Battle.net — not
    /// "not yet", but "there is no such API", which is why its games are shown unchecked rather
    /// than hidden forever.
    var canReportOwnership: Bool {
        switch self {
        case .steam, .gog:            return true
        case .battlenet, .standalone: return false
        }
    }

    /// Which store's connection gates a profile from `store`. Its own, except for a `standalone`
    /// profile carrying a Steam AppID — those files come out of the player's Steam account via
    /// DepotDownloader, so Steam is what decides whether the game is theirs to see.
    static func gate(for store: GameStore, hasSteamAppID: Bool) -> GameStore {
        store == .standalone && hasSteamAppID ? .steam : store
    }
}
