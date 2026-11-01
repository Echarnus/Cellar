import CellarDomain
import Foundation
import Testing
@testable import CellarData

/// The first release is Steam only (#221). Battle.net and GOG stay built but hidden, behind one flag
/// — these pin that the flag says Steam, and that everything a player reads follows it.
@Suite("Store availability")
struct StoreAvailabilityTests {

    @Test("The first release offers Steam and nothing else")
    func steamOnly() {
        #expect(StoreAvailability.offered == [.steam])
        #expect(GameStore.offered == [.steam])
        #expect(GameStore.steam.isOffered)
        #expect(!GameStore.battlenet.isOffered)
        #expect(!GameStore.gog.isOffered)
    }

    @Test("The stores read as a phrase in library order, however many are offered")
    func phrase() {
        #expect(StoreAvailability.phrase([.steam]) == "Steam")
        #expect(StoreAvailability.phrase([.gog, .steam]) == "Steam or GOG")
        #expect(StoreAvailability.phrase([.gog, .battlenet, .steam]) == "Steam, Battle.net or GOG")
        #expect(StoreAvailability.phrase([]) == "")
        #expect(StoreAvailability.phrase() == "Steam")
    }

    @Test("Signed out, the account button names only Steam")
    func accountButtonSignedOut() {
        let summary = AccountSummary(connected: [], steam: .signedOut)
        #expect(summary.detail == "Steam")
        #expect(summary.tone == .signedOut)
    }

    @Test("A Battle.net or GOG account connected before the switch never shows on the account button")
    func accountButtonHidesStoresNotOffered() {
        let steam = SteamSignInState.signedIn(account: "kenneth", days: 3, aging: false)
        let summary = AccountSummary(connected: [.steam, .battlenet, .gog], steam: steam)
        #expect(summary.stores == [.steam])
        #expect(summary.detail == "Steam")

        // Only a hidden store connected is the same as nothing connected: the button asks for Steam.
        let hiddenOnly = AccountSummary(connected: [.battlenet, .gog], steam: .signedOut)
        #expect(hiddenOnly.tone == .signedOut)
        #expect(hiddenOnly.detail == "Steam")
    }

    @Test("The library's connected stores and 'any store connected' count offered stores only")
    func snapshotCountsOfferedStores() {
        let snapshot = DiskLibraryRepository().snapshot()
        #expect(snapshot.connectedStores.allSatisfy(\.isOffered))
        #expect(snapshot.games.allSatisfy { $0.store.isOffered })
        #expect(snapshot.withheld.allSatisfy { $0.store.isOffered })
        #expect(StoreLibrary.hasConnectedStore == GameStore.offered.contains(where: StoreLibrary.isConnected))
    }
}
