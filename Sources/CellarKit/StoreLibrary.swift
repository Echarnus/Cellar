import Foundation

/// **Your games, not Cellar's catalogue.**
///
/// Cellar ships a profile per supported game, and it used to show all of them to everybody — so the
/// library was a list of what *somebody's* Mac could run, with Install buttons that could only ever
/// fail for a game you don't own. One rule replaces that: a game is listed when the store it comes
/// from says this account may have it.
///
/// The rule lives here, once, so `cellar library` and the app cannot drift apart.
public enum Ownership: Sendable, Equatable, Codable {
    /// The store confirmed it: this account can install and play it.
    case owned
    /// The store answered, and the answer was no.
    case notOwned
    /// Nobody asked yet, or the question could not be answered. **Never** rendered as "you don't
    /// own this" — an unanswered question is not a no.
    case unknown(String)

    public var isOwned: Bool { self == .owned }

    private enum CodingKeys: String, CodingKey { case state, reason }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(String.self, forKey: .state) {
        case "owned":    self = .owned
        case "notOwned": self = .notOwned
        default:         self = .unknown(try c.decodeIfPresent(String.self, forKey: .reason) ?? "not checked")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .owned:    try c.encode("owned", forKey: .state)
        case .notOwned: try c.encode("notOwned", forKey: .state)
        case .unknown(let why):
            try c.encode("unknown", forKey: .state)
            try c.encode(why, forKey: .reason)
        }
    }
}

/// Whether a store can answer the ownership question at all — the fact that decides what an
/// unanswered store does to its games.
public extension GameStore {
    /// Steam and GOG both publish, to a signed-in Cellar, exactly what the account owns. Blizzard
    /// publishes neither entitlements nor a sign-in state, and a standalone game has no store to
    /// ask. Those two can never be checked, so hiding their games would mean pretending they don't
    /// exist — they are shown, with the section saying plainly that Cellar cannot check.
    var canAnswerOwnership: Bool {
        switch self {
        case .steam, .gog:            return true
        case .battlenet, .standalone: return false
        }
    }
}

/// The library gate: connected? owned? — asked once, answered the same way everywhere.
public enum StoreLibrary {

    /// Why a game is or isn't in the library, in a form both front-ends can render.
    public struct Verdict: Sendable, Equatable {
        public let ownership: Ownership
        /// Whether the game belongs in the player's library at all.
        public let isVisible: Bool
        /// What to say about it, when it needs saying.
        public let note: String?
        /// The action that would resolve an unknown, when there is one.
        public let fix: String?
    }

    /// Decide one game's place in the library.
    public static func verdict(store: GameStore, ownership: Ownership) -> Verdict {
        switch ownership {
        case .owned:
            return Verdict(ownership: .owned, isVisible: true, note: nil, fix: nil)
        case .notOwned:
            return Verdict(ownership: .notOwned, isVisible: false,
                           note: "Not in your \(store.displayName) library.", fix: nil)
        case .unknown(let why):
            // A store that *can* answer but hasn't been asked hides its games, and the section
            // carries the fix — showing them with a caveat underneath reads fine and is a lie by
            // arrangement, because a list presented as yours is a claim no caption undoes.
            guard store.canAnswerOwnership else {
                return Verdict(ownership: ownership, isVisible: true,
                               note: "Cellar can't check whether you own this — \(store.displayName) doesn't publish it.",
                               fix: nil)
            }
            return Verdict(ownership: ownership, isVisible: false, note: why,
                           fix: store == .steam ? "Sign in to Steam" : "Sign in to \(store.displayName)")
        }
    }

    // MARK: - Steam

    /// What Cellar last learned from Steam, cached because `Game.summaries()` runs on every library
    /// refresh and must never make a network call — let alone start a process per game.
    struct SteamCache: Codable {
        var checkedAt: Date
        /// The account the answers belong to. A different account invalidates all of them: the
        /// alternative is showing one person's library to the next person at that Mac.
        var account: String
        var apps: [String: Ownership]
    }

    static var steamCacheFile: URL {
        Paths.shared.appendingPathComponent("libraries/steam.json")
    }

    /// How long an answer is trusted before Cellar re-asks. A library changes when somebody buys a
    /// game, which is rare enough that a day is generous and a refresh is one click away.
    public static let cacheLifetime: TimeInterval = 24 * 60 * 60

    static func loadSteamCache() -> SteamCache? {
        guard let data = try? Data(contentsOf: steamCacheFile),
              let cache = try? JSONDecoder.cellar.decode(SteamCache.self, from: data),
              cache.account == SteamAccount.state.accountName else { return nil }
        return cache
    }

    static func saveSteamCache(_ cache: SteamCache) {
        try? FileManager.default.createDirectory(
            at: steamCacheFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder.cellar.encode(cache).write(to: steamCacheFile, options: .atomic)
    }

    /// Steam's answer for one app, from cache. Never asks Steam itself — see `refreshSteam`.
    public static func steamOwnership(appID: Int) -> Ownership {
        guard SteamAccount.isSignedIn else {
            return .unknown("Sign in to Steam to see the games you own.")
        }
        guard let cache = loadSteamCache() else {
            return .unknown("Cellar hasn't checked your Steam library yet.")
        }
        return cache.apps["\(appID)"] ?? .unknown("Cellar hasn't checked this game yet.")
    }

    /// Whether the cached answers are old enough to be worth re-asking.
    public static var steamNeedsRefresh: Bool {
        guard SteamAccount.isSignedIn else { return false }
        guard let cache = loadSteamCache() else { return true }
        return Date().timeIntervalSince(cache.checkedAt) > cacheLifetime
    }

    /// Ask Steam, for every app id Cellar has a profile for, whether this account may download it.
    ///
    /// One question per game, because Steam offers no way to ask about several at once without a
    /// second credential — and this way the answer comes from the same session that would do the
    /// installing, so "owned" means "Cellar can install this", not "an id appeared in a list".
    @discardableResult
    public static func refreshSteam(progress: (String) -> Void = { _ in }) throws -> [String: Ownership] {
        guard let credentials = SteamAccount.credentials,
              let account = SteamAccount.state.accountName else {
            throw CellarError.invalidArgument(
                "Not signed in to Steam. Sign in once with: cellar steam login")
        }
        let appIDs = steamAppIDsInProfiles()
        guard !appIDs.isEmpty else { return [:] }

        var answers = loadSteamCache()?.apps ?? [:]
        for (index, appID) in appIDs.sorted().enumerated() {
            progress("Asking Steam about game \(index + 1) of \(appIDs.count)…")
            switch DepotTool.access(appID: appID, credentials: credentials) {
            case .available:      answers["\(appID)"] = .owned
            case .unavailable:    answers["\(appID)"] = .notOwned
            case .unknown(let why):
                // Don't overwrite a good answer with a failed check — a dropped connection should
                // not empty somebody's library.
                if answers["\(appID)"] == nil { answers["\(appID)"] = .unknown(why) }
            }
        }
        saveSteamCache(SteamCache(checkedAt: Date(), account: account, apps: answers))
        return answers
    }

    /// Every Steam app id the profile database knows about — including a `standalone` profile that
    /// carries a `steam_appid`, because that game is fetched from the player's Steam account too
    /// (Stardew Valley), so Steam is the store that gates it.
    public static func steamAppIDsInProfiles() -> Set<Int> {
        var ids: Set<Int> = []
        for ref in ProfileStore.all() {
            let fields = ProfileStore.fields(ref)
            guard let appID = fields["steam_appid"].flatMap({ Int($0) }) else { continue }
            let store = GameStore(profileValue: fields["store"]) ?? .default
            guard store == .steam || store == .standalone else { continue }
            ids.insert(appID)
        }
        return ids
    }

    /// Forget every cached answer — on sign-out, so the next person at this Mac is not shown
    /// somebody else's library.
    public static func forgetSteam() {
        try? FileManager.default.removeItem(at: steamCacheFile)
    }

    // MARK: - GOG

    /// GOG hands over the whole owned library in one authenticated call, so it is cached wholesale
    /// rather than probed per game.
    struct GOGCache: Codable {
        var checkedAt: Date
        var productIDs: [Int]
    }

    static var gogCacheFile: URL { Paths.shared.appendingPathComponent("libraries/gog.json") }

    public static func gogOwnership(productID: Int?) -> Ownership {
        guard GOGAuth.isSignedIn else { return .unknown("Sign in to GOG to see the games you own.") }
        guard let productID else { return .unknown("This profile has no gog_product_id.") }
        guard let data = try? Data(contentsOf: gogCacheFile),
              let cache = try? JSONDecoder.cellar.decode(GOGCache.self, from: data) else {
            return .unknown("Cellar hasn't read your GOG library yet.")
        }
        return cache.productIDs.contains(productID) ? .owned : .notOwned
    }

    @discardableResult
    public static func refreshGOG() throws -> [Int] {
        let ids = try GOGLibrary.ownedProductIDs()
        try? FileManager.default.createDirectory(
            at: gogCacheFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder.cellar.encode(GOGCache(checkedAt: Date(), productIDs: ids))
            .write(to: gogCacheFile, options: .atomic)
        return ids
    }

    public static func forgetGOG() {
        try? FileManager.default.removeItem(at: gogCacheFile)
    }

    // MARK: - One answer for any game

    /// **Which store actually answers for this game** — not always the one the profile names.
    ///
    /// A `standalone` profile carrying a `steam_appid` (Stardew Valley) is DRM-free and needs no
    /// client, but its files still come out of the player's Steam account, so Steam is who says
    /// whether they own it. Gating it as "no store, nobody to ask" would put a game in the library
    /// that Cellar cannot actually download.
    public static func gatingStore(for plan: GamePlan) -> GameStore {
        if plan.store == .standalone, plan.appID != nil { return .steam }
        return plan.store
    }

    /// The ownership of one planned game, from cache only — safe to call for every profile on every
    /// library refresh.
    public static func ownership(of plan: GamePlan) -> Ownership {
        switch plan.store {
        case .steam:
            guard let appID = plan.appID else { return .unknown("This profile has no steam_appid.") }
            return steamOwnership(appID: appID)
        case .standalone:
            // A standalone profile that names a Steam app id is still fetched from Steam.
            guard let appID = plan.appID else { return .unknown("No store to ask.") }
            return steamOwnership(appID: appID)
        case .gog:
            return gogOwnership(productID: plan.gogProductID)
        case .battlenet:
            return .unknown("Blizzard doesn't publish what you own.")
        }
    }

    /// Refresh everything Cellar can ask about, for the stores that are signed in. Never throws for
    /// a store that isn't connected — that is not an error, it is the normal state before sign-in.
    public static func refreshAll(progress: (String) -> Void = { _ in }) {
        if SteamAccount.isSignedIn {
            progress("Checking your Steam library…")
            _ = try? refreshSteam(progress: progress)
        }
        if GOGAuth.isSignedIn {
            progress("Checking your GOG library…")
            _ = try? refreshGOG()
        }
    }
}
