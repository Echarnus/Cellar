import CellarDomain
import AppKit
import CellarKit
import SwiftUI

/// The app's composition root: the state every window shares, made once and handed to each window
/// as it is built (docs/APP-ARCHITECTURE.md). Settings, Accounts and the welcome tour are separate
/// `NSWindow`s — a sheet under `NSHostingView` is a fatal AttributeGraph cycle — so they share no
/// view tree, and this is how they still see the same Cellar.
@MainActor
final class AppModel {
    /// The player's actions — one at a time, for the whole app.
    let activity = ActivityStore()
    /// The games, the selection and the sidebar's filters.
    let library = LibraryViewModel(repository: DiskLibraryRepository())
    /// Where the player is signed in.
    lazy var accounts = AccountsViewModel(activity: activity)
    /// The shared runtime downloading in the background — on its own runner, so it never holds Play.
    let preparation = RuntimePreparation()
    /// Sparkle, started the first time the menu bar asks for it.
    lazy var updater = AppUpdater()

    /// View › Add Installed Games Without a Profile: write draft profiles for them (`DraftProfile`),
    /// then show what turned up.
    func draftProfiles() {
        guard !activity.busy else { return }
        activity.run(.draftProfiles, title: String(localized: "Finding games without a profile"),
                     then: { [library] in library.refresh() })
    }
}
