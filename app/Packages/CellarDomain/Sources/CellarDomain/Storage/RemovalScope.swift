import Foundation

/// How much of a game's footprint to remove.
public enum RemovalScope: String, Sendable, CaseIterable {
    /// The game's own files, and the things Cellar made *for that game* — its launcher app, its
    /// extracted icon, its entry in the native Steam library. The bottle, the runner, the store
    /// client and the sign-in all survive, so re-installing is a download and nothing else.
    case game
    /// The game *and* the bottle it lived in: the Wine prefix with its registry, the store client
    /// installed into it, and the launchers Cellar generated for that bottle. The runner is shared
    /// by every bottle and the account is shared by every game, so neither is touched.
    case bottle
}
