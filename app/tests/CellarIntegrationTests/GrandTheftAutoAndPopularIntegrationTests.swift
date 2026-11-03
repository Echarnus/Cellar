import CellarDomain
import Foundation
import Testing
@testable import CellarData

/// Tier A: the GTA games (#290), Hogwarts Legacy (#291), Sleeping Dogs (#292) and the nine popular
/// games (#293) added on 2026-11-03, read from `profiles/` the way an installed Cellar reads them,
/// reach the library as untested Steam games with their Steam covers, and a Definitive Edition
/// installed by the Steam client plans a launch that starts Steam's stub. Real files, no Wine.
@Suite(.serialized)
struct GrandTheftAutoAndPopularIntegrationTests {

    static let games: [(slug: String, appID: Int)] = [
        ("grand-theft-auto-iv", 12210),
        ("grand-theft-auto-iii-definitive-edition", 1546970),
        ("grand-theft-auto-vice-city-definitive-edition", 1546990),
        ("grand-theft-auto-san-andreas-definitive-edition", 1547000),
        ("grand-theft-auto-iii", 12100),
        ("grand-theft-auto-vice-city", 12110),
        ("grand-theft-auto-san-andreas", 12120),
        ("hogwarts-legacy", 990080),
        ("sleeping-dogs-definitive-edition", 307690),
        ("sekiro-shadows-die-twice", 814380),
        ("monster-hunter-world", 582010),
        ("monster-hunter-wilds", 2246340),
        ("god-of-war", 1593500),
        ("black-myth-wukong", 2358720),
        ("clair-obscur-expedition-33", 1903340),
        ("satisfactory", 526870),
        ("lethal-company", 1966720),
        ("schedule-i", 3164500),
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

    @Test("A client-installed San Andreas Definitive Edition starts Steam's stub and watches the game")
    func definitiveEditionStartsTheStub() throws {
        #expect(IT.shippedProfilesStaged)
        let plan = try Game.plan(slug: "grand-theft-auto-san-andreas-definitive-edition")
        let fm = FileManager.default
        let root = plan.prefix.appendingPathComponent(
            "drive_c/Program Files (x86)/Steam/steamapps/common/GTA San Andreas - The Definitive Edition",
            isDirectory: true)
        let game = root.appendingPathComponent("Gameface/Binaries/Win64/SanAndreas.exe")
        try fm.createDirectory(at: game.deletingLastPathComponent(), withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: plan.prefix) }
        try Data("MZ".utf8).write(to: game)
        try Data("MZ".utf8).write(to: root.appendingPathComponent("PlayGTASanAndreas.exe"))

        #expect(plan.directLaunchExe?.lastPathComponent == "SanAndreas.exe")
        #expect(plan.directStartExe?.path == root.appendingPathComponent("PlayGTASanAndreas.exe").path)
        #expect(plan.publisherLauncher == .rockstar)
        #expect(!plan.canLaunchStoreFree, "Steamworks still needs the client running")
    }
}
