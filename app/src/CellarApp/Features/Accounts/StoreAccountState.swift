import CellarDomain
import SwiftUI
import CellarKit
import CellarUI

/// A snapshot of every store's sign-in state, read once per refresh — never from a view body.
///
/// Reading disk in a view body would run `Game.summaries()` (which resolves game icons, spawning
/// tools) during view creation, on the main thread, in the middle of a window's first layout —
/// which is how this app has crashed in AttributeGraph before (skills/swift.md).
// Built off the main actor (`AccountsViewModel.refresh`) and handed back to it, so it is plain Sendable data.
nonisolated struct StoreAccountState: Sendable {
    /// The one Steam sign-in, as CellarKit computed it. The view never derives this itself, so the
    /// app and `cellar accounts` cannot describe the same session differently.
    var steam: SteamAccount.State = .signedOut
    /// The account signed in to the *in-bottle Windows client*, when there is one. A fact about the
    /// machine, not an account row.
    var steamClientAccount: String?
    var gogSignedIn = false
    var gogAccount: String?
    /// Whether the player has told Cellar they have a Battle.net account. Not a sign-in: it is the
    /// only thing Cellar can know about Blizzard, and it decides whether its games are listed.
    var battleNetAdded = false
    /// False until the first read, so the UI never states something it hasn't checked yet.
    var isLoaded = false

    /// What Cellar knows before it has looked: nothing.
    static let unknown = StoreAccountState()

    static func current() -> StoreAccountState {
        // The app reads this itself instead of asking the CLI, so the two can disagree — and when
        // they do, this line beside the CLI's is the only place it shows.
        CellarLog.debug(.account, SteamAccount.diagnosis)
        return StoreAccountState(
            steam: SteamAccount.state,
            steamClientAccount: SteamBottle.sharedLoggedInAccount,
            gogSignedIn: GOGAuth.isSignedIn,
            gogAccount: GOGAuth.cachedUsername,
            battleNetAdded: StoreLibrary.BattleNetAccount.isAdded,
            isLoaded: true)
    }
}
