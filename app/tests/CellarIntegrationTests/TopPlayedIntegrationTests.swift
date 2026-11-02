import CellarDomain
import Foundation
import Testing
@testable import CellarData

/// Tier A: the top-50 Steam games added on 2026-11-01, read from `profiles/` the way an installed
/// Cellar reads them, reach the library as untested Steam games with a Steam cover, and plan a launch
/// that agrees with what the library shows. Real files, no Wine.
@Suite(.serialized)
struct TopPlayedIntegrationTests {

    static let games: [(slug: String, appID: Int)] = [
        ("counter-strike-2", 730),
        ("team-fortress-2", 440),
        ("deadlock", 1422450),
        ("phantom-blade-zero", 4115450),
        ("probably-stolen", 4348910),
        ("tbh-task-bar-hero", 3678970),
        ("enshrouded", 1203620),
        ("grand-theft-auto-v-enhanced", 3240220),
        ("moon-sweepers", 5335510),
        ("repo", 3241660),
        ("overwatch", 2357570),
        ("palworld", 1623730),
    ]

    @Test("Each reaches the library as an untested Steam game with its Steam cover")
    func reachesTheLibrary() throws {
        #expect(IT.shippedProfilesStaged)
        let summaries = Game.summaries()
        for game in Self.games {
            let summary = try #require(summaries.first { $0.slug == game.slug },
                                       "'\(game.slug)' is in profiles/ but not among the games Cellar knows")
            #expect(summary.store == .steam)
            #expect(summary.facts.status == "untested")
            #expect(summary.artworkAppID == game.appID)
            let plan = try Game.plan(slug: game.slug)
            #expect(plan.needsLiveSession)
            #expect(plan.backend == summary.backend)
        }
    }

    @Test("A copy Steam's client installed is launched as the game binary, even with a space in its name")
    func clientInstalledCopyLaunchesTheGame() throws {
        #expect(IT.shippedProfilesStaged)
        let plan = try Game.plan(slug: "probably-stolen")
        let fm = FileManager.default
        let root = plan.prefix.appendingPathComponent(
            "drive_c/Program Files (x86)/Steam/steamapps/common/Probably Stolen", isDirectory: true)
        let exe = root.appendingPathComponent("Probably Stolen.exe")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("MZ".utf8).write(to: exe)
        defer { try? fm.removeItem(at: plan.prefix) }

        #expect(plan.directLaunchExe?.path == exe.path)
        #expect(!plan.canLaunchStoreFree, "Steamworks still needs the client running")
    }
}
