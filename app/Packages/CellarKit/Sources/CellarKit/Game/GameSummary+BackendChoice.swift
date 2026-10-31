import CellarDomain
import Foundation

extension GameSummary {
    /// The backend to offer when a launch didn't bring the game up — see `BackendChoice.retry`.
    public var retryBackend: GraphicsBackend? {
        BackendChoice.retry(current: backend, primary: profileBackend ?? backend, fallback: fallbackBackend)
    }
}
