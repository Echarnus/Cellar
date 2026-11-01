import CellarDomain
import Foundation
import Testing
@testable import CellarData

/// Tier A: the five Steam games added on request on 2026-11-01 (both Dark Souls, both Fallouts,
/// Planet Zoo), read from `profiles/` the way an installed Cellar reads them, reach the library as
/// untested Steam games with a Steam cover, and plan a launch that agrees with what the library
/// shows. Real files, no Wine.
@Suite(.serialized)
struct RequestedGamesIntegrationTests {

    static let games: [(slug: String, appID: Int)] = [
        ("dark-souls-remastered", 570940),
        ("dark-souls-2", 335300),
        ("fallout-4", 377160),
        ("fallout-new-vegas", 22380),
        ("planet-zoo", 703080),
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

    @Test("Dark Souls II's client-installed copy is found under its Game folder and launched as the game")
    func nestedExeLaunchesTheGame() throws {
        #expect(IT.shippedProfilesStaged)
        let plan = try Game.plan(slug: "dark-souls-2")
        let fm = FileManager.default
        let root = plan.prefix.appendingPathComponent(
            "drive_c/Program Files (x86)/Steam/steamapps/common/Dark Souls II Scholar of the First Sin", isDirectory: true)
        let exe = root.appendingPathComponent("Game/DarkSoulsII.exe")
        try fm.createDirectory(at: exe.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("MZ".utf8).write(to: exe)
        defer { try? fm.removeItem(at: plan.prefix) }

        #expect(plan.directLaunchExe?.path == exe.path)
        #expect(!plan.canLaunchStoreFree, "Steamworks still needs the client running")
        #expect(plan.gameProcessNeedles.contains { "C:\\steamapps\\common\\Dark Souls II Scholar of the First Sin\\Game\\DarkSoulsII.exe".contains($0) })
    }
}
