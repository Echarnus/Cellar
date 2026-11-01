import CellarDomain
import Foundation
import Testing
@testable import CellarData

/// The Rockstar Games Launcher: the publisher's own program that Steam's Rockstar games start
/// through, which Cellar installs into a game's bottle because a depot download never runs Steam's
/// install script for it.
///
/// Installed against `FakeWine`, so what Cellar hands Wine is checked on every PR without a
/// runner, and Rockstar's download is replaced by a local file so no network is involved.
@Suite(.serialized)
struct RockstarLauncherTests {

    /// What a call threw, as text, or nil when it didn't throw.
    private func failure(_ body: () throws -> Void) -> String? {
        do { try body(); return nil } catch { return "\(error)" }
    }

    // MARK: - The profile field

    @Test("A profile names the launcher with publisher_launcher, in any of its spellings")
    func parsesTheField() throws {
        #expect(PublisherLauncher(profileValue: "rockstar") == .rockstar)
        #expect(PublisherLauncher(profileValue: " Rockstar-Games-Launcher ") == .rockstar)
        #expect(PublisherLauncher(profileValue: "RGL") == .rockstar)
        #expect(PublisherLauncher(profileValue: nil) == nil)
        #expect(PublisherLauncher(profileValue: "  ") == nil)
        #expect(PublisherLauncher(profileValue: "ubisoft-connect") == nil)

        let named = try TestHome.plan("""
        [install]
        steam_appid        = "1174180"
        publisher_launcher = "rockstar"
        """, slug: "rockstar-field")
        #expect(named.publisherLauncher == .rockstar)

        let none = try TestHome.plan("""
        [install]
        steam_appid = "480"
        """, slug: "rockstar-none")
        #expect(none.publisherLauncher == nil, "no field means no launcher: every other game is untouched")
    }

    @Test("A launcher Cellar doesn't know is refused, not silently left out of setup")
    func unknownLauncherIsRefused() throws {
        let slug = TestHome.writeProfile("""
        [install]
        steam_appid        = "480"
        publisher_launcher = "origin"
        """, slug: "rockstar-unknown")
        let error = try #require(failure { _ = try Game.plan(slug: slug) })
        #expect(error.contains("publisher launcher 'origin'") && error.contains("rockstar"))
    }

    @Test("Play starts start_exe when it is on disk beside the game, and the game's exe otherwise")
    func startExeResolvesBesideTheGame() throws {
        let plan = try TestHome.plan("""
        [install]
        steam_appid = "1174180"
        exe         = "RDR2.exe"
        start_exe   = "PlayRDR2.exe"
        """, slug: "rockstar-start")
        #expect(plan.directStartExe == nil, "nothing on disk yet, so nothing to start")

        try TestHome.installFakeGame(into: plan, at: "RDR2.exe")
        let game = try #require(plan.directLaunchExe)
        // Only the game: a stub that isn't there must not be started, or the launch fails in Wine.
        #expect(plan.directStartExe == game)

        try TestHome.installFakeGame(into: plan, at: "PlayRDR2.exe")
        #expect(plan.directStartExe == game.deletingLastPathComponent().appendingPathComponent("PlayRDR2.exe"))
        // What is watched stays the game itself: the stub hands off and exits.
        #expect(plan.directLaunchExe == game)
        #expect(plan.gameProcessNeedles.first == "RDR2.exe")
    }

    // MARK: - Installing it

    private func bottle(_ label: String) throws -> (plan: GamePlan, wine: WineRunner) {
        let install = try FakeWine.install()
        let plan = try TestHome.plan("""
        [runner]
        id = "\(install.spec.id)"

        [install]
        steam_appid        = "1174180"
        publisher_launcher = "rockstar"
        """, slug: label)
        try FileManager.default.createDirectory(at: plan.prefix, withIntermediateDirectories: true)
        let wine = try #require(Game.wineRunner(plan))
        FakeWine.reset()
        return (plan, wine)
    }

    private static func writeWindowsProgram(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data([0x4D, 0x5A] + [UInt8](repeating: 0, count: 62)).write(to: url)
    }

    @Test("Setup runs Rockstar's installer in the bottle, waits for the launcher, and says a window will open")
    func installsIntoTheBottle() throws {
        let (plan, wine) = try bottle("rockstar-install")
        #expect(!RockstarLauncher.isInstalled(in: plan.prefix))
        #expect(PublisherLauncher.rockstar.isInstalled(in: plan.prefix) == false)

        var fetched: URL?
        var lines: [String] = []
        // The installer downloads the launcher itself; stand in for that by landing Launcher.exe
        // shortly after Wine is asked to run it.
        let launcher = RockstarLauncher.executable(in: plan.prefix)
        DispatchQueue.global().asyncAfter(deadline: .now() + 1) {
            try? Self.writeWindowsProgram(launcher)
        }
        try RockstarLauncher.install(runner: wine, fetch: { url in
            fetched = url
            try Self.writeWindowsProgram(url)
        }, waitSeconds: 20, progress: { lines.append($0) })

        let installer = try #require(fetched)
        #expect(installer.lastPathComponent == "Rockstar-Games-Launcher.exe")
        #expect(RockstarLauncher.isInstalled(in: plan.prefix))
        #expect(launcher.path.hasSuffix("drive_c/Program Files/Rockstar Games/Launcher/Launcher.exe"))
        // Exactly one Wine call, and it is the installer: no silent switch Rockstar never documented.
        let calls = FakeWine.calls().filter { $0.tool == "wine" }
        #expect(calls.count == 1)
        #expect(calls.first?.arguments == [installer.path])
        #expect(calls.first?.environment["WINEPREFIX"] == plan.prefix.path)
        // The window is announced before it opens, and the sign-in is put where it belongs.
        let announced = try #require(lines.firstIndex { $0.contains("a window will open") })
        let waiting = try #require(lines.firstIndex { $0.contains("Waiting for the Rockstar Games Launcher") })
        #expect(announced < waiting)
        #expect(lines.contains { $0.contains("first time you press Play") })
        #expect(lines.last == "Rockstar Games Launcher installed.")
        #expect(!FileManager.default.fileExists(atPath: installer.path), "the installer is not kept in the cache")
    }

    @Test("A bottle that already has the launcher is left alone: no download, no Wine")
    func alreadyInstalledIsANoOp() throws {
        let (plan, wine) = try bottle("rockstar-present")
        try Self.writeWindowsProgram(RockstarLauncher.executable(in: plan.prefix))
        var downloads = 0
        var lines: [String] = []
        try RockstarLauncher.install(runner: wine, fetch: { _ in downloads += 1 }, waitSeconds: 1,
                                     progress: { lines.append($0) })
        #expect(downloads == 0)
        #expect(FakeWine.calls().isEmpty)
        #expect(lines == ["Rockstar Games Launcher is already installed in this bottle."])
    }

    @Test("A download that isn't a Windows program is thrown away, never run")
    func refusesANonProgram() throws {
        let (plan, wine) = try bottle("rockstar-html")
        var fetched: URL?
        let error = try #require(failure {
            try RockstarLauncher.install(runner: wine, fetch: { url in
                fetched = url
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try Data("<html>503 Service Unavailable</html>".utf8).write(to: url)
            }, waitSeconds: 1)
        })
        #expect(error.contains("wasn't a Windows program"))
        #expect(FakeWine.calls().isEmpty, "an error page handed to Wine fails in a baffling way")
        #expect(fetched.map { FileManager.default.fileExists(atPath: $0.path) } == false)
        #expect(!RockstarLauncher.isInstalled(in: plan.prefix))
    }

    @Test("An installer that never lands the launcher fails setup with a next step, not a ✓")
    func installThatNeverFinishesFails() throws {
        let (_, wine) = try bottle("rockstar-stalled")
        let error = try #require(failure {
            try RockstarLauncher.install(runner: wine, fetch: { try Self.writeWindowsProgram($0) }, waitSeconds: 1)
        })
        #expect(error.contains("didn't finish installing") && error.contains("Run setup again"))
    }

    @Test("Closing the launcher uses patterns pkill can read: no backslash escapes, both separators")
    func killPatternsAreRegexSafe() {
        for pattern in RockstarLauncher.killPatterns {
            #expect(!pattern.contains("\\"), "'\(pattern)' would be read as a regex escape by pkill -f")
        }
        let folder = try! NSRegularExpression(pattern: RockstarLauncher.killPatterns[0])
        for line in [#"C:\Program Files\Rockstar Games\Launcher\Launcher.exe"#,
                     "/Users/me/drive_c/Program Files/Rockstar Games/Launcher/Launcher.exe"] {
            #expect(folder.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) != nil)
        }
        // Battle.net's bootstrapper is also a "Launcher.exe"; it must never be caught by this.
        let blizzard = "C:\\Program Files (x86)\\Battle.net\\Battle.net Launcher.exe"
        #expect(folder.firstMatch(in: blizzard, range: NSRange(blizzard.startIndex..., in: blizzard)) == nil)
        #expect(!PublisherLauncher.rockstar.processNeedles.contains("Launcher.exe"))
        // `isRunning` puts a needle inside a double-quoted `sh -c` string: a trailing backslash
        // would escape the closing quote and the check would never match anything.
        for needle in PublisherLauncher.rockstar.processNeedles {
            #expect(!needle.hasSuffix("\\"), "'\(needle)' ends in a backslash")
            #expect(!needle.contains("\""), "'\(needle)' contains a quote")
        }
    }

    // MARK: - Waiting for the game behind it

    @Test("A long wait for the game ends early once what it waits on has gone")
    func supervisorStopsWaitingWhenTheLauncherCloses() throws {
        var starts = 0
        let began = Date()
        let error = try #require(failure {
            try ProcessWatch.superviseStart(
                attempts: 2, appearSeconds: 60, settleSeconds: 1, backoffSeconds: 0,
                cleanup: {}, start: { starts += 1 }, isUp: { false },
                keepWaiting: { false })
        })
        #expect(error.contains("never started"), "it never appeared, so it never closed either")
        #expect(starts == 2)
        // Two 60-second waits would be two minutes; a closed launcher ends each in one poll.
        #expect(Date().timeIntervalSince(began) < 20)
    }
}
