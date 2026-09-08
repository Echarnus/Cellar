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
        case "standalone", "none", "direct", "drm-free": self = .standalone
        default: return nil
        }
    }
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
                installLocation: "your Steam library")
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
                installLocation: "the Battle.net app")
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
                installLocation: "a direct download")
        }
    }

    var displayName: String { descriptor.displayName }

    /// Library ordering: stores appear in a stable, meaningful order rather than alphabetically.
    var sortIndex: Int {
        switch self {
        case .steam: return 0
        case .battlenet: return 1
        case .standalone: return 2
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
