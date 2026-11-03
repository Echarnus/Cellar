import CellarDomain
import Foundation

/// Sponsoring Cellar: money for test Macs, never a paywall.
///
/// Cellar is free and every feature works for everyone, always (Kenneth, 2026-11-03). Sponsoring
/// pays for Macs of every chip tier to test games on, and the site says exactly what it buys. The
/// app only ever points at that page — the payment link lives on the site (`pages/gen-site.py`,
/// `SPONSOR_LINKS`), so it can change without an app release.
public enum Sponsorship {
    /// Whether there is somewhere to send money yet. While `false` the one-time invitation is
    /// never shown — spending the only time we ask on a page that says "not yet" would waste it —
    /// but the page stays reachable from the app menu and Settings › About. Flip it in the same
    /// change that fills in `SPONSOR_LINKS` on the site.
    public static let isOpen = false

    /// The site's sponsor page: what the money buys, what it has bought, and how to give.
    public static let pageURL = URL(string: "https://echarnus.github.io/Cellar/sponsor.html")!
}

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
