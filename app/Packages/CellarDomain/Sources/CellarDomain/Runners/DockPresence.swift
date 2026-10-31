import Foundation

/// Whether a store client Cellar is about to start should appear in the Dock.
///
/// The two cases are genuinely different, and the difference is the player's intent. Starting a
/// game runs the client as scaffolding — it is `.hidden`, and the Dock shows what the player thinks
/// is running: Cellar, then the game. Choosing "Open Steam" makes the client the thing on screen —
/// it is `.visible`, because a window the player has to come back to (sign in, install, a store
/// page) needs a Dock icon and a ⌘-Tab entry to come back *to*.
public enum DockPresence: Sendable {
    case hidden
    case visible
}
