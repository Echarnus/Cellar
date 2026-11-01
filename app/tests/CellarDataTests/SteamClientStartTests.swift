import CellarDomain
import Foundation
import Testing
@testable import CellarData

/// A bottle's Steam that never starts is said to have not started — not blamed on the sign-in.
///
/// #190: the bottle's `wine` had been replaced with a script that runs nothing, so Steam never
/// came up. Play waited forty seconds for it, three minutes for a logon, took the bottle's
/// remembered sign-in away, waited fifteen more minutes for a window that was never there, and
/// then said "Nobody signed in to Steam" to a player who was signed in.
@Suite(.serialized)
struct SteamClientStartTests {

    // MARK: - What the polls say

    @Test("A client never seen once is 'never started' at the start deadline, not before")
    func neverStarted() {
        var watch = SteamBottle.ClientStartWatch(startTimeout: 40)
        #expect(watch.observe(running: false, elapsed: 2) == .waiting)
        #expect(watch.observe(running: false, elapsed: 38) == .waiting)
        #expect(watch.observe(running: false, elapsed: 40) == .neverStarted)
    }

    @Test("A client that was seen is never 'never started', however long the sign-in takes")
    func seenOnceIsStarted() {
        var watch = SteamBottle.ClientStartWatch(startTimeout: 40)
        #expect(watch.observe(running: true, elapsed: 2) == .waiting)
        #expect(watch.observe(running: true, elapsed: 600) == .waiting)
        #expect(watch.seenRunning)
    }

    @Test("Gone for a few polls is a restart; gone for many is closed")
    func restartVersusClosed() {
        var watch = SteamBottle.ClientStartWatch(startTimeout: 40, closedAfterPolls: 3)
        _ = watch.observe(running: true, elapsed: 2)
        #expect(watch.observe(running: false, elapsed: 4) == .waiting)
        #expect(watch.observe(running: false, elapsed: 6) == .waiting)
        #expect(watch.observe(running: true, elapsed: 8) == .waiting, "back up: Steam restarting after an update")
        #expect(watch.observe(running: false, elapsed: 10) == .waiting)
        #expect(watch.observe(running: false, elapsed: 12) == .waiting)
        #expect(watch.observe(running: false, elapsed: 14) == .closed)
    }

    // MARK: - The cold start

    @Test("A cold start that never shows a client ends the launch, saying Steam didn't start")
    func coldStartNeverComesUp() throws {
        var polls = 0
        do {
            try SteamBottle.waitForClientToComeUp(prefix: TestHome.scratch("bottle"), game: "Planet Coaster 2",
                                                  running: { polls += 1; return false },
                                                  ready: { true }, sleep: { _ in })
            Issue.record("expected the launch to stop")
        } catch {
            let message = "\(error)"
            #expect(message.contains("Steam didn't start in Planet Coaster 2's bottle"))
            #expect(!message.contains("Nobody signed in"))
            #expect(message.contains("isn't about your Steam sign-in"))
        }
        #expect(polls == Int(SteamBottle.clientStartSeconds / 2), "gave up at the deadline, not sooner")
    }

    @Test("A client that comes up and is current lets the launch go on at once")
    func coldStartComesUp() throws {
        var polls = 0
        try SteamBottle.waitForClientToComeUp(prefix: TestHome.scratch("bottle"), game: "Planet Coaster 2",
                                              running: { polls += 1; return polls >= 3 },
                                              ready: { true }, sleep: { _ in })
        #expect(polls == 3)
    }

    @Test("A client still updating at the deadline is left to what follows, as before")
    func coldStartStillUpdating() throws {
        try SteamBottle.waitForClientToComeUp(prefix: TestHome.scratch("bottle"), game: "Planet Coaster 2",
                                              running: { true }, ready: { false }, sleep: { _ in })
    }

    // MARK: - The test harness itself

    @Test("The fake Wine is never written through a link into a real runner")
    func fakeWineStaysInTheSandbox() throws {
        let fm = FileManager.default
        // Stands in for the player's runner: deliberately outside the sandbox, as
        // `IntegrationSupport` links ~/Library/Application Support/Cellar/runners/<id>.
        let outside = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("cellar-real-runner-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: outside) }
        #expect(!TestHome.isInside(outside))
        let realWine = outside.appendingPathComponent("wine/bin/wine")
        try fm.createDirectory(at: realWine.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "the real loader".write(to: realWine, atomically: true, encoding: .utf8)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: realWine.path)

        let link = Paths.runners.appendingPathComponent(RunnerCatalog.defaultID, isDirectory: true)
        try fm.createDirectory(at: Paths.runners, withIntermediateDirectories: true)
        try? fm.removeItem(at: link)
        try fm.createSymbolicLink(at: link, withDestinationURL: outside)

        let install = try FakeWine.install()

        #expect(try String(contentsOf: realWine, encoding: .utf8) == "the real loader")
        #expect(!fm.fileExists(atPath: outside.appendingPathComponent("wine/bin/wineserver").path))
        #expect(!TestHome.isSymbolicLink(link), "the link is replaced by the sandbox's own runner")
        #expect(TestHome.isInside(install.wineBinary))
    }

    @Test("A path that leads out of the sandbox through a link is not inside it")
    func insideResolvesLinks() throws {
        let fm = FileManager.default
        let outside = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("cellar-outside-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: outside, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: outside) }
        let link = TestHome.scratch("link").appendingPathComponent("out")
        try fm.createSymbolicLink(at: link, withDestinationURL: outside)
        #expect(TestHome.isInside(TestHome.scratch("plain")))
        #expect(!TestHome.isInside(link.appendingPathComponent("wine/bin/wine")))
    }
}
