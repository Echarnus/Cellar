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
