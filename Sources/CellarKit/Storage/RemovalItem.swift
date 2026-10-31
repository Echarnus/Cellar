import CellarDomain
import Foundation

/// One thing a removal will delete, resolved and measured before anything is touched.
public struct RemovalItem: Sendable, Identifiable {
    public enum Kind: Sendable {
        /// A file or directory on disk.
        case path
        /// An entry inside the native macOS Steam client's `shortcuts.vdf` — not a file of ours to
        /// delete, a line to take back out of somebody else's database.
        case steamShortcut
    }

    /// What this is, in the player's words: "Game files", "Launcher app".
    public let label: String
    public let url: URL
    public let bytes: Int64
    public let kind: Kind
    /// Whether this is the game's own data, as opposed to something Cellar generated around it (a
    /// launcher app, an icon, a log). A plan with none of it is a tidy-up, not an uninstall — and
    /// says so, rather than claiming to have removed a game that was never installed.
    public let isGameData: Bool

    public var id: String { "\(kind)-\(url.path)" }

    /// The path as a person would write it — `~/Library/…`, not `/Users/someone/Library/…`.
    public var displayPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return url.path.hasPrefix(home) ? "~" + url.path.dropFirst(home.count) : url.path
    }
}
