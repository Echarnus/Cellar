import CellarDomain
import Foundation

/// The one time the app asks, and the record that it has.
///
/// Shown once, and only once the player has played a game through Cellar — never on a first run,
/// never in front of the tour or the folder ask, never while nothing has worked for them yet.
/// Closing it by any route counts as seen. Versioned like `WelcomeTour`, though a bump should be
/// rare: asking again is the nagging this is designed not to do.
public struct SponsorInvite {
    public static let version = 1
    static let key = "sponsorInviteVersionSeen"

    private let defaults: UserDefaults
    private let isOpen: Bool

    public init(defaults: UserDefaults = .standard, isOpen: Bool = Sponsorship.isOpen) {
        self.defaults = defaults
        self.isOpen = isOpen
    }

    /// - Parameters:
    ///   - firstRunDone: the welcome tour has been seen and the folder ask has run.
    ///   - hasPlayed: at least one game has been played through Cellar.
    public func isOwed(firstRunDone: Bool, hasPlayed: Bool) -> Bool {
        isOpen && firstRunDone && hasPlayed && defaults.integer(forKey: Self.key) < Self.version
    }

    public func markSeen() { defaults.set(Self.version, forKey: Self.key) }
}
