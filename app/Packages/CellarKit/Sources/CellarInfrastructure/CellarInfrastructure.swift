import CellarDomain
import CellarKit

/// The one call a composition root makes to wire the engine's ports to real infrastructure.
public enum CellarInfrastructure {
    /// Register every store's adapter. Idempotent: calling it again re-registers the same adapters.
    public static func install() {
        StoreAdapters.register(SteamAdapter())
        StoreAdapters.register(BattleNetAdapter())
        StoreAdapters.register(GOGAdapter())
    }
}
