import CellarDomain
import Foundation
import Testing
@testable import CellarData

/// The shipped Elden Ring profile, pinned in detail.
///
/// The trap it carries is Easy Anti-Cheat. Steam never starts `eldenring.exe` itself: its launch
/// option is `start_protected_game.exe`, EAC's starter, which brings the anti-cheat up and then
/// starts the game. Cellar starts the game beside a running Steam, so unless the profile names that
/// starter Cellar would start the game binary directly and EAC would never run, which is changing
/// how the game protects itself. So the profile starts the starter and watches the game. It is also
/// DirectX 12 only, so it has no fallback, and it has never been run on a Mac.
@Suite(.serialized)
struct EldenRingTests {

    /// Staged once, by the database lint, so two suites never delete each other's copies mid-run.
    static let staged: Bool = { _ = ProfileDatabaseTests.slugs; return true }()

    static func plan() throws -> GamePlan {
        _ = staged
        return try Game.plan(slug: "elden-ring")
    }

    static func fields() throws -> [String: String] {
        _ = staged
        return ProfileStore.fields(try #require(ProfileStore.find("elden-ring"), "'elden-ring' is not in profiles/"))
    }

    @Test("Ships as a Steam game with the right AppID, install folder and exe")
    func identity() throws {
        let plan = try Self.plan()
        #expect(plan.name == "ELDEN RING")
        #expect(plan.store == .steam)
        #expect(plan.appID == 1245620, "the AppID is what Steam is told to start; a wrong one starts someone else's game")
        #expect(plan.installDir == "ELDEN RING")
        #expect(plan.launchExe == "Game/eldenring.exe")
        #expect(plan.installMethod == "windows-steam-in-bottle")
        #expect(plan.runnerID == "wineforge")
        #expect(plan.publisherLauncher == nil, "Bandai Namco has no launcher of its own in the way")
    }

    @Test("Steamworks means a running Steam client, so the launch goes through it")
    func needsSteam() throws {
        let plan = try Self.plan()
        #expect(plan.needsLiveSession)
        #expect(plan.launchContext.throughClient)
        #expect(!plan.canLaunchStoreFree)
    }

    @Test("DirectX 12 only: D3DMetal, and no fallback that could never start it")
    func backends() throws {
        let plan = try Self.plan()
        #expect(plan.facts.graphicsAPI == "DirectX 12")
        #expect(plan.backend == GraphicsBackend.d3dmetal.rawValue)
        #expect(plan.fallbackBackend == nil)
        #expect(BackendChoice.retry(current: plan.backend, primary: plan.profileBackend,
                                    fallback: plan.fallbackBackend) == nil)
    }

    @Test("Easy Anti-Cheat starts the way Steam starts it, and the game is what Cellar watches")
    func antiCheatStartsUntouched() throws {
        let plan = try Self.plan()
        #expect(plan.startExe == "start_protected_game.exe",
                "without it Cellar would start eldenring.exe itself and EAC would never run")
        let fm = FileManager.default
        let folder = plan.prefix.appendingPathComponent(
            "drive_c/Program Files (x86)/Steam/steamapps/common/ELDEN RING/Game", isDirectory: true)
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: plan.prefix) }
        let game = folder.appendingPathComponent("eldenring.exe")
        let starter = folder.appendingPathComponent("start_protected_game.exe")
        try Data("MZ".utf8).write(to: game)
        try Data("MZ".utf8).write(to: starter)

        #expect(plan.directLaunchExe?.path == game.path, "the game's own binary is what is found and watched")
        #expect(plan.directStartExe?.path == starter.path, "EAC's starter is what is started, as Steam does")
    }

    @Test("Both the starter and the game count as the game's processes, and nobody else's does")
    func needles() throws {
        let needles = try Self.plan().gameProcessNeedles
        let common = "C:\\Program Files (x86)\\Steam\\steamapps\\common\\"
        for own in ["ELDEN RING\\Game\\eldenring.exe", "ELDEN RING\\Game\\start_protected_game.exe"] {
            #expect(needles.contains { (common + own).contains($0) }, "'\(own)' would not be watched")
        }
        for needle in needles { #expect(!needle.lowercased().contains("steam.exe")) }
        // FromSoftware's other games in Cellar share the maker and the engine, never the process.
        for other in ["DARK SOULS III\\Game\\DarkSoulsIII.exe",
                      "DARK SOULS REMASTERED\\DarkSoulsRemastered.exe",
                      "Dark Souls II Scholar of the First Sin\\Game\\DarkSoulsII.exe"] {
            #expect(!needles.contains { (common + other).contains($0) }, "Elden Ring would claim \(other)")
        }
        let bottles = try ["dark-souls-3", "dark-souls-remastered", "dark-souls-2"].map { try Game.plan(slug: $0).bottleName }
        #expect(!bottles.contains(try Self.plan().bottleName))
    }

    @Test("Claims nothing that has not been run, and names its anti-cheat honestly")
    func honest() throws {
        let plan = try Self.plan()
        #expect(plan.facts.status == "untested", "not playable until `cellar verify` passes")
        let notes = try #require(plan.facts.notes)
        #expect(notes.contains("Not yet launched under Cellar"))
        #expect(notes.contains("Easy Anti-Cheat"), "a player has to read that online play hangs on it")
        #expect(plan.onlineHosts.isEmpty, "online_hosts names hosts seen in a run, and there has been none")
        #expect(try Self.fields()["save_paths"] == nil, "save_paths names folders seen written, and there has been none")
        let anticheat = try #require(plan.facts.anticheat)
        #expect(anticheat.contains("Easy Anti-Cheat") && anticheat.contains("online"))
        #expect(!anticheat.lowercased().contains("kernel"))
        let drm = try #require(plan.facts.drm)
        #expect(drm.contains("Steamworks") && !drm.contains("Denuvo"))
        #expect(plan.facts.wheel == nil)
    }

    @Test("What the game page shows verbatim is in a player's words")
    func plainWords() throws {
        let facts = try Self.plan().facts
        let shown = [facts.notes, facts.online, facts.requiresAccount, facts.anticheat]
            .compactMap { $0 }.joined(separator: " ").lowercased()
        // Delivery checklist P2: no bottle, runner, Wine, prefix, D3DMetal, log or profile on a player screen.
        for word in ["bottle", "runner", "wine", "prefix", "d3dmetal", "dxvk", "moltenvk", "renderer", " log ",
                     "profile", "eac", "start_protected_game", ".exe"] {
            #expect(!shown.contains(word), "the Elden Ring page shows '\(word)' to the player")
        }
    }

    @Test("The profile carries an acceptance section for the verify still to come")
    func acceptanceReady() throws {
        let text = try String(contentsOf: ProfileDatabaseTests.directory.appendingPathComponent("elden-ring.toml"),
                              encoding: .utf8)
        #expect(text.contains("[acceptance]"))
        #expect(text.contains("cellar verify elden-ring"))
    }
}
