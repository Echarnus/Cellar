import Foundation

/// Who is being launched, and by which route — everything the wording of a stage depends on.
///
/// The route matters as much as the store: the same Steam game can run through the client or, when
/// its profile says no live session is needed, straight from its exe. Saying "handing Steam the
/// command" when no Steam is involved would be the sort of small lie the UX rules exist to prevent.
public struct LaunchContext: Sendable {
    public let game: String
    public let store: GameStore
    /// Whether the launch goes through the store's client rather than running the exe directly.
    public let throughClient: Bool
    /// Whether the launch first waits for the player to sign in to the store client in the bottle.
    public let signsInFirst: Bool

    public init(game: String, store: GameStore, throughClient: Bool, signsInFirst: Bool = false) {
        self.game = game
        self.store = store
        self.throughClient = throughClient
        self.signsInFirst = signsInFirst
    }
}
