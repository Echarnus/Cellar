import CellarDomain
import Foundation
import Testing
@testable import CellarData

/// Every Grand Theft Auto game on Steam besides GTA V (which `RedDeadTests` and `TopPlayedTests`
/// pin), added on 2026-11-03 (#290), pinned in detail.
///
/// Three kinds, and each has its own trap:
/// - **GTA IV** starts through Rockstar's launcher from a stub beside the game, like the Red Deads.
/// - **The Definitive Editions** start through it too, but Steam's stub sits at the top of the
///   folder while the game runs from `Gameface/Binaries/Win64`, so `start_exe` has to be found at
///   the install root, not only beside the game.
/// - **The originals** are no longer sold, only downloadable by people who own them, and are DirectX
///   8 and 9, which D3DMetal never translates.
@Suite(.serialized)
struct GrandTheftAutoTests {

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
        let startExe: String?
        let backend: GraphicsBackend
        let fallback: GraphicsBackend?
        var rockstar: Bool { startExe != nil }
        var testDescription: String { slug }
    }

    static let games: [Expected] = [
        // DirectX 9: DXVK leads, WineD3D is the fallback. The stub sits beside the game.
        Expected(slug: "grand-theft-auto-iv", name: "Grand Theft Auto IV: The Complete Edition", appID: 12210,
                 installDir: "Grand Theft Auto IV", exe: "GTAIV/GTAIV.exe", startExe: "PlayGTAIV.exe",
                 backend: .dxvk, fallback: .wined3d),
        Expected(slug: "grand-theft-auto-iii-definitive-edition",
                 name: "Grand Theft Auto III – The Definitive Edition", appID: 1546970,
                 installDir: "GTA III - The Definitive Edition", exe: "Gameface/Binaries/Win64/LibertyCity.exe",
                 startExe: "PlayGTA3.exe", backend: .d3dmetal, fallback: .dxvk),
        Expected(slug: "grand-theft-auto-vice-city-definitive-edition",
                 name: "Grand Theft Auto: Vice City – The Definitive Edition", appID: 1546990,
                 installDir: "GTA Vice City - The Definitive Edition", exe: "Gameface/Binaries/Win64/ViceCity.exe",
                 startExe: "PlayGTAViceCity.exe", backend: .d3dmetal, fallback: .dxvk),
        Expected(slug: "grand-theft-auto-san-andreas-definitive-edition",
                 name: "Grand Theft Auto: San Andreas – The Definitive Edition", appID: 1547000,
                 installDir: "GTA San Andreas - The Definitive Edition", exe: "Gameface/Binaries/Win64/SanAndreas.exe",
                 startExe: "PlayGTASanAndreas.exe", backend: .d3dmetal, fallback: .dxvk),
        // DirectX 8: only Wine's own renderer draws it, so there is no fallback to offer.
        Expected(slug: "grand-theft-auto-iii", name: "Grand Theft Auto III", appID: 12100,
                 installDir: "Grand Theft Auto 3", exe: "gta3.exe", startExe: nil,
                 backend: .wined3d, fallback: nil),
        Expected(slug: "grand-theft-auto-vice-city", name: "Grand Theft Auto: Vice City", appID: 12110,
                 installDir: "Grand Theft Auto Vice City", exe: "gta-vc.exe", startExe: nil,
                 backend: .wined3d, fallback: nil),
        Expected(slug: "grand-theft-auto-san-andreas", name: "Grand Theft Auto: San Andreas", appID: 12120,
                 installDir: "Grand Theft Auto San Andreas", exe: "gta-sa.exe", startExe: nil,
                 backend: .dxvk, fallback: .wined3d),
    ]

    @Test("Each ships as a Steam game with the right AppID, folder and exe", arguments: GrandTheftAutoTests.games)
    func identity(_ game: Expected) throws {
        let plan = try Self.plan(game.slug)
        #expect(plan.name == game.name)
        #expect(plan.store == .steam, "bought and downloaded through Steam: Rockstar's launcher is not a store")
        #expect(plan.appID == game.appID, "the AppID is what Steam is told about; a wrong one is someone else's game")
        #expect(plan.installMethod == "windows-steam-in-bottle")
        #expect(plan.installDir == game.installDir)
        #expect(plan.launchExe == game.exe, "the game itself is what Cellar watches")
        #expect(plan.startExe == game.startExe)
        #expect(plan.gameProcessNeedles.first == (game.exe as NSString).lastPathComponent)
        #expect(plan.needsLiveSession, "Steam's copy wants its client running")
        #expect(plan.runnerID == "wineforge")
    }

    @Test("Steam's Rockstar copies start through Rockstar's launcher, and the originals don't",
          arguments: GrandTheftAutoTests.games)
    func launcher(_ game: Expected) throws {
        let plan = try Self.plan(game.slug)
        if game.rockstar {
            #expect(plan.publisherLauncher == .rockstar)
            #expect(plan.facts.requiresAccount == "Steam + Rockstar Games account",
                    "the second account is shown before the player installs, not discovered at Play")
            #expect(plan.facts.notes?.contains("Rockstar Games Launcher") == true)
        } else {
            #expect(plan.publisherLauncher == nil, "the pre-2019 Steam copies never had Rockstar's launcher")
            #expect(plan.facts.requiresAccount == "Steam")
            #expect(plan.facts.notes?.contains("No longer sold on Steam") == true,
                    "a player must read that this is only for copies already owned")
        }
    }

    @Test("Each picks the backend its DirectX version allows, and never a fallback that can't start it",
          arguments: GrandTheftAutoTests.games)
    func backends(_ game: Expected) throws {
        let plan = try Self.plan(game.slug)
        #expect(plan.backend == game.backend.rawValue)
        #expect(plan.fallbackBackend == game.fallback?.rawValue)
        if plan.facts.graphicsAPI == "DirectX 8" {
            #expect(plan.backend == GraphicsBackend.wined3d.rawValue,
                    "neither D3DMetal nor DXVK translates DirectX 8")
        }
        if plan.facts.graphicsAPI == "DirectX 9" {
            #expect(plan.backend != GraphicsBackend.d3dmetal.rawValue, "D3DMetal does 11 and 12 only")
        }
    }

    @Test("A Definitive Edition starts Steam's stub at the top of its folder and watches the game deep inside",
          arguments: GrandTheftAutoTests.games.filter { $0.exe.hasPrefix("Gameface/") })
    func definitiveEditionStartsTheStub(_ game: Expected) throws {
        let plan = try Self.plan(game.slug)
        let fm = FileManager.default
        let root = plan.prefix.appendingPathComponent(
            "drive_c/Program Files (x86)/Steam/steamapps/common/\(game.installDir)", isDirectory: true)
        let exe = root.appendingPathComponent(game.exe)
        try fm.createDirectory(at: exe.deletingLastPathComponent(), withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: plan.prefix) }
        try Data("MZ".utf8).write(to: exe)
        // Only the game on disk: nothing else is started, or the launch fails in Wine.
        #expect(plan.directStartExe?.path == exe.path)

        let stub = root.appendingPathComponent(try #require(game.startExe))
        try Data("MZ".utf8).write(to: stub)
        #expect(plan.directLaunchExe?.path == exe.path, "what is watched stays the game itself")
        #expect(plan.directStartExe?.path == stub.path, "Steam's stub is what is started, as Steam does")
    }

    @Test("GTA IV's stub is found beside the game, in its GTAIV folder")
    func gtaIVStartsBesideTheGame() throws {
        let plan = try Self.plan("grand-theft-auto-iv")
        let fm = FileManager.default
        let folder = plan.prefix.appendingPathComponent(
            "drive_c/Program Files (x86)/Steam/steamapps/common/Grand Theft Auto IV/GTAIV", isDirectory: true)
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: plan.prefix) }
        try Data("MZ".utf8).write(to: folder.appendingPathComponent("GTAIV.exe"))
        try Data("MZ".utf8).write(to: folder.appendingPathComponent("PlayGTAIV.exe"))
        #expect(plan.directStartExe?.lastPathComponent == "PlayGTAIV.exe")
        #expect(plan.directLaunchExe?.lastPathComponent == "GTAIV.exe")
    }

    @Test("No two GTA games claim each other's processes or share a bottle")
    func apart() throws {
        let all = Self.games.map(\.slug) + ["grand-theft-auto-v", "grand-theft-auto-v-enhanced"]
        let plans = try all.map { try Self.plan($0) }
        #expect(Set(plans.map(\.bottleName)).count == plans.count)
        let common = "C:\\Program Files (x86)\\Steam\\steamapps\\common\\"
        for plan in plans {
            for other in plans where other.slug != plan.slug {
                let path = common + (other.installDir ?? "") + "\\" + (other.launchExe ?? "")
                    .replacingOccurrences(of: "/", with: "\\")
                #expect(!plan.gameProcessNeedles.contains { path.contains($0) },
                        "\(plan.slug) would claim \(other.slug)'s game as its own")
            }
        }
    }

    @Test("None claims more than has been run, and each is ready for its verify",
          arguments: GrandTheftAutoTests.games)
    func honest(_ game: Expected) throws {
        let plan = try Self.plan(game.slug)
        #expect(plan.facts.status == "untested")
        #expect(plan.facts.notes?.hasPrefix("Not yet launched under Cellar") == true)
        #expect(plan.onlineHosts.isEmpty, "online_hosts names hosts seen in a run, and there has been none")
        #expect(plan.facts.anticheat?.hasPrefix("none") == true, "single-player: nothing guards it")
        let text = try String(contentsOf: ProfileDatabaseTests.directory.appendingPathComponent("\(game.slug).toml"),
                              encoding: .utf8)
        #expect(text.contains("[acceptance]"))
        #expect(text.contains("cellar verify \(game.slug)"))
    }

    @Test("What the game page shows verbatim is in a player's words", arguments: GrandTheftAutoTests.games)
    func plainWords(_ game: Expected) throws {
        let facts = try Self.plan(game.slug).facts
        let shown = [facts.notes, facts.online, facts.requiresAccount, facts.anticheat, facts.drm]
            .compactMap { $0 }.joined(separator: " ").lowercased()
        // Delivery checklist P2: no bottle, runner, Wine, prefix, D3DMetal, log or profile on a player screen.
        for word in ["bottle", "runner", "wine", "prefix", "d3dmetal", "dxvk", "moltenvk", "renderer", " log ",
                     "profile", ".exe"] {
            #expect(!shown.contains(word), "\(game.slug)'s page shows '\(word)' to the player")
        }
    }
}
