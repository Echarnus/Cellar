import Foundation

/// Whether a store can answer the ownership question at all — the fact that decides what an
/// unanswered store does to its games.
public extension GameStore {
    /// What a player does to make this store's games appear, in the words the button uses. Steam
    /// and GOG are signed in to; Battle.net is only ever *claimed*, because there is nothing there
    /// to sign in to from Cellar's side.
    var libraryFix: String {
        switch self {
        case .steam, .gog: return String(localized: "Sign in to \(displayName)")
        case .battlenet:   return String(localized: "Add Battle.net in Accounts")
        }
    }

    /// Steam and GOG both publish, to a signed-in Cellar, exactly what the account owns. Blizzard
    /// publishes neither entitlements nor a sign-in state, so it can never be checked — its games
    /// are gated on the player's own word instead (`BattleNetAccount`).
    var canAnswerOwnership: Bool {
        switch self {
        case .steam, .gog: return true
        case .battlenet:   return false
        }
    }
}
