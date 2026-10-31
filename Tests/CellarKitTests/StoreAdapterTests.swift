import Testing
@testable import CellarKit

/// Every store has exactly one adapter, and it is that store's — the one `switch` left.
@Suite(.serialized)
struct StoreAdapterTests {

    @Test("Each store's adapter is its own", arguments: GameStore.allCases)
    func adapterMatchesStore(_ store: GameStore) {
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
}
