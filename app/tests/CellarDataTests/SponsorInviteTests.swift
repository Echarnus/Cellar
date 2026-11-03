import Foundation
import Testing
@testable import CellarData

/// The sponsor invitation asks once, at a moment the player has had something from Cellar, and
/// never while there is nowhere to send money. Kenneth (2026-11-03): sponsoring is non-intrusive,
/// and nothing in Cellar is ever behind it.
@Suite("Sponsor invitation")
struct SponsorInviteTests {
    private static func freshDefaults() -> UserDefaults {
        let name = "SponsorInviteTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test("Asked once a game has been played after the first run, and never again")
    func asksOnce() {
        let invite = SponsorInvite(defaults: Self.freshDefaults(), isOpen: true)
        #expect(invite.isOwed(firstRunDone: true, hasPlayed: true))
        invite.markSeen()
        #expect(!invite.isOwed(firstRunDone: true, hasPlayed: true))
    }

    @Test("Never on a first run, and never before anything has been played")
    func notTooEarly() {
        let invite = SponsorInvite(defaults: Self.freshDefaults(), isOpen: true)
        #expect(!invite.isOwed(firstRunDone: false, hasPlayed: true))
        #expect(!invite.isOwed(firstRunDone: true, hasPlayed: false))
        #expect(!invite.isOwed(firstRunDone: false, hasPlayed: false))
    }

    @Test("Never while there is nowhere to send money")
    func notBeforeItIsOpen() {
        let invite = SponsorInvite(defaults: Self.freshDefaults(), isOpen: false)
        #expect(!invite.isOwed(firstRunDone: true, hasPlayed: true))
    }

    @Test("The app points at the site's sponsor page, which the generator writes")
    func pointsAtTheSite() throws {
        #expect(Sponsorship.pageURL.absoluteString == "https://echarnus.github.io/Cellar/sponsor.html")
        let generator = try String(contentsOf: Repo.root.appendingPathComponent("pages/gen-site.py"), encoding: .utf8)
        #expect(generator.contains("write(\"sponsor.html\""), "pages/gen-site.py no longer writes sponsor.html")
    }
}
