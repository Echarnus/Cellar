import CellarDomain
import Foundation
import Testing
@testable import CellarKit

/// Tier A: play time, recorded by the same session hooks `cellar launch` calls and read back through
/// the library the app shows — including a session a crash never closed.
@Suite(.serialized)
struct PlaytimeIntegrationTests {

    @Test("A played session reaches the library, and one a crash left open is closed, not lost")
    func sessionsReachTheLibrary() throws {
        IT.ensure()
        let slug = IT.writeProfile("""
        [game]
        name = "Timed Game"
        store = "gog"
        """, slug: "it-playtime")

        let before = try #require(Game.summaries().first { $0.slug == slug })
        #expect(before.playtime == nil, "a game never played says nothing, not 0 hours")
        #expect(before.lastPlayed == nil)

        // A normal session: launch reports it up, then gone.
        Diagnostics.playSessionBegan(slug: slug, name: "Timed Game", route: "direct")
        Diagnostics.playSessionEnded(slug: slug, name: "Timed Game")
        let played = try #require(Game.summaries().first { $0.slug == slug }?.playtime)
        #expect(played.sessions == 1)
        #expect(played.openSince == nil)
        #expect(played.lastPlayed != nil)

        // A session whose `cellar launch` died with the game: begun, never ended. The next read of
        // the library closes it at the last sign of life rather than leaving it open forever.
        Diagnostics.playSessionBegan(slug: slug, name: "Timed Game", route: "direct")
        let recovered = try #require(Game.summaries().first { $0.slug == slug }?.playtime)
        #expect(recovered.sessions == 2, "the crashed session still counts")
        #expect(recovered.openSince == nil)
        #expect(recovered.totalSeconds >= played.totalSeconds, "and never takes time away")
    }
}
