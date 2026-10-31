import CellarDomain
import Foundation
import Synchronization

/// What a store *does*, one type per store — where `StoreDescriptor` is what a store *is*.
///
/// Per-store behaviour used to be a `switch plan.store` repeated in every function that needed it,
/// so adding a store meant finding all of them. An adapter answers those questions for its own
/// store. The adapters themselves live in `CellarInfrastructure`; this module holds only the port
/// and the registry the composition root fills (`StoreAdapters`). Capabilities move here one at a time
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

    /// The last step of `cellar setup`: the store's client in the bottle, if the game needs one.
    func setUpClient(_ plan: GamePlan, wine: WineRunner, step: (String) -> Void,
                     phase: (InstallProgress) -> Void) throws
    /// Install the game through its store. `progress` gets a download tool's raw output as well as
    /// `step`'s sentences.
    func installGame(_ plan: GamePlan, wine: WineRunner, step: (String) -> Void,
                     progress: (String) -> Void, phase: (InstallProgress) -> Void) throws
    /// Open the store's client in the bottle (sign in, browse, manage installs).
    func openClient(_ plan: GamePlan, wine: WineRunner, showHUD: Bool) throws
    /// Start the game through the store, once Play has ruled out running its exe directly: the
    /// client in the bottle for a store that has one, an honest "not installed" for one that doesn't.
    func launchThroughClient(_ plan: GamePlan, wine: WineRunner, showHUD: Bool, forceStore: Bool,
                             progress: (String) -> Void, stage: (LaunchStage) -> Void,
                             update: (InstallProgress) -> Void) throws -> LaunchRoute
}

/// Which adapter answers for each store. CellarKit defines the port; the concrete adapters are
/// infrastructure (Steam's bottle, Battle.net's client, GOG's API) and live in
/// `CellarInfrastructure`, which this module does not import. The composition root — the `cellar`
/// CLI's `main`, or a test's set-up — registers them once with `CellarInfrastructure.install()`.
public enum StoreAdapters {
    private static let registered = Mutex<[GameStore: any StoreAdapter]>([:])

    /// Make `adapter` the one that answers for its store. Registering again replaces it.
    public static func register(_ adapter: any StoreAdapter) {
        registered.withLock { $0[adapter.store] = adapter }
    }

    /// Whether every store has an adapter.
    public static var isComplete: Bool {
        registered.withLock { table in GameStore.allCases.allSatisfy { table[$0] != nil } }
    }

    /// The registered adapter for `store`. Reaching here with none is a wiring bug in the
    /// composition root, not something a player can cause, so it stops loudly.
    public static func adapter(for store: GameStore) -> any StoreAdapter {
        if let adapter = registered.withLock({ $0[store] }) { return adapter }
        preconditionFailure("No StoreAdapter registered for \(store.rawValue). The composition root must call CellarInfrastructure.install() first.")
    }
}

extension GameStore {
    /// The adapter for this store, as registered by the composition root.
    public var adapter: any StoreAdapter { StoreAdapters.adapter(for: self) }
}
