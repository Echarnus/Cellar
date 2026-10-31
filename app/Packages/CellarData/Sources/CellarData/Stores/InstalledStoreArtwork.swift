import CellarDomain
import Foundation

/// The store icons already installed on this Mac, found by `StoreIcon`. The app's composition root
/// hands it to `StoreIcons`, so CellarUI can show a store's real icon without depending on the engine.
public struct InstalledStoreArtwork: StoreArtworkSource {
    public init() {}

    public func markFile(for store: GameStore) -> URL? { StoreIcon.mark(store) }
}
