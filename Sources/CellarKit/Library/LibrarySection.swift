import CellarDomain
import Foundation

/// One store's games in the sidebar — or the games of that store whose profile Cellar guessed.
public struct LibrarySection: Identifiable, Sendable {
    public let store: GameStore
    /// Profiles Cellar wrote itself from the games' files.
    public let guessed: Bool
    public let games: [GameSummary]
    public var id: String { "\(store.rawValue)\(guessed ? "-guessed" : "")" }
}
