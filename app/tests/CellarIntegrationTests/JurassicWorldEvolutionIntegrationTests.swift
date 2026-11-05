import CellarDomain
import Foundation
import Testing
@testable import CellarData

/// Tier A: the three Jurassic World Evolution games (2026-11-05), read from `profiles/` the way an
/// installed Cellar reads them, reach the library as untested Steam games with their Steam cover,
/// each with a Mac estimate, and plan a launch that agrees with what the library shows. Real files,
/// no Wine.
@Suite(.serialized)
struct JurassicWorldEvolutionIntegrationTests {

    static let games: [(slug: String, appID: Int)] = [
        ("jurassic-world-evolution", 648350),
        ("jurassic-world-evolution-2", 1244460),
        ("jurassic-world-evolution-3", 2958130),
    ]

    @Test("Each reaches the library as an untested Steam game with its Steam cover and a Mac estimate")
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
            #expect(plan.facts.macRequirements != nil, "every game says which Mac it needs")
        }
    }
}
