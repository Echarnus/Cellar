import Foundation

/// **The account button at the foot of the sidebar** — who the player is signed in as, in words.
///
/// It replaced an unlabelled person icon in the header, which said nothing about whether anyone was
/// signed in. The button now reads as the answer: the Steam account name and the stores behind it,
/// "Sign in" when there are none, and an expired Steam session said out loud, since that is the one
/// state where the library quietly stops being right.
public struct AccountSummary: Sendable, Equatable {
    /// How the button should look, beyond its words.
    public enum Tone: Sendable, Equatable {
        /// The library hasn't been read yet, so nobody knows. Never "Sign in": a player who is signed
        /// in must not be told otherwise for the second it takes Cellar to look (Kenneth, #266).
        case loading
        /// No store connected: the button is the invitation to sign in.
        case signedOut
        /// At least one store connected, all well.
        case connected
        /// Something the player has to fix — Steam rejected its stored session.
        case needsAttention
    }

    /// The first line: whose account, or "Sign in".
    public let title: String
    /// The second line: which stores, or what is wrong.
    public let detail: String
    public let tone: Tone
    /// The connected stores, in library order.
    public let stores: [GameStore]
    /// The Steam account's own picture, as a file on this Mac, when Cellar has one. Shown in place
    /// of the generic person, so the player recognises their account at a glance.
    public let avatar: URL?

    /// Before the first read of the library: no claim either way.
    public static let loading = AccountSummary(title: String(localized: "Loading…"), detail: "", tone: .loading)

    private init(title: String, detail: String, tone: Tone) {
        self.title = title
        self.detail = detail
        self.tone = tone
        self.stores = []
        self.avatar = nil
    }

    /// - Parameters:
    ///   - connected: the stores Cellar may speak for (`StoreLibrary.isConnected`), in any order.
    ///   - steam: the one Steam sign-in, whose account name is the most recognisable one to show.
    ///   - offered: the stores this build shows (`StoreAvailability`). A connected store that isn't
    ///     offered is left off the button, and the signed-out line names only the offered ones.
    public init(connected: [GameStore], steam: SteamSignInState,
                offered: [GameStore] = GameStore.offered, avatar: URL? = nil) {
        let stores = GameStore.allCases.filter { connected.contains($0) && offered.contains($0) }
            .sorted { $0.sortIndex < $1.sortIndex }
        self.stores = stores
        // Only beside a Steam account name: the picture is that account's, and it would be wrong
        // next to "Sign in" or "Your accounts".
        self.avatar = steam.accountName != nil && stores.contains(.steam) ? avatar : nil
        if case .expired(let account, _) = steam {
            title = account
            detail = String(localized: "Steam sign-in expired")
            tone = .needsAttention
        } else if stores.isEmpty {
            title = String(localized: "Sign in")
            detail = StoreAvailability.phrase(offered)
            tone = .signedOut
        } else {
            // Steam's is the only account name Cellar reads without asking anyone. The others are
            // named on the line below, which is enough to tell the stores apart.
            title = steam.isUsable ? steam.accountName ?? String(localized: "Your accounts")
                                   : String(localized: "Your accounts")
            detail = stores.map(\.displayName).joined(separator: " · ")
            tone = .connected
        }
    }
}
