import CellarDomain
import SwiftUI
import AppKit
import CellarData

/// Whether the first-run tour is owed, and the record that it has been seen.
///
/// Versioned rather than a bool: when the tour gains a step that matters (a new store, a changed
/// sign-in), bumping `version` shows it once more to people who already ran the old one. Skipping
/// counts as seen — a tour that reappears after you dismissed it is nagging, not helping. It can
/// always be replayed from Settings.
enum WelcomeTour {
    /// Bump when the tour teaches something a returning player has not been told.
    static let version = 1
    private static let key = "welcomeTourVersionSeen"

    static var isOwed: Bool { UserDefaults.standard.integer(forKey: key) < version }
    static func markSeen() { UserDefaults.standard.set(version, forKey: key) }
}
