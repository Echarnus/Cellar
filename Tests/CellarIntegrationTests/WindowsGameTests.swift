import Foundation
import Testing
@testable import CellarKit

/// Tier B and C: the tests that actually translate Windows.
///
/// Everything else in this repository can pass while a game refuses to start. These run a real
/// runner, build a real Wine prefix and put a real Windows executable on screen, then take the
/// layer down again — the same sequence a player triggers by pressing Play.
///
/// Opt in with `CELLAR_IT=1`. See `docs/TESTING.md`.
@Suite(.serialized, .enabled(if: IT.wineTierEnabled, "set CELLAR_IT=1 to run the Wine tiers"))
struct WindowsGameTests {

    // MARK: - Tier B: the layer itself

    @Test("The machine can translate x86-64 Windows at all")
    func machineIsCapable() throws {
        #expect(SystemEnvironment.isAppleSilicon, "Cellar's D3DMetal path requires Apple Silicon")
        #expect(SystemEnvironment.rosettaWorks,
                "every runner Cellar ships is an x86_64 Wine; without Rosetta nothing can start")
        IT.log("host: \(SystemEnvironment.chipBrand), macOS \(SystemEnvironment.macOSVersionString)")
    }

    @Test("A runner resolves to an executable wine binary")
    func runnerIsUsable() throws {
        try #require(IT.machineCanRunWine)
        let runner = try IT.resolveRunner { IT.log($0) }

        #expect(FileManager.default.isExecutableFile(atPath: runner.wineBinary.path))
        #expect(runner.wineBinary.deletingLastPathComponent().lastPathComponent == "bin")

        let wine = WineRunner(install: runner, prefix: IT.scratch("version-probe"))
        let version = wine.wineVersion()
        #expect(!version.isEmpty, "`wine --version` printed nothing — the runner is not runnable")
        IT.log("runner: \(runner.spec.id) — \(version), D3DMetal: \(runner.hasD3DMetal)")
    }

    @Test("A fresh prefix initialises as WoW64, which is what the 32-bit store clients need")
    func prefixInitialisesAsWoW64() throws {
        try #require(IT.machineCanRunWine)
        let runner = try IT.resolveRunner()
        let name = "it-prefix-\(UUID().uuidString.prefix(6))"
        let info = try PrefixManager.create(name: name, backend: .d3dmetal, runner: runner.spec.id)
        let wine = WineRunner(install: runner, prefix: info.url)
        defer { wine.killServer(); try? PrefixManager.remove(name: name) }

        try wine.initializePrefix()
        try wine.setWindowsVersion("win10")

        let fm = FileManager.default
        #expect(fm.fileExists(atPath: info.url.appendingPathComponent("system.reg").path),
                "no registry hive — Game.setUp treats this prefix as uninitialised forever")
        #expect(fm.fileExists(atPath: info.url.appendingPathComponent("drive_c/windows").path))
        #expect(fm.fileExists(atPath: info.url.appendingPathComponent("drive_c/Program Files (x86)").path),
                "a non-WoW64 build cannot install Steam or Battle.net — Game.setUp checks this too")

        let registry = try String(contentsOf: info.url.appendingPathComponent("user.reg"), encoding: .utf8)
        #expect(registry.contains("win10"), "the Windows version Cellar set must survive in the hive")
    }

    @Test("A Windows PE executes inside the prefix and its output comes back")
    func windowsExecutableRuns() throws {
        try #require(IT.machineCanRunWine)
        let runner = try IT.resolveRunner()
        let name = "it-exec-\(UUID().uuidString.prefix(6))"
        let info = try PrefixManager.create(name: name, backend: .d3dmetal, runner: runner.spec.id)
        let wine = WineRunner(install: runner, prefix: info.url)
        defer { wine.killServer(); try? PrefixManager.remove(name: name) }

        try wine.initializePrefix()
        let result = wine.run(["cmd", "/c", "echo cellar-translation-works"])
        #expect(result.stdout.contains("cellar-translation-works"),
                "a Windows console program produced no output — the translation layer is broken")
    }

    // MARK: - Tier C: a Windows-only game, end to end

    @Test("A Windows-only game goes profile → bottle → launch → watched → shut down")
    func windowsOnlyGameEndToEnd() throws {
        try #require(IT.machineCanRunWine)
        let fm = FileManager.default
        let runner = try IT.resolveRunner { IT.log($0) }
        let source = IT.GameSource.configured
        IT.log("game under test: \(source.label)")

        // 1. A profile is the only thing a player has to add for a new game.
        let slug = IT.writeProfile("""
        [game]
        slug  = "it-windows-game"
        name  = "Integration Fixture"
        store = "standalone"

        [compatibility]
        # DRM-free: no client has to be alive for this to run, which is what lets Cellar take the
        # direct route and makes the whole thing observable in a test.
        needs_live_session = false
        status             = "untested"

        [runner]
        id = "\(runner.spec.id)"

        [graphics]
        backend = "d3dmetal"

        [launch]
        exe = "\(source.relativeExe)"

        [env]
        CELLAR_INTEGRATION_MARKER = "1"
        """, slug: "it-windows-game")

        let plan = try Game.plan(slug: slug)
        #expect(plan.store == .standalone)
        #expect(plan.needsLiveSession == false)
        #expect(plan.env["CELLAR_INTEGRATION_MARKER"] == "1", "the profile's env must reach the game")
        defer {
            Game.wineRunner(plan)?.killServer()
            try? fm.removeItem(at: plan.prefix)
        }

        // 2. Before anything is installed, Cellar must say so rather than offering Play.
        #expect(plan.directLaunchExe == nil)
        #expect(Game.isGameInstalled(plan) == false)
        #expect(summary(for: slug)?.nextStep == .install)

        // 3. Set up: runner + bottle + initialised prefix. No store client — this game has no store.
        var progress: [String] = []
        _ = try Game.setUp(plan) { progress.append($0); IT.log($0) }
        #expect(fm.fileExists(atPath: plan.prefix.appendingPathComponent("system.reg").path))
        #expect(progress.contains { $0.contains("No store client needed") },
                "a standalone game must be told plainly that nothing else is being installed")

        // 4. The game's files arrive. Cellar never ships these; the test provides them.
        let exe = try IT.installGameFiles(source, into: plan, runner: runner)
        #expect(WindowsInstaller.isPortableExecutable(exe),
                "whatever we are about to run must really be a Windows executable")
        IT.log("installed \(exe.lastPathComponent) into \(plan.depotGameDir.path)")

        // 5. Readiness flips, and the copy now promises a store-free launch — truthfully.
        #expect(plan.directLaunchExe?.path == exe.path)
        #expect(plan.canLaunchStoreFree)
        #expect(Game.isGameInstalled(plan))
        let ready = try #require(summary(for: slug))
        #expect(ready.nextStep == .play)
        #expect(ready.actionTitle == "Play")
        #expect(ready.actionHint.contains("no store client at all"))

        // 6. Launch it — the real thing, through the same call the Play button makes.
        let route = try Game.launch(plan) { IT.log($0) }
        guard case .direct(let exeName) = route else {
            Issue.record("expected the direct route for a DRM-free game, got \(route)")
            return
        }
        #expect(exeName == source.exeName)

        // 7. The proof: the Windows process is alive on this Mac.
        let needles = plan.gameProcessNeedles
        #expect(!needles.isEmpty)
        let appeared = ProcessWatch.waitToAppear(needles, seconds: 90)
        if !appeared {
            let log = plan.slug
            Issue.record("""
            \(source.exeName) never appeared after launch. \
            Wine log: \(Paths.logs.appendingPathComponent("game-\(log).log").path)
            """)
        }
        #expect(appeared, "the Windows game did not start under Cellar")
        IT.log("\(source.exeName) is running under Wine on macOS")

        // 8. Cellar wrote a log for it, which is what a player would send in a bug report.
        let logFile = Paths.logs.appendingPathComponent("game-\(plan.slug).log")
        #expect(fm.fileExists(atPath: logFile.path))

        // 9. Quitting takes the whole layer down — the behaviour that makes Cellar a launcher
        //    rather than a pile of Wine processes.
        ProcessWatch.kill(needles)
        ProcessWatch.waitToExit(needles, graceSeconds: 5)
        #expect(ProcessWatch.isRunningAny(needles) == false, "the game process outlived the shutdown")

        Game.wineRunner(plan)?.killServer()
        Thread.sleep(forTimeInterval: 2)
        let wine = try #require(Game.wineRunner(plan))
        #expect(wine.serverRunning == false, "wineserver kept the bottle alive after shutdown")
    }

    @Test("A game whose files are missing refuses to launch, and says what to do")
    func missingFilesRefuseToLaunch() throws {
        try #require(IT.machineCanRunWine)
        let runner = try IT.resolveRunner()
        let slug = IT.writeProfile("""
        [game]
        store = "standalone"
        [compatibility]
        needs_live_session = false
        [runner]
        id = "\(runner.spec.id)"
        [launch]
        exe = "NeverInstalled.exe"
        """, slug: "it-missing")

        let plan = try Game.plan(slug: slug)
        defer { try? FileManager.default.removeItem(at: plan.prefix) }

        do {
            _ = try Game.launch(plan)
            Issue.record("launching a game with no files on disk must not succeed")
        } catch let error as CellarError {
            // The message a player actually gets. `Game.launch` never reaches `launchDirect`'s
            // "No launchable exe found" for this case — that one is only possible once the files
            // are on disk, because `canLaunchStoreFree` gates the direct route. With nothing
            // installed, launch falls through to the store switch, and for a game with no store
            // the honest answer is that it isn't installed yet.
            #expect(error.description.contains("isn't installed yet"))
            #expect(error.description.contains(plan.slug), "the message must name the game")
            #expect(error.description.contains("cellar install"),
                    "refusing to launch is only half of it — the message has to say what to do next")
        }
    }

    // MARK: - Helpers

    private func summary(for slug: String) -> GameSummary? {
        Game.summaries().first { $0.slug == slug }
    }
}
