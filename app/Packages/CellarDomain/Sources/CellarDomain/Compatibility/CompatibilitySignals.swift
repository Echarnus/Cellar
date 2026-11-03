import Foundation

/// Everything `CompatibilityForecast` reads about a game: its profile's facts and the way Cellar
/// is set to run it. Plain values, so the estimate can be tested without a profile on disk.
public struct CompatibilitySignals: Sendable {
    public var facts: GameFacts
    public var store: GameStore
    public var runnerID: String
    public var backend: String
    public var fallbackBackend: String?
    public var launcher: PublisherLauncher?

    public init(facts: GameFacts, store: GameStore = .steam, runnerID: String = "wineforge",
                backend: String = "d3dmetal", fallbackBackend: String? = nil,
                launcher: PublisherLauncher? = nil) {
        self.facts = facts
        self.store = store
        self.runnerID = runnerID
        self.backend = backend
        self.fallbackBackend = fallbackBackend
        self.launcher = launcher
    }

    /// Lower-cased, so every rule matches the way a person wrote the profile.
    func lower(_ value: String?) -> String { (value ?? "").lowercased() }
}
