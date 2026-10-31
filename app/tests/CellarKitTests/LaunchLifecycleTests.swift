import Foundation
import Testing
import CellarDomain
@testable import CellarKit

/// Launch → watch → quit → shut down, through Cellar's own calls, against a fake Wine.
///
/// This is the path every Play button takes, and until now only tier C (`CELLAR_IT=1`, a real
/// runner) walked it — so an ordinary PR could break it and stay green. Here it runs on every PR:
/// `FakeWine` stands in for the runner and records what Cellar hands it, and a fake exe stays alive
/// long enough to be found, then quits so the shutdown can be watched.
@Suite(.serialized)
struct LaunchLifecycleTests {

    /// A store-free Steam game whose exe is on disk, set up to stay alive for `seconds` once started.
    private func storeFreeGame(seconds: Int) throws -> (plan: GamePlan, exe: URL, exeName: String) {
        let install = try FakeWine.install()
        let exeName = "CellarFixture-\(UUID().uuidString.prefix(8)).exe"
        let plan = try TestHome.plan("""
        [game]
        name  = "Lifecycle Fixture"
        store = "steam"

        [compatibility]
        needs_live_session = false
        status             = "untested"

        [runner]
        id = "\(install.spec.id)"

        [install]
        steam_appid = "480"

        [launch]
        exe = "\(exeName)"

        [env]
        FIXTURE_ENV_MARKER = "1"
        """, slug: "lifecycle")
        try TestHome.installFakeGame(into: plan, at: exeName)
        let exe = try #require(plan.directLaunchExe)
        try FakeWine.keepAlive(exe, seconds: seconds)
        return (plan, exe, exeName)
    }

    @Test("A store-free game is handed to Wine with its prefix, locale and env, and watched until it is up")
    func directLaunchHandsWineTheGame() throws {
        let (plan, exe, exeName) = try storeFreeGame(seconds: 4)
        defer {
            ProcessWatch.kill([exeName])
            try? FileManager.default.removeItem(at: plan.prefix)
        }
        FakeWine.reset()
        #expect(plan.canLaunchStoreFree)

        var stages: [LaunchStage] = []
        let route = try Game.launch(plan, checkUpdates: false, stage: { stages.append($0) })

        guard case .direct(let watched) = route else {
            Issue.record("a store-free game with its exe on disk took the \(route.logDescription) route")
            return
        }
        #expect(watched == exeName)
        // The steps the launch window promised are the steps the launch took, and only then "running".
        #expect(stages == LaunchStage.sequence(plan.launchContext) + [.running])
        #expect(!stages.contains(.client), "no store client is opened for a game that runs bare")

        let call = try #require(FakeWine.calls().last(where: { $0.tool == "wine" && $0.arguments.first == exe.path }),
                                "Wine was never asked to run the game's exe")
        #expect(call.environment["WINEPREFIX"] == plan.prefix.path, "the game must run in its own bottle")
        #expect(call.environment["LANG"] == plan.language.language.environment["LANG"],
                "the game must start in the player's language, not the shell's")
        #expect(call.environment["LC_ALL"] == plan.language.language.environment["LC_ALL"])
        // Not a CELLAR_ name: a profile may not set Cellar's own variables (ProfileStore.deniedEnvPrefixes).
        #expect(call.environment["FIXTURE_ENV_MARKER"] == "1", "the profile's [env] must reach the game")
        #expect(call.environment["WINEDEBUG"] == "-all")
    }

    @Test("Quitting the game takes the layer down: Cellar waits the game out, then stops the wineserver")
    func quittingShutsTheLayerDown() throws {
        let (plan, _, exeName) = try storeFreeGame(seconds: 5)
        defer {
            ProcessWatch.kill([exeName])
            try? FileManager.default.removeItem(at: plan.prefix)
        }
        let route = try Game.launch(plan, checkUpdates: false)
        #expect(ProcessWatch.isRunning(exeName), "the fake game should still be up right after launch")
        FakeWine.reset()

        let started = Date()
        Game.waitForExitThenShutDown(plan, route: route)

        #expect(!ProcessWatch.isRunning(exeName), "Cellar returned while the game was still running")
        #expect(Date().timeIntervalSince(started) < 30, "the wait must end when the game does")
        #expect(FakeWine.calls().contains { $0.tool == "wineserver" && $0.arguments == ["-k"] },
                "the bottle's wineserver was never asked to stop")
    }

    @Test("A Wine process that outlives its bottle's wineserver is stopped, and nothing else is")
    func leftoversAreSwept() throws {
        let install = try FakeWine.install()
        // A real binary living inside the runner's tree, as `wine-preloader` does: the sweep finds
        // Wine's processes by the executable the kernel started, not by their command line.
        let straggler = install.binDirectory.appendingPathComponent("wine-preloader")
        try? FileManager.default.removeItem(at: straggler)
        try FileManager.default.copyItem(at: URL(fileURLWithPath: "/bin/sleep"), to: straggler)
        defer { try? FileManager.default.removeItem(at: straggler) }

        let orphan = Process()
        orphan.executableURL = straggler
        orphan.arguments = ["30"]
        let bystander = Process()
        bystander.executableURL = URL(fileURLWithPath: "/bin/sleep")
        bystander.arguments = ["30"]
        try orphan.run()
        try bystander.run()
        defer {
            if orphan.isRunning { orphan.terminate() }
            if bystander.isRunning { bystander.terminate() }
        }

        let swept = WineRunner(install: install, prefix: TestHome.scratch("sweep")).shutDown(grace: 1)

        let deadline = Date().addingTimeInterval(5)
        while orphan.isRunning, Date() < deadline { Thread.sleep(forTimeInterval: 0.1) }
        #expect(swept.contains(orphan.processIdentifier), "the leftover Wine process was not found")
        #expect(!orphan.isRunning, "the leftover Wine process is still running after the shutdown")
        #expect(bystander.isRunning, "a process outside the runner is never Cellar's to stop")
        #expect(!swept.contains(bystander.processIdentifier))
    }
}
