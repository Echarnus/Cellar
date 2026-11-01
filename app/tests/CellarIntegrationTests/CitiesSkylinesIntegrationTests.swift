import CellarDomain
import Foundation
import Testing
@testable import CellarData

/// Tier A: the shipped Cities: Skylines II profile, read from `profiles/` the way an installed Cellar
/// reads it, reaches the library and plans a launch past the Paradox Launcher. Real files, no Wine.
@Suite(.serialized)
struct CitiesSkylinesIntegrationTests {

    static let slug = "cities-skylines-2"

    @Test("Cities: Skylines II reaches the library as an untested Steam game with a Steam cover")
    func reachesTheLibrary() throws {
        #expect(IT.shippedProfilesStaged)
        let summary = try #require(Game.summaries().first { $0.slug == Self.slug },
                                   "'\(Self.slug)' is in profiles/ but not among the games Cellar knows")
        #expect(summary.name == "Cities: Skylines II")
        #expect(summary.store == .steam)
        #expect(summary.facts.status == "untested")
        #expect(summary.artworkAppID == 949230)
        // The plan the launch would use agrees with what the library shows.
        let plan = try Game.plan(slug: Self.slug)
        #expect(plan.needsLiveSession)
        #expect(plan.backend == summary.backend)
        #expect(plan.fallbackBackend.flatMap(GraphicsBackend.init(rawValue:)) == .dxvk)
    }

    @Test("A downloaded copy on disk is launched as the game binary, not through Steam's Play button")
    func downloadedCopyLaunchesTheGame() throws {
        #expect(IT.shippedProfilesStaged)
        let plan = try Game.plan(slug: Self.slug)
        let fm = FileManager.default
        let exe = plan.depotGameDir.appendingPathComponent("Cities2.exe")
        try fm.createDirectory(at: plan.depotGameDir, withIntermediateDirectories: true)
        try Data("MZ".utf8).write(to: exe)
        // A Paradox Launcher beside it, as a real install has, must not be what Cellar picks.
        let launcher = plan.depotGameDir.appendingPathComponent("Launcher/dowser.exe")
        try fm.createDirectory(at: launcher.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("MZ".utf8).write(to: launcher)
        defer { try? fm.removeItem(at: plan.depotGameDir) }

        #expect(!SteamBottle.isGameInstalled(in: plan.prefix, appID: 949230),
                "with no appmanifest the Steam adapter launches the exe beside the client")
        #expect(plan.directLaunchExe?.path == exe.path)
        #expect(plan.directLaunchExe?.lastPathComponent != "dowser.exe")
    }
}
