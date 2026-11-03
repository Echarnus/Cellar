import CellarDomain
import Foundation
import Testing
@testable import CellarData

/// DARK SOULS III, pinned. It used to be a `depot` download that needed Steam running anyway — two
/// sign-ins for one game — with Elden Ring's anti-cheat in its facts and backend names in the notes
/// a player reads. It is installed and started by the bottle's Steam now, like every Steamworks game.
@Suite(.serialized)
struct DarkSouls3Tests {

    /// Staged once, by the database lint, so two suites never delete each other's copies mid-run.
    static let staged: Bool = { _ = ProfileDatabaseTests.slugs; return true }()

    static func plan() throws -> GamePlan {
        _ = staged
        return try Game.plan(slug: "dark-souls-3")
    }

    @Test("Ships as a Steam game installed by the bottle's Steam, with the exe under Game/")
    func identity() throws {
        let plan = try Self.plan()
        #expect(plan.name == "DARK SOULS III")
        #expect(plan.store == .steam)
        #expect(plan.appID == 374320)
        #expect(plan.installMethod == "windows-steam-in-bottle", "a depot download signs in a second time")
        #expect(plan.installDir == "DARK SOULS III")
        #expect(plan.launchExe == "Game/DarkSoulsIII.exe")
        #expect(plan.runnerID == "wineforge")
    }

    @Test("Needs a running Steam client, so the launch goes through it")
    func needsSteam() throws {
        let plan = try Self.plan()
        #expect(plan.needsLiveSession)
        #expect(plan.launchContext.throughClient)
    }

    @Test("Starts on D3DMetal for its DirectX 11, with DXVK as the fallback")
    func backends() throws {
        let plan = try Self.plan()
        #expect(plan.backend == GraphicsBackend.d3dmetal.rawValue)
        #expect(plan.fallbackBackend == GraphicsBackend.dxvk.rawValue)
        #expect(plan.facts.graphicsAPI == "DirectX 11")
    }

    @Test("Claims no more than has been run, and in a player's words")
    func honest() throws {
        let facts = try Self.plan().facts
        #expect(facts.status == "untested", "not playable until `cellar verify` passes")
        #expect(facts.anticheat == "none listed", "EasyAntiCheat is Elden Ring's, not this game's")
        let shown = [facts.notes, facts.online, facts.requiresAccount].compactMap { $0 }.joined(separator: " ").lowercased()
        for word in ["bottle", "runner", "wine", "prefix", "d3dmetal", "dxvk", "m5", "eac"] {
            #expect(!shown.contains(word), "the game page shows '\(word)' to the player")
        }
    }
}
