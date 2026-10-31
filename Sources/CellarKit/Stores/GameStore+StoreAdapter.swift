import CellarDomain
import Foundation
import Synchronization

extension GameStore {
    /// The adapter for this store, as registered by the composition root.
    public var adapter: any StoreAdapter { StoreAdapters.adapter(for: self) }
}
