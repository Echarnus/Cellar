import Foundation
import Testing
@testable import CellarKit

/// The shipped race-sim profiles, Assetto Corsa and Assetto Corsa Competizione, pinned in detail.
///
/// Both are Steam games whose DRM wants a running Steam client, and both are made to be driven with
/// a wheel — so they are the first profiles to carry the `wheel` and `wheel_setup` fields. What they
/// must not do is claim a wheel result nobody has seen: they are untested, and say so.
@Suite(.serialized)
struct RaceSimTests {

    /// Staged once, by the database lint, so two suites never delete each other's copies mid-run.
    static let staged: Bool = { _ = ProfileDatabaseTests.slugs; return true }()

    static func plan(_ slug: String) throws -> GamePlan {
        _ = staged
        return try Game.plan(slug: slug)
    }

    struct Expected: Sendable, CustomTestStringConvertible {
        let slug: String
        let name: String
        let appID: Int
        let installDir: String
        let exe: String
        let backend: GraphicsBackend
        let fallback: GraphicsBackend
        var testDescription: String { slug }
    }

    static let games: [Expected] = [
        Expected(slug: "assetto-corsa", name: "Assetto Corsa", appID: 244210,
                 installDir: "assettocorsa", exe: "AssettoCorsa.exe",
                 // CrossOver users document DXVK working and D3DMetal not; D3DMetal stays as fallback.
                 backend: .dxvk, fallback: .d3dmetal),
        Expected(slug: "assetto-corsa-competizione", name: "Assetto Corsa Competizione", appID: 805550,
                 installDir: "Assetto Corsa Competizione", exe: "AC2/Binaries/Win64/AC2-Win64-Shipping.exe",
                 backend: .d3dmetal, fallback: .dxvk),
    ]

    @Test("Each ships as a Steam game with the right AppID, install folder and exe", arguments: RaceSimTests.games)
    func identity(_ game: Expected) throws {
        let plan = try Self.plan(game.slug)
        #expect(plan.name == game.name)
        #expect(plan.store == .steam)
        #expect(plan.appID == game.appID, "the AppID is what Steam is told to start; a wrong one starts someone else's game")
        #expect(plan.installDir == game.installDir)
        #expect(plan.launchExe == game.exe)
        #expect(plan.installMethod == "windows-steam-in-bottle")
    }

    @Test("Steamworks DRM means both need a running Steam client", arguments: RaceSimTests.games)
    func needsSteam(_ game: Expected) throws {
        let plan = try Self.plan(game.slug)
        #expect(plan.needsLiveSession, "a Steamworks game started with no client exits straight back to nothing")
        #expect(plan.launchContext.throughClient, "with no files on disk the launch goes through Steam")
    }

    @Test("Each picks the backend public reports favour, with the other as its fallback", arguments: RaceSimTests.games)
    func backends(_ game: Expected) throws {
        let plan = try Self.plan(game.slug)
        #expect(plan.backend == game.backend.rawValue)
        #expect(plan.profileBackend == game.backend.rawValue)
        #expect(plan.fallbackBackend == game.fallback.rawValue)
        #expect(plan.runnerID == "wineforge")
    }

    @Test("Neither claims more than has been run: untested, and the wheel untested too", arguments: RaceSimTests.games)
    func honest(_ game: Expected) throws {
        let facts = try Self.plan(game.slug).facts
        #expect(facts.status == "untested")
        #expect(facts.wheel == "untested")
        #expect(facts.compatibility.contains {
            $0.label == "Racing wheel" && $0.value == "Made for a wheel, not yet tried with one in Cellar"
        })
        let notes = try #require(facts.notes)
        #expect(notes.contains("Not yet launched under Cellar"))
        #expect(facts.anticheat?.hasPrefix("none") == true,
                "neither ships kernel anti-cheat, and the profile must not imply one")
    }

    @Test("Each tells the player how to bind a wheel inside the game", arguments: RaceSimTests.games)
    func wheelSetup(_ game: Expected) throws {
        let setup = try #require(try Self.plan(game.slug).facts.wheelSetup)
        #expect(setup.contains("Options"), "the steps start from the game's own menu")
        #expect(setup.contains("Controls"))
        // The setup text is shown verbatim: no promise of force feedback that nobody has felt.
        #expect(!setup.lowercased().contains("force feedback"))
    }

    @Test("The game's own processes are what Cellar watches, never Steam's", arguments: RaceSimTests.games)
    func needles(_ game: Expected) throws {
        let needles = try Self.plan(game.slug).gameProcessNeedles
        #expect(needles.contains((game.exe as NSString).lastPathComponent))
        // AC's launcher starts acs.exe from the same folder; the folder needle is what catches it.
        #expect(needles.contains("\\\(game.installDir)\\"))
        for needle in needles { #expect(!needle.lowercased().contains("steam")) }
    }

    @Test("A copy Steam's client installed is found, down to ACC's nested game binary", arguments: RaceSimTests.games)
    func findsClientInstalledCopy(_ game: Expected) throws {
        let plan = try Self.plan(game.slug)
        let fm = FileManager.default
        #expect(plan.directLaunchExe == nil)

        let root = plan.prefix.appendingPathComponent(
            "drive_c/Program Files (x86)/Steam/steamapps/common/\(game.installDir)", isDirectory: true)
        let exe = root.appendingPathComponent(game.exe)
        try fm.createDirectory(at: exe.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("MZ".utf8).write(to: exe)
        defer { try? fm.removeItem(at: plan.prefix) }

        #expect(plan.directLaunchExe?.path == exe.path)
        #expect(!plan.canLaunchStoreFree, "the files being there does not make Steamworks DRM go away")
    }

    // MARK: - The `wheel` vocabulary

    @Test("A profile's wheel field is shown in words, and no field shows no row")
    func wheelWords() throws {
        #expect(Wheels.support("full") == "Steering, pedals and force feedback")
        #expect(Wheels.support(" Steering ") == "Steering and pedals, no force feedback")
        #expect(Wheels.support("untested") == "Made for a wheel, not yet tried with one in Cellar")
        #expect(Wheels.support("none") == "No wheel support")
        #expect(Wheels.support(nil) == nil)
        #expect(Wheels.support("  ") == nil)

        let slug = TestHome.writeProfile("""
        [game]
        name = "Pad Only"
        store = "gog"
        """, slug: "nowheel")
        let facts = try Game.plan(slug: slug).facts
        #expect(facts.wheel == nil && facts.wheelSetup == nil)
        #expect(!facts.compatibility.contains { $0.label == "Racing wheel" },
                "a game nobody drives with a wheel gets no wheel row")
    }
}
