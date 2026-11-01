import CellarDomain
import Foundation
import Testing
@testable import CellarData

/// The five games from Steam's Most Played top 20 (2026-11-01) that have no Mac version, no
/// kernel-level anti-cheat, and were not already in the database, pinned in detail.
///
/// Three are Valve's own online games on VAC (Counter-Strike 2, Team Fortress 2, Deadlock), one is a
/// Denuvo-protected DirectX 12 single-player game (Phantom Blade Zero), and one a small DirectX 10
/// game (Probably Stolen). None has been run on a Mac yet, and every profile says so.
@Suite(.serialized)
struct TopPlayedTests {

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
        let fallback: GraphicsBackend?
        /// An online game on VAC: the profile must say playing online is at the player's own risk.
        let vac: Bool
        var testDescription: String { slug }
    }

    static let games: [Expected] = [
        Expected(slug: "counter-strike-2", name: "Counter-Strike 2", appID: 730,
                 installDir: "Counter-Strike Global Offensive", exe: "game/bin/win64/cs2.exe",
                 backend: .d3dmetal, fallback: .dxvk, vac: true),
        // DirectX 9: D3DMetal does not translate it, so DXVK leads and WineD3D is the fallback.
        Expected(slug: "team-fortress-2", name: "Team Fortress 2", appID: 440,
                 installDir: "Team Fortress 2", exe: "tf_win64.exe",
                 backend: .dxvk, fallback: .wined3d, vac: true),
        Expected(slug: "deadlock", name: "Deadlock", appID: 1422450,
                 installDir: "Deadlock", exe: "game/bin/win64/deadlock.exe",
                 backend: .d3dmetal, fallback: .dxvk, vac: false),
        // DirectX 12 only: nothing but D3DMetal can start it, so no fallback is offered.
        Expected(slug: "phantom-blade-zero", name: "Phantom Blade Zero", appID: 4115450,
                 installDir: "PBZ", exe: "steam/PBZ.exe",
                 backend: .d3dmetal, fallback: nil, vac: false),
        // DirectX 10: DXVK translates it, D3DMetal (11 and 12 only) is the second route.
        Expected(slug: "probably-stolen", name: "Probably Stolen - Cyberpunk Shopkeeper Sim", appID: 4348910,
                 installDir: "Probably Stolen", exe: "Probably Stolen.exe",
                 backend: .dxvk, fallback: .d3dmetal, vac: false),
    ]

    @Test("Each ships as a Steam game with the right AppID, install folder and exe", arguments: TopPlayedTests.games)
    func identity(_ game: Expected) throws {
        let plan = try Self.plan(game.slug)
        #expect(plan.name == game.name)
        #expect(plan.store == .steam)
        #expect(plan.appID == game.appID, "the AppID is what Steam is told to start; a wrong one starts someone else's game")
        #expect(plan.installDir == game.installDir)
        #expect(plan.launchExe == game.exe)
        #expect(plan.installMethod == "windows-steam-in-bottle")
        #expect(plan.runnerID == "wineforge")
    }

    @Test("Each needs a running Steam client, so the launch goes through it", arguments: TopPlayedTests.games)
    func needsSteam(_ game: Expected) throws {
        let plan = try Self.plan(game.slug)
        #expect(plan.needsLiveSession)
        #expect(plan.launchContext.throughClient, "with no files on disk the launch goes through Steam")
    }

    @Test("Each starts on a backend that translates its DirectX, with a fallback only where one can work",
          arguments: TopPlayedTests.games)
    func backends(_ game: Expected) throws {
        let plan = try Self.plan(game.slug)
        #expect(plan.backend == game.backend.rawValue)
        #expect(plan.profileBackend == game.backend.rawValue)
        #expect(plan.fallbackBackend == game.fallback?.rawValue)
        #expect(BackendChoice.retry(current: plan.backend, primary: plan.profileBackend,
                                    fallback: plan.fallbackBackend) == game.fallback)
        let api = try #require(plan.facts.graphicsAPI)
        if api.contains("DirectX 9") || api.contains("DirectX 10") {
            #expect(plan.backend != GraphicsBackend.d3dmetal.rawValue,
                    "D3DMetal only translates DirectX 11 and 12; it cannot be the first route for \(api)")
        }
        if api == "DirectX 12" {
            #expect(plan.fallbackBackend == nil, "no fallback Cellar ships can start a DirectX 12 game")
        }
    }

    @Test("None claims more than has been run, or anti-cheat that is kernel-level", arguments: TopPlayedTests.games)
    func honest(_ game: Expected) throws {
        let facts = try Self.plan(game.slug).facts
        #expect(facts.status == "untested", "a top-20 game is not playable until `cellar verify` passes")
        let notes = try #require(facts.notes)
        #expect(notes.contains("Not yet launched under Cellar"))
        let anticheat = try #require(facts.anticheat)
        if anticheat.lowercased().contains("kernel") {
            #expect(anticheat.contains("not kernel-level"),
                    "kernel-level anti-cheat cannot run under Wine; such a game must not get a profile")
        }
        if game.vac {
            #expect(anticheat.hasPrefix("VAC"))
            let online = try #require(facts.online)
            #expect(online.contains("at your own risk"),
                    "Valve does not support translation layers, and the player must read that before playing online")
        }
        #expect(facts.wheel == nil, "not a racing game: no wheel row")
    }

    @Test("Denuvo is named as DRM on the one game that has it, and nowhere else", arguments: TopPlayedTests.games)
    func drm(_ game: Expected) throws {
        let drm = try #require(try Self.plan(game.slug).facts.drm)
        #expect(drm.contains("Denuvo") == (game.slug == "phantom-blade-zero"))
        #expect(drm.contains("Steamworks"))
    }

    @Test("The game's own processes are what Cellar watches, never Steam's", arguments: TopPlayedTests.games)
    func needles(_ game: Expected) throws {
        let needles = try Self.plan(game.slug).gameProcessNeedles
        #expect(needles.contains((game.exe as NSString).lastPathComponent))
        #expect(needles.contains("\\\(game.installDir)\\"))
        for needle in needles { #expect(!needle.lowercased().contains("steam.exe")) }
        // No game's folder needle may claim another top-20 game's install folder.
        for other in Self.games where other.slug != game.slug {
            #expect(!"C:\\steamapps\\common\\\(other.installDir)\\".contains("\\\(game.installDir)\\"))
        }
    }

    @Test("A copy Steam's client installed is found, down to the nested game binary", arguments: TopPlayedTests.games)
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
        #expect(!plan.canLaunchStoreFree, "the files being there does not make Steamworks go away")
    }

    @Test("The 2026 releases bring their own cover, because Steam's legacy art path has none for them")
    func coversForNewReleases() throws {
        for slug in ["phantom-blade-zero", "probably-stolen"] {
            let plan = try Self.plan(slug)
            let portrait = try #require(plan.artPortraitURL, "'\(slug)' would fall back to a generated cover")
            #expect(portrait.hasPrefix("https://shared.fastly.steamstatic.com/store_item_assets/steam/apps/\(plan.appID ?? 0)/"))
            #expect(portrait.hasSuffix("/library_capsule.jpg"))
            #expect(plan.artHeroURL?.hasSuffix("/library_hero.jpg") == true)
        }
    }

    @Test("Every game gets its own bottle")
    func separateBottles() throws {
        let bottles = try Self.games.map { try Self.plan($0.slug).bottleName }
        #expect(Set(bottles).count == bottles.count)
    }
}
