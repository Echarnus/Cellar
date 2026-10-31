import Foundation

/// How the player proves who they are — the single fact that decides whether signing in is
/// something Cellar can do *for* them, once, or something they must do inside somebody else's
/// window, per bottle.
public enum StoreAuthStyle: String, Sendable {
    /// Inside the store client's own window, in the bottle (Steam, Battle.net). Cellar can open the
    /// window and nothing more; it never sees or holds the credential.
    case inClientWindow
    /// Cellar runs the sign-in itself and holds a token (GOG's OAuth, Steam's QR device flow for
    /// downloads). One sign-in, account-wide, no client involved.
    case cellarHeldToken
}
