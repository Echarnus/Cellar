import CellarDomain
import Foundation
import Testing
@testable import CellarData

/// A game is installed when its install finished, not when its exe appeared (#167). DepotDownloader
/// writes the exe early, and the page read "Installed" with Play at 3%.
@Suite(.serialized)
struct UnfinishedInstallTests {

    /// A store whose install puts the exe on disk and then stops, the way a download does when it
    /// is cancelled or the network drops partway.
    struct StoppingAdapter: StoreAdapter {
        var finishes = false
        var store: GameStore { .gog }
        func isClientInstalled(_ plan: GamePlan) -> Bool { true }
        var isClientRunning: Bool { false }
        func signedInAccount(_ plan: GamePlan) -> String? { nil }
        func recordsGameInstalled(_ plan: GamePlan) -> Bool? { nil }
        func setUpClient(_ plan: GamePlan, wine: WineRunner, step: (String) -> Void,
                         phase: (InstallProgress) -> Void) throws {}
        func installGame(_ plan: GamePlan, wine: WineRunner, step: (String) -> Void,
                         progress: (String) -> Void, phase: (InstallProgress) -> Void) throws {
            // Mid-download, the exe is already there and Cellar can see it.
            #expect(plan.directLaunchExe == nil, "the exe isn't written yet")
            try UnfinishedInstallTests.writeExe(for: plan)
            #expect(plan.directLaunchExe != nil)
            #expect(!Game.isGameInstalled(plan), "an exe that has landed mid-download is not a game")
            phase(InstallProgress(.downloading, fraction: 0.03))
            if !finishes { throw CellarError.ioFailure("DepotDownloader exited 143.") }
        }
        func openClient(_ plan: GamePlan, wine: WineRunner, showHUD: Bool) throws {}
        func launchThroughClient(_ plan: GamePlan, wine: WineRunner, showHUD: Bool, forceStore: Bool,
                                 progress: (String) -> Void, stage: (LaunchStage) -> Void,
                                 update: (InstallProgress) -> Void) throws -> LaunchRoute {
            .direct(exeName: "game.exe")
        }
    }

    static func writeExe(for plan: GamePlan) throws {
        let exe = plan.depotGameDir.appendingPathComponent("Bin/game.exe")
        try FileManager.default.createDirectory(at: exe.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("MZ".utf8).write(to: exe)
    }

    func plan(_ slug: String) throws -> GamePlan {
        try #require(TestHome.installStubRunner() != nil)
        let plan = try TestHome.plan("""
        [game]
        name  = "Unfinished Fixture"
        store = "gog"
        [launch]
        exe = "Bin/game.exe"
        """, slug: slug)
        try? FileManager.default.removeItem(at: plan.prefix)
        try FileManager.default.createDirectory(at: plan.prefix, withIntermediateDirectories: true)
        return plan
    }

    @Test("A stopped install leaves files but not a game, and the library says the download is incomplete")
    func stoppedInstall() throws {
        let plan = try plan("unfinished-stopped")
        defer { try? FileManager.default.removeItem(at: plan.prefix) }

        #expect(throws: CellarError.self) { try InstallGame(plan, adapter: StoppingAdapter()).run() }
        #expect(plan.directLaunchExe != nil, "the files that made it are kept, so Install can resume")
        #expect(!Game.isGameInstalled(plan))
        #expect(UnfinishedInstall.isPending(plan))
        let summary = LoadLibrary.summary(of: plan)
        #expect(!summary.gameInstalled)
        #expect(summary.installInterrupted)
        #expect(summary.nextStep == .install)
    }

    @Test("An install that finishes is installed, and leaves no note behind")
    func finishedInstall() throws {
        let plan = try plan("unfinished-finished")
        defer { try? FileManager.default.removeItem(at: plan.prefix) }

        #expect(throws: CellarError.self) { try InstallGame(plan, adapter: StoppingAdapter()).run() }
        // Install again: it picks up and this time completes.
        try? FileManager.default.removeItem(at: plan.depotGameDir)
        try InstallGame(plan, adapter: StoppingAdapter(finishes: true)).run()
        #expect(Game.isGameInstalled(plan))
        #expect(!UnfinishedInstall.isPending(plan))
        let summary = LoadLibrary.summary(of: plan)
        #expect(summary.gameInstalled)
        #expect(!summary.installInterrupted)
        #expect(summary.nextStep == .play)
    }

    @Test("Uninstalling a half-downloaded game clears the note with the files")
    func uninstallClears() throws {
        let plan = try plan("unfinished-uninstall")
        defer { try? FileManager.default.removeItem(at: plan.prefix) }

        UnfinishedInstall.begin(plan)
        try Self.writeExe(for: plan)
        let removal = Uninstall.plan(for: plan, scope: .game)
        #expect(removal.removesGameFiles, "a partial download is offered for removal like any game files")
        _ = try Uninstall.perform(removal, for: plan)
        #expect(!UnfinishedInstall.isPending(plan))
        #expect(!LoadLibrary.summary(of: plan).installInterrupted)
    }

    @Test("No bottle, no note: an install that never got that far leaves nothing behind")
    func noBottle() throws {
        let plan = try plan("unfinished-nobottle")
        try FileManager.default.removeItem(at: plan.prefix)
        UnfinishedInstall.begin(plan)
        #expect(!FileManager.default.fileExists(atPath: plan.prefix.path))
        #expect(!UnfinishedInstall.isPending(plan))
    }
}
