import CellarDomain
import Foundation
import Testing
@testable import CellarData

/// The shipped Kingdom Come profiles, Deliverance and Deliverance II, pinned in detail.
///
/// Both are Steam games with nothing but Steamworks on them — no Denuvo, no anti-cheat — so Cellar
/// keeps Steam running beside them and leaves the game's files untouched. Where they differ is the
/// renderer: the first is DirectX 11, which two of Cellar's backends translate, and the second is
/// DirectX 12, which only D3DMetal does. Neither has been run on a Mac yet, and both say so.
@Suite(.serialized)
struct KingdomComeTests {

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
        let fallback: GraphicsBackend?
        var testDescription: String { slug }
    }

    static let games: [Expected] = [
        Expected(slug: "kingdom-come-deliverance", name: "Kingdom Come: Deliverance", appID: 379430,
                 installDir: "KingdomComeDeliverance", exe: "Bin/Win64/KingdomCome.exe",
                 fallback: .dxvk),
        // DirectX 12 only: no backend but D3DMetal can start it, so none is offered as a fallback.
        Expected(slug: "kingdom-come-deliverance-2", name: "Kingdom Come: Deliverance II", appID: 1771300,
                 installDir: "KingdomComeDeliverance2", exe: "Bin/Win64MasterMasterSteamPGO/KingdomCome.exe",
                 fallback: nil),
    ]

    @Test("Each ships as a Steam game with the right AppID, install folder and exe", arguments: KingdomComeTests.games)
    func identity(_ game: Expected) throws {
        let plan = try Self.plan(game.slug)
        #expect(plan.name == game.name)
        #expect(plan.store == .steam)
        #expect(plan.appID == game.appID, "the AppID is what Steam is told to start; a wrong one starts someone else's game")
        #expect(plan.installDir == game.installDir)
        #expect(plan.launchExe == game.exe)
        #expect(plan.installMethod == "windows-steam-in-bottle")
    }

    @Test("Steamworks means both need a running Steam client", arguments: KingdomComeTests.games)
    func needsSteam(_ game: Expected) throws {
        let plan = try Self.plan(game.slug)
        #expect(plan.needsLiveSession)
        #expect(plan.launchContext.throughClient, "with no files on disk the launch goes through Steam")
    }

    @Test("Both start on D3DMetal; only the DirectX 11 game has a second route", arguments: KingdomComeTests.games)
    func backends(_ game: Expected) throws {
        let plan = try Self.plan(game.slug)
        #expect(plan.backend == GraphicsBackend.d3dmetal.rawValue)
        #expect(plan.profileBackend == GraphicsBackend.d3dmetal.rawValue)
        #expect(plan.fallbackBackend == game.fallback?.rawValue)
        #expect(plan.runnerID == "wineforge")
        // What the launch window offers when the game never comes up: DXVK for the first game,
        // nothing for the second — a DX11 translator offered for a DX12 game would only fail again.
        #expect(BackendChoice.retry(current: plan.backend, primary: plan.profileBackend,
                                    fallback: plan.fallbackBackend) == game.fallback)
    }

    @Test("Neither claims more than has been run, nor DRM or anti-cheat it does not have", arguments: KingdomComeTests.games)
    func honest(_ game: Expected) throws {
        let facts = try Self.plan(game.slug).facts
        #expect(facts.status == "untested")
        let notes = try #require(facts.notes)
        #expect(notes.contains("Not yet launched under Cellar"))
        #expect(facts.anticheat?.hasPrefix("none") == true)
        let drm = try #require(facts.drm)
        #expect(drm.hasPrefix("Steamworks"))
        #expect(!drm.lowercased().contains("denuvo") || drm.lowercased().contains("no denuvo"),
                "neither game carries Denuvo, and the profile must not say it does")
        #expect(facts.wheel == nil, "not a racing game: no wheel row")
    }

    @Test("The game's own processes are what Cellar watches, never Steam's", arguments: KingdomComeTests.games)
    func needles(_ game: Expected) throws {
        let needles = try Self.plan(game.slug).gameProcessNeedles
        #expect(needles.contains("KingdomCome.exe"))
        // Both games' binaries are called KingdomCome.exe, so the exe needle alone matches either;
        // the install folder needle is the one that names this game.
        #expect(needles.contains("\\\(game.installDir)\\"))
        let other = try #require(Self.games.first { $0.slug != game.slug })
        #expect(!"C:\\steamapps\\common\\\(other.installDir)\\".contains("\\\(game.installDir)\\"),
                "one game's folder needle must not match the other's install folder")
        for needle in needles { #expect(!needle.lowercased().contains("steam")) }
    }

    @Test("A copy Steam's client installed is found, down to the nested game binary", arguments: KingdomComeTests.games)
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

    @Test("The two games get two bottles, so their saves and Wine settings never mix")
    func separateBottles() throws {
        let first = try Self.plan("kingdom-come-deliverance")
        let second = try Self.plan("kingdom-come-deliverance-2")
        #expect(first.bottleName != second.bottleName)
        #expect(first.prefix != second.prefix)
    }
}
