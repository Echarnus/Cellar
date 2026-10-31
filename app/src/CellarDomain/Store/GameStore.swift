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
/// a `StoreAdapter`, and a CLI command group. Nothing else should need to know.
public enum GameStore: String, CaseIterable, Sendable {
    /// Valve's Windows Steam client, installed inside the bottle.
    case steam
    /// Blizzard's Battle.net desktop app, installed inside the bottle.
    case battlenet
    /// GOG.com. No client in the bottle: Cellar holds an OAuth token, reads the player's owned
    /// library over HTTP, and installs the DRM-free installer itself.
    case gog

    /// Parse a profile's `store = "…"` value. Unknown and missing values return nil, and a profile
    /// that resolves to nil is refused (`Game.plan`) rather than guessed at: Cellar only runs games
    /// a store installed, so there is no "no store" and no default store to fall back to.
    public init?(profileValue: String?) {
        guard let raw = profileValue?.trimmingCharacters(in: .whitespaces).lowercased(), !raw.isEmpty else {
            return nil
        }
        switch raw {
        case "steam": self = .steam
        case "battlenet", "battle.net", "blizzard", "bnet": self = .battlenet
        case "gog", "gog.com", "gog-galaxy": self = .gog
        default: return nil
        }
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
                // The client itself, never the game: `steamwebhelper.exe` is the one that takes the
                // Dock icon (verified with `lsappinfo`), the rest are helpers Steam runs at startup.
                clientProcessNames: [
                    "steam.exe",
                    "steamwebhelper.exe",
                    "steamservice.exe",
                    "steamsysinfo.exe",
                    "steamerrorreporter.exe",
                    "steamerrorreporter64.exe",
                    "gldriverquery.exe",
                    "gldriverquery64.exe",
                    "vulkandriverquery.exe",
                    "vulkandriverquery64.exe",
                ],
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
                // `Agent.exe` is the update agent and `Battle.net Helper.exe` its browser
                // subprocesses — both outlive the client and both go when the bottle shuts down.
                clientProcessNames: [
                    "Battle.net.exe",
                    "Battle.net Launcher.exe",
                    "Battle.net Helper.exe",
                    "Agent.exe",
                ],
                uninstallKeepsNote: "Battle.net itself, your sign-in, and anything else installed in this bottle.",
                uninstallClientNote: "Battle.net offers the game as an install again next time it starts. That is it noticing the files are gone, not a failed uninstall.",
                requiresClientClosedToUninstall: true)
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
                clientProcessNames: [],   // pure HTTP, no client to hide
                uninstallKeepsNote: "Your GOG sign-in, which covers your whole library.",
                // GOG ships an Inno Setup installer, so it ships an uninstaller too — running it is
                // what takes the registry entries with the files.
                uninstallClientNote: "Cellar runs the game's own GOG uninstaller first, silently, so nothing is left in the bottle's registry.",
                requiresClientClosedToUninstall: false)
        }
    }

    var displayName: String { descriptor.displayName }

    /// Library ordering: stores appear in a stable, meaningful order rather than alphabetically.
    /// Package-wide, not public: `GameStore.inLibraryOrder` is the API.
    package var sortIndex: Int {
        switch self {
        case .steam: return 0
        case .battlenet: return 1
        case .gog: return 2
        }
    }
}
