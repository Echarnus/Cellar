import CellarDomain
import Foundation
import Testing
@testable import CellarData

/// Hogwarts Legacy (#291), Sleeping Dogs: Definitive Edition (#292) and nine popular Windows-only
/// Steam games Cellar didn't have (#293), added on 2026-11-03, pinned in detail.
///
/// None has anti-cheat that guards starting the game, none needs a launcher Cellar can't set up,
/// and none has been run on a Mac yet. What each profile must get right is its Steam identity, the
/// backend its DirectX version allows (and no fallback for a DirectX 12-only game), and an honest
/// word about Denuvo where it has it.
@Suite(.serialized)
struct PopularGamesTests {

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
        /// DirectX 12 only: D3DMetal, and no fallback.
        let dx12Only: Bool
        let denuvo: Bool
        var testDescription: String { slug }
    }

    static let games: [Expected] = [
        Expected(slug: "hogwarts-legacy", name: "Hogwarts Legacy", appID: 990080,
                 installDir: "Hogwarts Legacy", exe: "HogwartsLegacy.exe", dx12Only: true, denuvo: true),
        Expected(slug: "sleeping-dogs-definitive-edition", name: "Sleeping Dogs: Definitive Edition", appID: 307690,
                 installDir: "SleepingDogsDefinitiveEdition", exe: "SDHDShip.exe", dx12Only: false, denuvo: false),
        Expected(slug: "sekiro-shadows-die-twice", name: "Sekiro: Shadows Die Twice", appID: 814380,
                 installDir: "Sekiro", exe: "sekiro.exe", dx12Only: false, denuvo: false),
        Expected(slug: "monster-hunter-world", name: "Monster Hunter: World", appID: 582010,
                 installDir: "Monster Hunter World", exe: "MonsterHunterWorld.exe", dx12Only: false, denuvo: false),
        Expected(slug: "monster-hunter-wilds", name: "Monster Hunter Wilds", appID: 2246340,
                 installDir: "MonsterHunterWilds", exe: "MonsterHunterWilds.exe", dx12Only: true, denuvo: true),
        Expected(slug: "god-of-war", name: "God of War", appID: 1593500,
                 installDir: "GodOfWar", exe: "GoW.exe", dx12Only: false, denuvo: false),
        Expected(slug: "black-myth-wukong", name: "Black Myth: Wukong", appID: 2358720,
                 installDir: "BlackMythWukong", exe: "b1.exe", dx12Only: true, denuvo: true),
        Expected(slug: "clair-obscur-expedition-33", name: "Clair Obscur: Expedition 33", appID: 1903340,
                 installDir: "Expedition 33", exe: "Expedition33_Steam.exe", dx12Only: true, denuvo: false),
        // DirectX 12 by default but DirectX 11 in its settings, so a fallback can help.
        Expected(slug: "satisfactory", name: "Satisfactory", appID: 526870,
                 installDir: "Satisfactory", exe: "FactoryGameSteam.exe", dx12Only: false, denuvo: false),
        Expected(slug: "lethal-company", name: "Lethal Company", appID: 1966720,
                 installDir: "Lethal Company", exe: "Lethal Company.exe", dx12Only: false, denuvo: false),
        Expected(slug: "schedule-i", name: "Schedule I", appID: 3164500,
                 installDir: "Schedule I", exe: "Schedule I.exe", dx12Only: false, denuvo: false),
    ]

    @Test("Each ships as a Steam game with the right AppID, folder and exe", arguments: PopularGamesTests.games)
    func identity(_ game: Expected) throws {
        let plan = try Self.plan(game.slug)
        #expect(plan.name == game.name)
        #expect(plan.store == .steam)
        #expect(plan.appID == game.appID, "the AppID is what Steam is told about; a wrong one is someone else's game")
        #expect(plan.installMethod == "windows-steam-in-bottle")
        #expect(plan.installDir == game.installDir)
        #expect(plan.launchExe == game.exe)
        #expect(plan.startExe == nil, "Steam starts the game's own exe, so Cellar does too")
        #expect(plan.publisherLauncher == nil)
        #expect(plan.needsLiveSession, "Steamworks: a game started with no client exits straight back")
        #expect(plan.launchContext.throughClient)
        #expect(plan.runnerID == "wineforge")
    }

    @Test("D3DMetal first, and a fallback only where the game can run on DirectX 11",
          arguments: PopularGamesTests.games)
    func backends(_ game: Expected) throws {
        let plan = try Self.plan(game.slug)
        #expect(plan.backend == GraphicsBackend.d3dmetal.rawValue)
        if game.dx12Only {
            #expect(plan.facts.graphicsAPI == "DirectX 12")
            #expect(plan.fallbackBackend == nil, "DXVK and DXMT stop at DirectX 11; a fallback could never start it")
            #expect(plan.retryBackend == nil)
        } else {
            #expect(plan.facts.graphicsAPI?.contains("DirectX 11") == true)
            #expect(plan.fallbackBackend == GraphicsBackend.dxvk.rawValue)
        }
    }

    @Test("Denuvo is named as DRM where it is there, and never as anti-cheat", arguments: PopularGamesTests.games)
    func drm(_ game: Expected) throws {
        let facts = try Self.plan(game.slug).facts
        let drm = try #require(facts.drm)
        #expect(drm.contains("Denuvo") == game.denuvo)
        #expect(!(facts.anticheat ?? "").contains("Denuvo"), "Denuvo is anti-tamper DRM, not anti-cheat")
        #expect(!(facts.anticheat ?? "").lowercased().contains("kernel"))
        // A launcher Cellar can't set up costs a game its chance (docs/COMPATIBILITY.md); none of these has one.
        for launcher in ["ea app", "ubisoft", "epic"] { #expect(!drm.lowercased().contains(launcher)) }
        if game.denuvo { #expect(facts.notes?.contains("Denuvo") == true, "the player reads why the first start goes online") }
    }

    @Test("Hogwarts Legacy says its saves may not match a PC's yet, until Steam's options are passed")
    func hogwartsSaves() throws {
        let notes = try #require(try Self.plan("hogwarts-legacy").facts.notes)
        #expect(notes.contains("Steam Cloud") && notes.contains("294"))
    }

    @Test("None claims more than has been run, and each is ready for its verify", arguments: PopularGamesTests.games)
    func honest(_ game: Expected) throws {
        let plan = try Self.plan(game.slug)
        #expect(plan.facts.status == "untested")
        #expect(plan.facts.notes?.hasPrefix("Not yet launched under Cellar") == true)
        #expect(plan.onlineHosts.isEmpty, "online_hosts names hosts seen in a run, and there has been none")
        let text = try String(contentsOf: ProfileDatabaseTests.directory.appendingPathComponent("\(game.slug).toml"),
                              encoding: .utf8)
        #expect(text.contains("[acceptance]"))
        #expect(text.contains("cellar verify \(game.slug)"))
        #expect(text.contains("evidence_checked"), "the public evidence the estimate weighs is dated")
    }

    @Test("What the game page shows verbatim is in a player's words", arguments: PopularGamesTests.games)
    func plainWords(_ game: Expected) throws {
        let facts = try Self.plan(game.slug).facts
        let shown = [facts.notes, facts.online, facts.requiresAccount, facts.anticheat, facts.drm]
            .compactMap { $0 }.joined(separator: " ").lowercased()
        for word in ["bottle", "runner", "wine", "prefix", "d3dmetal", "dxvk", "moltenvk", "renderer", " log ",
                     "profile", ".exe"] {
            #expect(!shown.contains(word), "\(game.slug)'s page shows '\(word)' to the player")
        }
    }

    @Test("No two of them claim each other's processes or share a bottle")
    func apart() throws {
        let plans = try Self.games.map { try Self.plan($0.slug) }
        #expect(Set(plans.map(\.bottleName)).count == plans.count)
        let common = "C:\\Program Files (x86)\\Steam\\steamapps\\common\\"
        for plan in plans {
            for other in plans where other.slug != plan.slug {
                let path = common + (other.installDir ?? "") + "\\" + (other.launchExe ?? "")
                #expect(!plan.gameProcessNeedles.contains { path.contains($0) },
                        "\(plan.slug) would claim \(other.slug)'s game as its own")
            }
        }
    }
}
