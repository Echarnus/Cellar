import CellarDomain
import Foundation
import Testing
@testable import CellarData

/// Tier A: Elden Ring, read from `profiles/` the way an installed Cellar reads it, reaches the
/// library as an untested Steam game with its Steam cover, and a client-installed copy plans a
/// launch that starts Easy Anti-Cheat's starter and watches the game. Real files, no Wine.
@Suite(.serialized)
struct EldenRingIntegrationTests {

    @Test("Reaches the library as an untested Steam game with its Steam cover")
    func reachesTheLibrary() throws {
        #expect(IT.shippedProfilesStaged)
        let summary = try #require(Game.summaries().first { $0.slug == "elden-ring" },
                                   "'elden-ring' is in profiles/ but not among the games Cellar knows")
        #expect(summary.store == .steam)
        #expect(summary.facts.status == "untested")
        #expect(summary.artworkAppID == 1245620)
        #expect(summary.backend == (try Game.plan(slug: "elden-ring")).backend)
    }

    @Test("A client-installed copy starts through Easy Anti-Cheat's starter beside Steam")
    func startsThroughTheStarter() throws {
        #expect(IT.shippedProfilesStaged)
        let plan = try Game.plan(slug: "elden-ring")
        let fm = FileManager.default
        let folder = plan.prefix.appendingPathComponent(
            "drive_c/Program Files (x86)/Steam/steamapps/common/ELDEN RING/Game", isDirectory: true)
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: plan.prefix) }
        try Data("MZ".utf8).write(to: folder.appendingPathComponent("eldenring.exe"))
        try Data("MZ".utf8).write(to: folder.appendingPathComponent("start_protected_game.exe"))

        #expect(plan.directLaunchExe?.lastPathComponent == "eldenring.exe")
        #expect(plan.directStartExe?.lastPathComponent == "start_protected_game.exe")
        #expect(!plan.canLaunchStoreFree, "Steamworks still needs the client running")
    }
}
