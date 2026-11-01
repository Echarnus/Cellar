import Foundation

/// A publisher's own launcher that a game needs *as well as* the store it came from.
///
/// Not a store. The game is still bought, owned and downloaded through its store (Steam, for every
/// game that uses one today), and nothing about the library changes. But some publishers put their
/// own program between the store and the game: Rockstar's games, Steam's copies included, start
/// through the Rockstar Games Launcher, which signs the player in to a Rockstar Games account and
/// only then starts the game. On Windows, Steam installs that launcher itself the first time the
/// game is played. A copy Cellar downloaded never gets that step, so Cellar sets the launcher up in
/// the game's bottle the way it sets up a store client: the publisher's own download, run inside
/// the bottle, never bundled (`docs/LEGAL.md`).
///
/// A profile names one with `publisher_launcher = "rockstar"`.
public enum PublisherLauncher: String, CaseIterable, Sendable {
    /// Rockstar Games Launcher: Red Dead Redemption, Red Dead Redemption 2, Grand Theft Auto V.
    case rockstar

    /// Parse a profile's `publisher_launcher = "…"`. Missing means none. A value Cellar doesn't know
    /// is also nil, which `Game.plan` refuses rather than silently launching without the launcher.
    public init?(profileValue: String?) {
        guard let raw = profileValue?.trimmingCharacters(in: .whitespaces).lowercased(), !raw.isEmpty else {
            return nil
        }
        switch raw {
        case "rockstar", "rockstar-games", "rockstar-games-launcher", "rgl": self = .rockstar
        default: return nil
        }
    }

    /// The launcher's own name, the one the player sees on its window.
    public var displayName: String {
        switch self {
        case .rockstar: return "Rockstar Games Launcher"
        }
    }

    /// The account the launcher asks for — never a Cellar sign-in.
    public var accountNoun: String {
        switch self {
        case .rockstar: return "Rockstar Games account"
        }
    }

    /// Command-line fragments that identify the launcher's processes, for telling whether it is up
    /// and for closing it after setup. Wine reports Windows command lines, hence both separators.
    /// `Launcher.exe` alone would also match Battle.net's bootstrapper, so the folder is the needle.
    /// No needle ends in a backslash: `ProcessWatch.isRunning` puts it inside a double-quoted shell
    /// string, where a trailing `\` would escape the closing quote.
    public var processNeedles: [String] {
        switch self {
        case .rockstar:
            return [
                #"\Rockstar Games\Launcher"#, "/Rockstar Games/Launcher/",
                "RockstarService.exe", "SocialClubHelper.exe", "LauncherPatcher.exe",
            ]
        }
    }
}
