import Foundation

/// Why a game is or isn't in the library, in a form both front-ends can render.
public struct LibraryVerdict: Sendable, Equatable {
    public let ownership: Ownership
    /// Whether the game belongs in the player's library at all.
    public let isVisible: Bool
    /// What to say about it, when it needs saying.
    public let note: String?
    /// The action that would resolve an unknown, when there is one.
    public let fix: String?

    public init(ownership: Ownership, isVisible: Bool, note: String?, fix: String?) {
        self.ownership = ownership
        self.isVisible = isVisible
        self.note = note
        self.fix = fix
    }
}
