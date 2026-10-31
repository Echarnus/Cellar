import CellarDomain
import SwiftUI
import CellarData
import CellarUI

// MARK: - Pieces

enum AccountState {
    case signedIn(String)
    /// Signed in, but the store doesn't hand back a name worth showing.
    case signedInUnnamed
    case signedOut
    /// The store publishes nothing Cellar can read. Never a ✗ — see skills/ux.md.
    case unknowable
    /// The player said this store is theirs, and Cellar has no way to confirm it. Deliberately not
    /// drawn as a ✓: the mark and the word both say who is doing the claiming.
    case addedByYou
    /// Nothing published *and* nothing claimed — so this store's games are not listed yet.
    case notAdded
}
