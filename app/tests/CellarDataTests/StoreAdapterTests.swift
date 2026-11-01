import CellarDomain
import Testing
@testable import CellarData
import CellarInfrastructure

/// Every store has exactly one adapter, and it is that store's. The adapters live in
/// `CellarInfrastructure`; CellarData sees them only through the registry.
@Suite(.serialized)
struct StoreAdapterTests {

    @Test("Wiring the infrastructure in gives every store an adapter, and each one is its own",
          arguments: GameStore.allCases)
    func adapterMatchesStore(_ store: GameStore) {
        CellarInfrastructure.install()
        #expect(StoreAdapters.isComplete)
        #expect(store.adapter.store == store)
    }

    @Test("A store with no client in the bottle never asks for one, and never claims one is running")
    func clientlessStore() throws {
        let plan = try TestHome.plan("""
        [game]
        name  = "Adapter GOG Game"
        store = "gog"
        """, slug: "adapter-gog")
        let gog = plan.store.adapter
        #expect(gog.isClientInstalled(plan))
        #expect(!gog.isClientRunning)
        #expect(gog.recordsGameInstalled(plan) == nil, "GOG keeps no record: the exe is the answer")
    }

    @Test("Only Steam keeps its own record of what is installed")
    func installRecords() throws {
        let steam = try TestHome.plan("""
        [game]
        name  = "Adapter Steam Game"
        store = "steam"
        [install]
        steam_appid = "4242"
        """, slug: "adapter-steam")
        let battlenet = try TestHome.plan("""
        [game]
        name  = "Adapter Battle.net Game"
        store = "battlenet"
        """, slug: "adapter-bnet")
        #expect(steam.store.adapter.recordsGameInstalled(steam) == false,
                "an appmanifest that isn't there is a no, not a don't-know")
        #expect(battlenet.store.adapter.recordsGameInstalled(battlenet) == nil)
    }

    @Test("Steam: Cellar starts a copy the client doesn't have, and the client's own copy when that gets Game Mode")
    func steamStartsGameItself() {
        // Cellar's own download: rungameid would find nothing, whatever else is true.
        #expect(SteamAdapter.startsGameItself(clientCopy: false, forceStore: false, gameAppAvailable: false))
        #expect(SteamAdapter.startsGameItself(clientCopy: false, forceStore: true, gameAppAvailable: true))
        // The client's copy: started by Cellar only when its game app can be used.
        #expect(SteamAdapter.startsGameItself(clientCopy: true, forceStore: false, gameAppAvailable: true))
        #expect(!SteamAdapter.startsGameItself(clientCopy: true, forceStore: false, gameAppAvailable: false))
        // Asking for the store route by name gets it.
        #expect(!SteamAdapter.startsGameItself(clientCopy: true, forceStore: true, gameAppAvailable: true))
    }
}
