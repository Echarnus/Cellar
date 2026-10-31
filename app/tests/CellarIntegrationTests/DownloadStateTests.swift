import CellarDomain
import Foundation
import Testing
@testable import CellarData

/// Tier A: what the library says about a game while its files are arriving, read back from real
/// files in a real bottle (#167). A download that has written the exe is not an installed game.
@Suite(.serialized)
struct DownloadStateTests {

    @Test("Mid-download, then stopped, then finished: the library says each one truthfully")
    func downloadLifecycle() throws {
        IT.ensure()
        let slug = IT.writeProfile("""
        [game]
        name  = "Download State Fixture"
        store = "steam"
        steam_appid = 1

        [compatibility]
        needs_live_session = false

        [launch]
        exe = "Bin/game.exe"
        """, slug: "it-download-state")
        let plan = try Game.plan(slug: slug)
        let fm = FileManager.default
        try fm.createDirectory(at: plan.prefix, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: plan.prefix) }
        func summary() throws -> GameSummary { try #require(Game.summaries().first { $0.slug == slug }) }

        // The download begins, and DepotDownloader puts the exe down early.
        UnfinishedInstall.begin(plan)
        let exe = plan.depotGameDir.appendingPathComponent("Bin/game.exe")
        try fm.createDirectory(at: exe.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("MZ".utf8).write(to: exe)
        #expect(plan.directLaunchExe != nil)
        #expect(try summary().gameInstalled == false, "an exe at 3% is not an installed game")
        #expect(try summary().nextStep == .install, "Play is never offered for a game still arriving")

        // The app is quit mid-download: the note stays, and the game says so.
        let stopped = try summary()
        #expect(stopped.installInterrupted)
        #expect(stopped.actionHint.contains("picks up where it left off"))

        // Install runs again and completes.
        UnfinishedInstall.finish(plan)
        let done = try summary()
        #expect(done.gameInstalled)
        #expect(!done.installInterrupted)
        // Play, or repair where this machine has no runner for it: either way, past Install.
        #expect(done.nextStep != .install)
    }

    @Test("A real child process is stopped when the command that started it is")
    func childProcessStops() throws {
        let child = Process()
        child.executableURL = URL(fileURLWithPath: "/bin/sh")
        // A tool that keeps writing, as a download does, until it is told to stop.
        child.arguments = ["-c", "while true; do echo ' 1.00% file.pak'; sleep 0.05; done"]
        child.standardOutput = FileHandle.nullDevice
        try child.run()
        ChildProcesses.track(child)
        #expect(child.isRunning)
        #expect(ChildProcesses.terminateAll() == 0)
        child.waitUntilExit()
        #expect(!child.isRunning)
    }
}
