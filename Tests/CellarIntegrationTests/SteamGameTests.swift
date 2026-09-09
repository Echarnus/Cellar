import Foundation
import Testing
@testable import CellarKit

/// Tier D: a **real Steam game**, downloaded from a real depot with the player's own sign-in, and
/// started on this Mac.
///
/// Tier C already proves the pipeline end to end, but it does it with `winemine.exe` — 100 KB of
/// Win32 that ships inside Wine. Everything between "a profile exists" and "a window appears" is
/// exercised there *except* the part players actually do: authenticate to a store, pull a couple of
/// gigabytes of somebody else's game, and run an engine that expects a GPU. That gap is what this
/// tier closes, and Fallout Shelter is the cheapest title that closes it — free-to-play, ~2 GB,
/// **Windows-only** (so a pass cannot secretly be a native macOS build), single-player and
/// DRM-free, which is what lets Cellar take the store-free route and watch the game directly.
///
/// It skips far more often than it runs, so the skip is designed as carefully as the pass: the
/// reason is a sentence naming the fix, and `reportsWhyItCannotRun` prints it on every run. A tier
/// that quietly does nothing is worse than no tier at all.
///
/// ```sh
/// cellar steam login              # once — a QR scan, no password
/// sh Scripts/test.sh --steam      # the Wine tiers plus this one
/// ```
@Suite(.serialized)
struct SteamGameTests {

    /// Fallout Shelter unless the environment points somewhere else.
    static let game = IT.SteamGame.configured

    /// Asked once. Ownership is a network round-trip, and every test in the tier wants the answer.
    static let blocker: String? = IT.steamBlocker(for: game)

    static var canRun: Bool { blocker == nil }

    // MARK: - Always

    /// Runs on every machine, including CI, and never fails for being unable to download anything.
    /// Its whole job is to make the tier's state legible in the log someone reads before a release.
    @Test("The tier says out loud whether it ran, and why not when it didn't")
    func reportsWhyItCannotRun() throws {
        let game = Self.game
        if let blocker = Self.blocker {
            IT.log("Steam tier SKIPPED for \(game.slug) (app \(game.appID)): \(blocker)")
        } else {
            IT.log("Steam tier ENABLED: Steam will hand over app \(game.appID) for this account")
        }

        // The profile it would run must exist and agree with the tier's expectations either way —
        // otherwise the tier could sit skipped for months while the profile rotted underneath it.
        _ = IT.shippedProfilesStaged
        let plan = try Game.plan(slug: game.slug)
        #expect(plan.appID == game.appID)
        #expect(plan.launchExe == game.exe)
        #expect(plan.installDir == game.installDir)
        #expect(plan.needsLiveSession == false,
                "this tier watches the game's own process, which only works when no client is in the way")
    }

    // MARK: - The real thing

    @Test("A real Steam game downloads, installs and runs — profile → depot → launch → shut down",
          .enabled(if: SteamGameTests.canRun, "\(SteamGameTests.blocker ?? "")"),
          .timeLimit(.minutes(30)))
    func steamGameEndToEnd() throws {
        let fm = FileManager.default
        let game = Self.game
        _ = IT.shippedProfilesStaged

        // 1. The profile the repo actually ships — not a fixture. If this test passes, that file is
        //    correct, which is the only reason it is worth downloading two gigabytes to find out.
        let plan = try Game.plan(slug: game.slug)
        IT.log("game under test: \(plan.name) (Steam app \(game.appID))")
        defer {
            Game.wineRunner(plan)?.killServer()
            // The bottle is inside the throwaway CELLAR_HOME, so the download goes with it.
        }

        // 2. Nothing installed yet: Cellar must offer to download, and must not promise Play.
        #expect(Game.isGameInstalled(plan) == false)
        #expect(plan.directLaunchExe == nil)
        #expect(plan.canLaunchStoreFree == false)

        // 3. Runner + bottle. No store client: this game does not need one, and saying so is the
        //    difference between a 2 GB install and a 3.4 GB one.
        var progress: [String] = []
        _ = try Game.setUp(plan) { progress.append($0); IT.log($0) }
        #expect(fm.fileExists(atPath: plan.prefix.appendingPathComponent("system.reg").path),
                "no registry hive — the bottle never initialised")
        #expect(progress.contains { $0.contains("No store client needed") },
                "a store-free game must be told plainly that nothing else is being installed")

        // 4. The download, through Cellar's own call rather than a hand-rolled DepotDownloader
        //    command line — a test that drove the tool itself would pass while `fetchDepot` broke.
        IT.log("downloading app \(game.appID) from Steam — this is the slow part")
        try IT.downloadFromSteam(plan) { IT.log($0) }

        // 5. What arrived is what the profile promised. This is the assertion that turns the
        //    profile's "verified from Steam's app record" into "verified against the actual files":
        //    if Bethesda renames the executable, this is where Cellar finds out.
        let exe = try #require(plan.directLaunchExe,
                               "the depot downloaded but \(game.exe) is not where the profile says it is")
        #expect(exe.lastPathComponent == game.exe)
        #expect(WindowsInstaller.isPortableExecutable(exe),
                "\(game.exe) is not a Windows PE — the wrong platform's depot was fetched")
        let size = (try? fm.attributesOfItem(atPath: exe.path)[.size] as? Int) ?? 0
        #expect(size > 100_000, "\(game.exe) is \(size) bytes — that is a stub, not the game")
        IT.log("installed \(exe.path)")

        // 6. Readiness flips, and the copy now truthfully promises a launch with no client at all.
        #expect(Game.isGameInstalled(plan))
        #expect(plan.canLaunchStoreFree)
        let ready = try #require(Game.summaries().first { $0.slug == plan.slug })
        #expect(ready.nextStep == .play)
        #expect(ready.actionTitle == "Play")
        #expect(ready.actionHint.contains("no store client at all"))

        // 7. Launch it, through the same call the Play button makes.
        let route = try Game.launch(plan) { IT.log($0) }
        guard case .direct(let launched) = route else {
            Issue.record("expected the direct route for a DRM-free game, got \(route)")
            return
        }
        #expect(launched == game.exe)

        // 8. The proof: a Windows-only game is running on this Mac. Given generously — a Unity
        //    title compiles shaders on first start, which `winemine.exe` never made us wait for.
        let needles = plan.gameProcessNeedles
        #expect(!needles.isEmpty)
        let logFile = Paths.logs.appendingPathComponent("game-\(plan.slug).log")
        let appeared = ProcessWatch.waitToAppear(needles, seconds: 180)
        if !appeared {
            Issue.record("""
            \(game.exe) never appeared after launch. Wine log: \(logFile.path)
            """)
        }
        #expect(appeared, "the Windows game did not start under Cellar")
        IT.log("\(game.exe) is running under Wine on macOS")

        // 9. Cellar wrote the log a player would attach to a bug report.
        #expect(fm.fileExists(atPath: logFile.path))

        // 10. Quitting takes the whole layer down — what makes Cellar a launcher rather than a pile
        //     of Wine processes left behind on the machine.
        ProcessWatch.kill(needles)
        ProcessWatch.waitToExit(needles, graceSeconds: 10)
        #expect(ProcessWatch.isRunningAny(needles) == false, "the game process outlived the shutdown")

        Game.wineRunner(plan)?.killServer()
        Thread.sleep(forTimeInterval: 2)
        let wine = try #require(Game.wineRunner(plan))
        #expect(wine.serverRunning == false, "wineserver kept the bottle alive after shutdown")
    }

    @Test("Steam is asked about ownership with the credential that would do the downloading",
          .enabled(if: SteamGameTests.canRun, "\(SteamGameTests.blocker ?? "")"))
    func ownershipIsCheckedNotAssumed() throws {
        let credentials = try #require(SteamAccount.credentials)

        // The same question, asked again: a licence Cellar cannot confirm must never be reported as
        // owned. Free-to-play is exactly where this goes wrong — "free" reads like "everyone has
        // it", and Steam still refuses the depot until the account has actually added it, which is
        // why this tier checks rather than assuming.
        #expect(DepotTool.access(appID: Self.game.appID, credentials: credentials) == .available)
    }
}
