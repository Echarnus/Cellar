import CellarDomain
import Foundation
import Testing
@testable import CellarData

/// The engine's side of the domain's ports and of the values it extends (#133): what the app's
/// composition root wires in has to answer exactly what the engine itself would.
@Suite(.serialized)
struct DomainPortTests {

    private func summary(store: GameStore = .gog, backend: String = "dxvk",
                         profileBackend: String? = "d3dmetal", fallback: String? = "dxvk") -> GameSummary {
        var summary = GameSummary(slug: "port-fixture", name: "Port Fixture", store: store, appID: nil,
                                  iconPath: nil, runnerInstalled: true, clientInstalled: true, account: nil,
                                  gameInstalled: true, bottleExists: true, running: false, productCode: nil,
                                  ownership: .owned, artworkAppID: nil, artPortraitURL: nil, artHeroURL: nil,
                                  needsClientAtRuntime: false, facts: GameFacts(), runnerID: "wineforge",
                                  backend: backend, bottleName: "port-fixture")
        summary.profileBackend = profileBackend
        summary.fallbackBackend = fallback
        return summary
    }

    @Test("The disk repository's snapshot splits the same summaries LoadLibrary reads, by the library gate")
    func diskRepositoryMatchesLoadLibrary() {
        let snapshot = DiskLibraryRepository().snapshot()
        let all = LoadLibrary().summaries()
        #expect(snapshot.games.map(\.slug) == all.filter(\.isVisible).map(\.slug))
        #expect(snapshot.withheld.map(\.slug) == all.filter { !$0.isVisible }.map(\.slug))
        #expect(snapshot.steam == SteamAccount.state)
        #expect(snapshot.hasConnectedStore == StoreLibrary.hasConnectedStore)
        #expect(snapshot.gogSignedIn == GOGAuth.isSignedIn)
        // The account button and the empty library must never disagree about who is signed in.
        #expect(snapshot.connectedStores == GameStore.allCases.filter(StoreLibrary.isConnected))
        #expect(snapshot.hasConnectedStore == !snapshot.connectedStores.isEmpty)
    }

    @Test("A summary's verdict is the store library's, asked about its own store and ownership")
    func summaryVerdictIsTheLibraryGate() {
        for store in GameStore.allCases {
            let game = summary(store: store)
            let expected = StoreLibrary.verdict(store: store, ownership: .owned,
                                                isConnected: StoreLibrary.isConnected(store))
            #expect(game.verdict == expected)
            #expect(game.isVisible == expected.isVisible)
        }
    }

    @Test("A player who left the profile's backend is offered the backend retry, through BackendChoice")
    func summaryRetryBackend() {
        let moved = summary(backend: "dxvk", profileBackend: "d3dmetal", fallback: "dxvk")
        #expect(moved.retryBackend == BackendChoice.retry(current: "dxvk", primary: "d3dmetal", fallback: "dxvk"))
        let onProfile = summary(backend: "d3dmetal", profileBackend: nil, fallback: "dxvk")
        #expect(onProfile.retryBackend == BackendChoice.retry(current: "d3dmetal", primary: "d3dmetal", fallback: "dxvk"))
    }

    @Test("The installed store artwork is exactly where the engine finds each store's icon")
    func installedArtworkIsStoreIcon() {
        for store in GameStore.allCases {
            #expect(InstalledStoreArtwork().markFile(for: store) == StoreIcon.mark(store))
        }
    }

    @Test("The old nested names still name the domain values, so no caller had to change")
    func typealiasesNameTheDomainValues() {
        let state: GameUpdates.State = .unknown("not checked yet")
        #expect(state == UpdateState.unknown("not checked yet"))
        let record = Playtime.Record(totalSeconds: 60, sessions: 1)
        #expect(record == PlayRecord(totalSeconds: 60, sessions: 1))
        let verdict = StoreLibrary.Verdict(ownership: .owned, isVisible: true, note: nil, fix: nil)
        #expect(verdict == LibraryVerdict(ownership: .owned, isVisible: true, note: nil, fix: nil))
        #expect(SteamAccount.expectedLifetimeInDays == SteamSignInState.expectedLifetimeInDays)
    }
}
