import CellarDomain
import Foundation

/// The library as it is on this Mac: every profile through `LoadLibrary`, filtered by what the
/// player's stores confirmed, plus the sign-in state the empty library names.
public struct DiskLibraryRepository: LibraryRepository {
    public init() {}

    /// Reads the library as it is on disk now. Never asks a store anything over the network:
    /// `LoadLibrary` runs on every refresh.
    public func snapshot() -> LibrarySnapshot {
        let all = LoadLibrary().summaries()
        return LibrarySnapshot(games: all.filter(\.isVisible), withheld: all.filter { !$0.isVisible },
                               steam: SteamAccount.state, hasConnectedStore: StoreLibrary.hasConnectedStore,
                               gogSignedIn: GOGAuth.isSignedIn,
                               connectedStores: GameStore.allCases.filter(StoreLibrary.isConnected))
    }
}
