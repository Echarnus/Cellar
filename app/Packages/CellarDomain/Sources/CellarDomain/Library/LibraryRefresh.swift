import Foundation

/// **When the library re-reads itself.** There is no Refresh button in the sidebar: a library that
/// has to be told to look is one that shows a stale answer until the player guesses why. So every
/// moment the answer can have changed is a trigger, and this decides which of them actually read
/// the disk again.
///
/// Pure, so the rule is tested rather than trusted: the app calls `isDue` from each trigger and
/// keeps only the time of the last read.
public enum LibraryRefresh {
    /// What happened that might have changed the library.
    public enum Trigger: Sendable, Equatable, CaseIterable {
        /// The window opened.
        case opened
        /// The player came back to Cellar — maybe after downloading in the in-bottle Steam client,
        /// moving a game folder in Finder, or signing in from the CLI.
        case becameActive
        /// Something Cellar ran finished: an install, an uninstall, a setup, a check, a launch.
        case actionFinished
        /// A store was signed in, signed out, added or removed.
        case accountsChanged
        /// The quiet periodic read while the window sits open.
        case timer
    }

    /// Switching to Cellar and away again is not news: one read covers a burst of ⌘-Tabs.
    public static let activationCooldown: TimeInterval = 10
    /// How stale the library may get while Cellar is open and nothing else has asked.
    public static let interval: TimeInterval = 5 * 60

    /// Whether `trigger` should read the library now, given when it was last read.
    ///
    /// Anything Cellar itself did — opening, finishing an action, an account change — always reads:
    /// the player is looking at the result. Coming back to the app and the timer are the two that
    /// can fire with nothing new, so they wait out their own interval.
    public static func isDue(_ trigger: Trigger, lastRefresh: Date?, now: Date = Date()) -> Bool {
        guard let lastRefresh else { return true }
        let age = now.timeIntervalSince(lastRefresh)
        switch trigger {
        case .opened, .actionFinished, .accountsChanged: return true
        case .becameActive: return age >= activationCooldown
        case .timer: return age >= interval
        }
    }
}
