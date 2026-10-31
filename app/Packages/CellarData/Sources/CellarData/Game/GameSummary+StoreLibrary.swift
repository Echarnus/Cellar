import CellarDomain
import Foundation

/// The library gate, which asks the engine whether the store is connected (`StoreLibrary`).
extension GameSummary {
    /// Whether this game belongs in the player's library at all.
    public var isVisible: Bool { verdict.isVisible }

    /// Why this game is or isn't in the library — the whole answer, so a caller that needs the
    /// sentence and the fix doesn't re-derive them from the parts.
    public var verdict: StoreLibrary.Verdict {
        StoreLibrary.verdict(store: store, ownership: ownership,
                             isConnected: StoreLibrary.isConnected(store))
    }
}
