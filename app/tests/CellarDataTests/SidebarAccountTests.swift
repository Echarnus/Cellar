import CellarDomain
import Foundation
import Testing

/// The sidebar's foot: the account button that replaced the header's unlabelled person icon, and
/// the rule that replaced its Refresh button.
@Suite("Sidebar account and automatic refresh")
struct SidebarAccountTests {

    // MARK: - The account button

    /// Every store, as if all three were offered — these tests are about the button's shape, not
    /// about which stores a release ships with (that is `StoreAvailabilityTests`).
    private let all = GameStore.inLibraryOrder

    @Test("With nothing connected the button is the invitation to sign in, naming the stores")
    func signedOut() {
        let summary = AccountSummary(connected: [], steam: .signedOut, offered: all)
        #expect(summary.tone == .signedOut)
        #expect(summary.title == "Sign in")
        #expect(summary.detail == "Steam, Battle.net or GOG")
        #expect(summary.stores.isEmpty)
    }

    @Test("Signed in to Steam, the button names the Steam account and every connected store in library order")
    func steamAccountNamed() {
        let steam = SteamSignInState.signedIn(account: "kenneth", days: 3, aging: false)
        let summary = AccountSummary(connected: [.gog, .steam], steam: steam, offered: all)
        #expect(summary.tone == .connected)
        #expect(summary.title == "kenneth")
        #expect(summary.stores == [.steam, .gog])
        #expect(summary.detail == "Steam · GOG")
    }

    @Test("Without a Steam name the title says whose accounts these are, never a bare store name")
    func noSteamName() {
        let summary = AccountSummary(connected: [.battlenet], steam: .signedOut, offered: all)
        #expect(summary.tone == .connected)
        #expect(summary.title == "Your accounts")
        #expect(summary.detail == "Battle.net")
    }

    @Test("An expired Steam session is said out loud, as that account, even beside a working store")
    func expiredSteam() {
        let summary = AccountSummary(connected: [.gog], steam: .expired(account: "kenneth", reason: "revoked"), offered: all)
        #expect(summary.tone == .needsAttention)
        #expect(summary.title == "kenneth")
        #expect(summary.detail == "Steam sign-in expired")
    }

    @Test("The snapshot's account summary is built from the snapshot's own stores")
    func snapshotAccount() {
        let snapshot = LibrarySnapshot(games: [], withheld: [], steam: .signedOut,
                                       hasConnectedStore: true, gogSignedIn: true, connectedStores: [.gog])
        #expect(snapshot.account == AccountSummary(connected: [.gog], steam: .signedOut))
        #expect(LibrarySnapshot.empty.account.tone == .signedOut)
    }

    // MARK: - No Refresh button: the library refreshes itself

    private let now = Date(timeIntervalSince1970: 1_000_000)

    @Test("The first read always happens, whatever asks for it", arguments: LibraryRefresh.Trigger.allCases)
    func firstReadAlwaysDue(_ trigger: LibraryRefresh.Trigger) {
        #expect(LibraryRefresh.isDue(trigger, lastRefresh: nil, now: now))
    }

    @Test("Anything Cellar did reads the library at once, even straight after another read",
          arguments: [LibraryRefresh.Trigger.opened, .actionFinished, .accountsChanged])
    func ownActionsAlwaysDue(_ trigger: LibraryRefresh.Trigger) {
        #expect(LibraryRefresh.isDue(trigger, lastRefresh: now, now: now))
    }

    @Test("Coming back to Cellar reads the library, but a burst of ⌘-Tabs reads it once")
    func activationCooldown() {
        let justNow = now.addingTimeInterval(-1)
        let aWhileAgo = now.addingTimeInterval(-LibraryRefresh.activationCooldown)
        #expect(!LibraryRefresh.isDue(.becameActive, lastRefresh: justNow, now: now))
        #expect(LibraryRefresh.isDue(.becameActive, lastRefresh: aWhileAgo, now: now))
    }

    @Test("While the window sits open the library is never older than the interval")
    func timer() {
        #expect(!LibraryRefresh.isDue(.timer, lastRefresh: now.addingTimeInterval(-60), now: now))
        #expect(LibraryRefresh.isDue(.timer, lastRefresh: now.addingTimeInterval(-LibraryRefresh.interval), now: now))
        #expect(LibraryRefresh.interval <= 5 * 60, "a library more than five minutes stale is the bug the button papered over")
    }
}
