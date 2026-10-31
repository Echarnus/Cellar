import CellarDomain
import AppKit
import CellarKit
import SwiftUI

/// What is left of the app's notifications: windows asking `AppDelegate` to open other windows,
/// and ⌘F reaching a view's focus. State changes are not here — they are calls on the stores
/// `AppModel` owns (docs/APP-ARCHITECTURE.md).
extension Notification.Name {
    /// Posted by the "Settings…" menu item; ContentView opens its settings sheet on receipt.
    static let cellarOpenSettings = Notification.Name("cellar.openSettings")
    /// Posted by the "Accounts…" menu item, the sidebar button, and any "Sign in" button for a store
    /// whose token Cellar holds — because that sign-in is account-level, not per-game.
    static let cellarOpenAccounts = Notification.Name("cellar.openAccounts")
    /// Posted by Settings' "Review folder access…" button — the same window first run shows, in its
    /// status-board form.
    static let cellarOpenFolderAccess = Notification.Name("cellar.openFolderAccess")
    /// Posted by the "Welcome to Cellar…" menu item and by Settings, to replay the first-run tour.
    /// Named for the *tour* specifically, because the folder-access screen above is the other
    /// first-run window and the two coexist rather than fight for the name.
    static let cellarOpenWelcomeTour = Notification.Name("cellar.openWelcomeTour")
    /// Posted by Edit › Find… (⌘F), so the keyboard reaches the library search like any Mac app's.
    static let cellarFocusSearch = Notification.Name("cellar.focusSearch")
}
