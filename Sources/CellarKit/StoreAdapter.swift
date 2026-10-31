import Foundation

/// What a store *does*, one type per store — where `StoreDescriptor` is what a store *is*.
///
/// Per-store behaviour used to be a `switch plan.store` repeated in every function that needed it,
/// so adding a store meant finding all of them. An adapter answers those questions for its own
/// store, and `GameStore.adapter` is the one switch left. Capabilities move here one at a time
/// (docs/APP-ARCHITECTURE.md → Target: the engine); `Game`'s static functions stay as the façade
/// every caller already uses.
///
/// Every game comes through a store, so there is no adapter for "no store".
public protocol StoreAdapter: Sendable {
    var store: GameStore { get }
    /// Whether the store's client is present in the bottle. A store with no client in the bottle is
    /// "installed" by definition and never asks the player to set one up.
    func isClientInstalled(_ plan: GamePlan) -> Bool
    /// Whether the store's client is running now.
    var isClientRunning: Bool { get }
    /// The signed-in account, or nil when the store doesn't say (see `GameSummary.account`).
    func signedInAccount(_ plan: GamePlan) -> String?
    /// Whether the game's files are on disk, by the store's own record — nil when the store keeps
    /// none, and the profile's exe is the only answer.
    func recordsGameInstalled(_ plan: GamePlan) -> Bool?
}

extension GameStore {
    /// The adapter for this store — the only `switch` on a store that behaviour should need.
    public var adapter: any StoreAdapter {
        switch self {
        case .steam:     return SteamAdapter()
        case .battlenet: return BattleNetAdapter()
        case .gog:       return GOGAdapter()
        }
    }
}

public struct SteamAdapter: StoreAdapter {
    public init() {}
    public var store: GameStore { .steam }
    public func isClientInstalled(_ plan: GamePlan) -> Bool { SteamBottle.isInstalled(in: plan.prefix) }
    public var isClientRunning: Bool { SteamBottle.isRunning }
    public func signedInAccount(_ plan: GamePlan) -> String? { SteamBottle.loggedInAccount(in: plan.prefix) }
    /// Steam's appmanifest is authoritative — and only counts when its folder holds files.
    public func recordsGameInstalled(_ plan: GamePlan) -> Bool? {
        plan.appID.map { SteamBottle.isGameInstalled(in: plan.prefix, appID: $0) }
    }
}

public struct BattleNetAdapter: StoreAdapter {
    public init() {}
    public var store: GameStore { .battlenet }
    public func isClientInstalled(_ plan: GamePlan) -> Bool { BattleNetBottle.isInstalled(in: plan.prefix) }
    public var isClientRunning: Bool { BattleNetBottle.isRunning }
    public func signedInAccount(_ plan: GamePlan) -> String? { BattleNetBottle.rememberedAccount(in: plan.prefix) }
    public func recordsGameInstalled(_ plan: GamePlan) -> Bool? { nil }
}

public struct GOGAdapter: StoreAdapter {
    public init() {}
    public var store: GameStore { .gog }
    /// GOG needs no client in the bottle at all, so there is never one to set up.
    public func isClientInstalled(_ plan: GamePlan) -> Bool { true }
    public var isClientRunning: Bool { false }
    /// Cellar holds the GOG token itself, so this is a fact, not a guess — but read it from the
    /// cache: `summaries()` runs on every library refresh and must not make a network call.
    public func signedInAccount(_ plan: GamePlan) -> String? {
        GOGAuth.isSignedIn ? (GOGAuth.cachedUsername ?? "your GOG account") : nil
    }
    public func recordsGameInstalled(_ plan: GamePlan) -> Bool? { nil }
}
