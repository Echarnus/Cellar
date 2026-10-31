import CellarDomain
import Foundation
import Testing
@testable import CellarKit

/// Playtime kept on this Mac: sessions add up, and one a crash left open is still closed.
@Suite(.serialized)
struct PlaytimeTests {

    @Test("Sessions add up and the last one is remembered")
    func sessionsAddUp() {
        TestHome.ensure()
        let slug = "play-\(UUID().uuidString.prefix(8))".lowercased()
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        Playtime.began(slug: slug, at: start)
        Playtime.ended(slug: slug, at: start.addingTimeInterval(3600))
        Playtime.began(slug: slug, at: start.addingTimeInterval(86_400))
        Playtime.ended(slug: slug, at: start.addingTimeInterval(86_400 + 1800))
        let record = Playtime.all()[slug]
        #expect(record?.sessions == 2)
        #expect(record?.totalSeconds == 5400)
        #expect(record?.lastPlayed == start.addingTimeInterval(86_400 + 1800))
        #expect(record?.openSince == nil)
    }

    @Test("A session a crash left open is closed at the last sign of life, not left running")
    func crashedSessionCloses() {
        TestHome.ensure()
        let slug = "crash-\(UUID().uuidString.prefix(8))".lowercased()
        let start = Date().addingTimeInterval(-600)
        Playtime.began(slug: slug, at: start)
        // Still running: left open.
        #expect(Playtime.all(isRunning: { $0 == slug })[slug]?.openSince != nil)
        // Gone without an end: closed, counted once, never longer than what was observed.
        let record = Playtime.all(isRunning: { _ in false })[slug]
        #expect(record?.openSince == nil)
        #expect(record?.sessions == 1)
        #expect((record?.totalSeconds ?? .max) <= 600)
    }

    @Test("Durations read like a person wrote them")
    func describe() {
        #expect(Playtime.describe(seconds: 30) == "under a minute")
        #expect(Playtime.describe(seconds: 45 * 60) == "45 min")
        #expect(Playtime.describe(seconds: 2 * 3600) == "2 h")
        #expect(Playtime.describe(seconds: 12 * 3600 + 5 * 60) == "12 h 5 min")
    }
}
