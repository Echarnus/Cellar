import Foundation

/// Everything that differs per store, in one table: the words, the marks, and the shape of the
/// player's journey. Kept UI-framework-free (a hex string, not a `Color`) so CellarData stays
/// dependency-light and the CLI and the app can both render it.
public struct StoreDescriptor: Sendable {
    public let store: GameStore
    /// "Steam", "Battle.net" — the client's own name, used verbatim in UI copy.
    public let displayName: String
    /// The heading a library section gets when games are grouped by store.
    public let sectionTitle: String
    /// Fallback SF Symbol, for contexts that cannot draw a real mark. The app draws each store's
    /// own mark instead (`StoreMark`), from the store's install on this machine where there is one
    /// (`StoreIcon`) — nothing proprietary is ever shipped, see docs/LEGAL.md.
    public let symbolName: String
    /// The store's accent, `#RRGGBB`, used for its chips, section heading and primary button. Close
    /// to each brand, and kept far enough apart in tone that two stores never read as the same
    /// thing — though colour is never the *only* signal (see skills/ux.md).
    public let accentHex: String
    /// "Steam account" — what the player is being asked to sign in to.
    public let accountNoun: String
    /// Whether Cellar can tell, from disk alone, that somebody is signed in. Steam writes
    /// `loginusers.vdf`; Battle.net exposes nothing comparable, so its readiness ladder folds
    /// sign-in into the "open the client" step instead of pretending to know.
    public let canDetectSignIn: Bool
    /// Whether the store's installer can run unattended. Steam's takes `/S`; Battle.net's has no
    /// silent switch, so setup has to *tell the player* that a window will appear and wait for them.
    public let hasSilentInstaller: Bool
    /// Where the game itself comes from, in the player's words.
    public let installLocation: String
    /// How signing in works for this store — see `StoreAuthStyle`.
    public let authStyle: StoreAuthStyle
    /// Whether Cellar has to stand the store's client up inside the bottle at all. False for GOG,
    /// which is pure HTTP, and that difference is why GOG needs no per-bottle sign-in.
    public let installsClientInBottle: Bool
    /// The Windows executables that *are* the client, so Cellar can keep them out of the Dock while
    /// a game is starting (see `DockShim`). Deliberately a list of the client's own processes and
    /// nothing else: anything not named here — the game, a mod tool, an installer — keeps its icon.
    public let clientProcessNames: [String]
    /// What survives when a game from this store is removed, in the player's words. Shown on every
    /// uninstall: what a player actually fears is losing the account or the other games, and for
    /// Steam that fear is well founded — one install and one sign-in serve every Steam game.
    public let uninstallKeepsNote: String
    /// What the store's client does once the files are gone, or nil when there is no client to do
    /// anything. Stops a re-appearing "Install" button reading as a failed uninstall.
    public let uninstallClientNote: String?
    /// Whether the client has to be closed before a game's files can be removed. A running client
    /// holds the files open and rewrites its manifests as it exits, which is how a half-deleted
    /// library happens — so Cellar closes it first, and says so beforehand.
    public let requiresClientClosedToUninstall: Bool

    /// Whether one sign-in covers the whole account rather than one bottle. Drives the Accounts
    /// screen: a store that is signed in once is listed once, not once per game.
    public var signsInOnce: Bool { authStyle == .cellarHeldToken }

    public var accentColorComponents: (red: Double, green: Double, blue: Double) {
        StoreDescriptor.components(fromHex: accentHex)
    }

    public static func components(fromHex hex: String) -> (red: Double, green: Double, blue: Double) {
        var value = UInt64(0)
        let digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        Scanner(string: digits).scanHexInt64(&value)
        return (Double((value >> 16) & 0xFF) / 255.0,
                Double((value >> 8) & 0xFF) / 255.0,
                Double(value & 0xFF) / 255.0)
    }
}
