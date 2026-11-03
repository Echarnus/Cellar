import CellarDomain
import Foundation

extension GamePlan {
    /// The same estimate the game page shows (`GameSummary.forecast`), for the CLI.
    public var forecast: CompatibilityForecast {
        CompatibilityForecast(CompatibilitySignals(
            facts: facts, store: store, runnerID: runnerID, backend: profileBackend,
            fallbackBackend: fallbackBackend, launcher: publisherLauncher))
    }
}
