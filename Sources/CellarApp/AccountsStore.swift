import CellarDomain
import Foundation
import Observation
import CellarKit

/// Where the player is signed in, for every window that shows it — Settings and the welcome tour
/// used to read it into a `@State` each, with a copy of the same refresh in both.
@MainActor
@Observable
final class AccountsStore {
    /// Read once per refresh, never from a view body — see `StoreAccountState`.
    private(set) var state = StoreAccountState.unknown

    @ObservationIgnored private let activity: ActivityStore

    init(activity: ActivityStore) {
        self.activity = activity
    }

    /// Re-read every store's state, **off the main thread and after layout has finished**.
    ///
    /// This work is not cheap — it stats bottles, reads the keychain, and asks GOG for a username
    /// over the network. Doing it inline in `onAppear` meant blocking the main thread and then
    /// mutating state in the middle of `NSHostingView`'s first layout pass, which re-enters the
    /// view graph and aborts in AttributeGraph.
    ///
    /// The GOG name is the CLI's to learn, because the CLI is what holds the token: `cellar gog
    /// status` asks GOG and writes the name both binaries read. The app never reads the token itself.
    func refresh() {
        let activity = activity
        Task.detached {
            if GOGAuth.isSignedIn, GOGAuth.cachedUsername == nil {
                _ = await activity.runBeside(.gogStatus)
            }
            let snapshot = StoreAccountState.current()
            await MainActor.run { self.state = snapshot }
        }
    }
}
