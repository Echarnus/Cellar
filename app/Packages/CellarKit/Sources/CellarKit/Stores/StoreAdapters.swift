import CellarDomain
import Foundation
import Synchronization

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
