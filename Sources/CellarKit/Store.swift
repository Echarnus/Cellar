import Foundation

/// Where a game comes from, and therefore *which client Cellar has to stand up inside the bottle*.
///
/// A store is not a cosmetic label. Each one has its own installer, its own idea of "signed in",
/// its own way of being told to install and to launch a title, and its own failure modes — so the
/// setup ladder, the launch sequence and the words shown to the player all differ per store. The
/// descriptor below is the single place that difference is written down; CellarKit, the CLI and the
/// app all read their vocabulary from here so the three never drift apart.
///
/// Adding a store means: a case here, a `*Bottle` type beside `SteamBottle` / `BattleNetBottle`,
/// a branch in `Game.setUp` / `Game.launch`, and a CLI command group. Nothing else should need to know.
public enum GameStore: String, CaseIterable, Sendable {
    /// Valve's Windows Steam client, installed inside the bottle.
    case steam
    /// Blizzard's Battle.net desktop app, installed inside the bottle.
    case battlenet
    /// GOG.com. No client in the bottle: Cellar holds an OAuth token, reads the player's owned
    /// library over HTTP, and installs the DRM-free installer itself.
    case gog
    /// No store at all — the game's files are on disk and its exe is launched directly.
    case standalone

    public static let `default` = GameStore.steam

    /// Parse a profile's `store = "…"` value. Unknown values return nil so the caller can fall
    /// back to the default rather than silently mis-classifying a game.
    public init?(profileValue: String?) {
        guard let raw = profileValue?.trimmingCharacters(in: .whitespaces).lowercased(), !raw.isEmpty else {
            return nil
        }
        switch raw {
        case "steam": self = .steam
        case "battlenet", "battle.net", "blizzard", "bnet": self = .battlenet
        case "gog", "gog.com", "gog-galaxy": self = .gog
        case "standalone", "none", "direct", "drm-free": self = .standalone
        default: return nil
        }
    }
}

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
    /// Nothing to sign in to.
    case none
}

/// Everything that differs per store, in one table: the words, the marks, and the shape of the
/// player's journey. Kept UI-framework-free (a hex string, not a `Color`) so CellarKit stays
/// dependency-light and the CLI and the app can both render it.
public struct StoreDescriptor: Sendable {
    public let store: GameStore
    /// "Steam", "Battle.net" — the client's own name, used verbatim in UI copy.
    public let displayName: String
    /// The heading a library section gets when games are grouped by store.
    public let sectionTitle: String
    /// Fallback SF Symbol, for contexts that cannot draw a real mark. The app draws each store's
    /// own logo as vectors instead (`StoreMark`) — nothing proprietary is shipped, see docs/LEGAL.md.
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

    static func components(fromHex hex: String) -> (red: Double, green: Double, blue: Double) {
        var value = UInt64(0)
        let digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        Scanner(string: digits).scanHexInt64(&value)
        return (Double((value >> 16) & 0xFF) / 255.0,
                Double((value >> 8) & 0xFF) / 255.0,
                Double(value & 0xFF) / 255.0)
    }
}

public extension GameStore {
    var descriptor: StoreDescriptor {
        switch self {
        case .steam:
            return StoreDescriptor(
                store: .steam,
                displayName: "Steam",
                sectionTitle: "Steam",
                symbolName: "gamecontroller.fill",
                accentHex: "#2C7FBF",
                accountNoun: "Steam account",
                canDetectSignIn: true,
                hasSilentInstaller: true,
                installLocation: "your Steam library",
                // Steam's QR device flow signs Cellar in for *downloads*, but a Steamworks game
                // still talks to a running client, so the bottle's own sign-in is the one that
                // matters at launch. Honest answer: the client window.
                authStyle: .inClientWindow,
                installsClientInBottle: true,
                // The one thing that must never be collateral damage: the shared install holds the
                // sign-in and every other Steam game's files.
                uninstallKeepsNote: "Your Steam sign-in and the shared Steam install, so every other Steam game keeps working.",
                uninstallClientNote: "Steam shows the game as not installed the next time it opens — the files are gone, the licence isn't.",
                requiresClientClosedToUninstall: true)
        case .battlenet:
            return StoreDescriptor(
                store: .battlenet,
                displayName: "Battle.net",
                sectionTitle: "Battle.net",
                symbolName: "hexagon.fill",
                accentHex: "#00A2E8",
                accountNoun: "Battle.net account",
                canDetectSignIn: false,
                hasSilentInstaller: false,
                installLocation: "the Battle.net app",
                authStyle: .inClientWindow,
                installsClientInBottle: true,
                uninstallKeepsNote: "Battle.net itself, your sign-in, and anything else installed in this bottle.",
                uninstallClientNote: "Battle.net offers the game as an install again next time it starts. That is it noticing the files are gone, not a failed uninstall.",
                requiresClientClosedToUninstall: true)
        case .standalone:
            return StoreDescriptor(
                store: .standalone,
                displayName: "Standalone",
                sectionTitle: "No store",
                symbolName: "shippingbox.fill",
                accentHex: "#8A8A8E",
                accountNoun: "no account",
                canDetectSignIn: false,
                hasSilentInstaller: true,
                installLocation: "a direct download",
                authStyle: .none,
                installsClientInBottle: false,
                uninstallKeepsNote: "Nothing else to keep — a standalone game brings no client and no account.",
                uninstallClientNote: nil,
                requiresClientClosedToUninstall: false)
        case .gog:
            return StoreDescriptor(
                store: .gog,
                displayName: "GOG",
                sectionTitle: "GOG",
                symbolName: "lock.open.fill",     // DRM-free: the one store with nothing to satisfy
                accentHex: "#9B4DCA",             // purple — the two other stores are both blue
                accountNoun: "GOG account",
                // Cellar holds the token, so it knows exactly who is signed in — and can say so.
                canDetectSignIn: true,
                hasSilentInstaller: true,
                installLocation: "your GOG library",
                authStyle: .cellarHeldToken,
                installsClientInBottle: false,
                uninstallKeepsNote: "Your GOG sign-in, which covers your whole library.",
                // GOG ships an Inno Setup installer, so it ships an uninstaller too — running it is
                // what takes the registry entries with the files.
                uninstallClientNote: "Cellar runs the game's own GOG uninstaller first, silently, so nothing is left in the bottle's registry.",
                requiresClientClosedToUninstall: false)
        }
    }

    var displayName: String { descriptor.displayName }

    /// Library ordering: stores appear in a stable, meaningful order rather than alphabetically.
    var sortIndex: Int {
        switch self {
        case .steam: return 0
        case .battlenet: return 1
        case .gog: return 2
        case .standalone: return 3
        }
    }
}

/// Shared helper for the Windows installers the stores hand us.
public enum WindowsInstaller {
    /// Whether a downloaded file really is a Windows executable. A CDN answers an outage with a
    /// perfectly valid HTML error page; feeding that to Wine fails in a baffling way, so every
    /// store installer is checked for the `MZ` magic before it is executed.
    public static func isPortableExecutable(_ file: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: file) else { return false }
        defer { try? handle.close() }
        return handle.readData(ofLength: 2) == Data([0x4D, 0x5A])   // "MZ"
    }
}
