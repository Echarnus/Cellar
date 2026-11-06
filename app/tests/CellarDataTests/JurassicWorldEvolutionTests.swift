import CellarDomain
import Foundation
import Testing
@testable import CellarData

/// The three Jurassic World Evolution games, asked for on 2026-11-05 for 0.6.5: Frontier's park
/// builders on the COBRA engine that Planet Coaster 2 and Planet Zoo run on.
///
/// The traps they carry, each pinned below: three games whose folders and exes differ by one
/// character ("Jurassic World Evolution" is the start of the other two folders, and JWE.exe of the
/// other two exes), so each must claim its own process and never a sibling's; Steam's config lists
/// Frontier's internal build variants beside the real exe, which must not be what Cellar starts;
/// the first is DirectX 11 with a fallback, the other two DirectX 12 only, so no fallback that
/// could never start them; and they share PC2's engine but must not inherit PC2's own crash
/// workaround unproven. None has been run on a Mac yet.
@Suite(.serialized)
struct JurassicWorldEvolutionTests {

    static let staged: Bool = { _ = ProfileDatabaseTests.slugs; return true }()

    static func plan(_ slug: String) throws -> GamePlan {
        _ = staged
        return try Game.plan(slug: slug)
    }

    static func fields(_ slug: String) throws -> [String: String] {
        _ = staged
        return ProfileStore.fields(try #require(ProfileStore.find(slug), "'\(slug)' is not in profiles/"))
    }

    struct Expected: Sendable, CustomTestStringConvertible {
        let slug: String
        let name: String
        let appID: Int
        let installDir: String
        let exe: String
        let api: String
        let runner: String
        let fallback: GraphicsBackend?
        /// Frontier's build variants Steam lists as other launch options (SteamDB config).
        let variants: [String]
        let macReports: String
        var testDescription: String { slug }
    }

    static let games: [Expected] = [
        Expected(slug: "jurassic-world-evolution", name: "Jurassic World Evolution", appID: 648350,
                 installDir: "Jurassic World Evolution", exe: "JWE.exe", api: "DirectX 11",
                 runner: "wineforge", fallback: .dxvk,
                 variants: ["Nero.Win64.release.exe", "Nero.Win64.profile.exe"], macReports: "runs"),
        Expected(slug: "jurassic-world-evolution-2", name: "Jurassic World Evolution 2", appID: 1244460,
                 installDir: "Jurassic World Evolution 2", exe: "JWE2.exe", api: "DirectX 12",
                 runner: "wineforge-d3dmetal4", fallback: nil,
                 variants: ["galileo.exe", "Galileo.release.exe", "JWE2.release.exe"], macReports: "runs"),
        Expected(slug: "jurassic-world-evolution-3", name: "Jurassic World Evolution 3", appID: 2958130,
                 installDir: "Jurassic World Evolution 3", exe: "JWE3.exe", api: "DirectX 12",
                 runner: "wineforge-d3dmetal4", fallback: nil,
                 variants: ["Anning.release.exe", "Anning.profile.exe"], macReports: "fails"),
    ]

    @Test("Each ships as a Steam game with the right AppID, install folder and exe", arguments: JurassicWorldEvolutionTests.games)
    func identity(_ game: Expected) throws {
        let plan = try Self.plan(game.slug)
        #expect(plan.name == game.name)
        #expect(plan.store == .steam)
        #expect(plan.appID == game.appID, "the AppID is what Steam is told to start; a wrong one starts someone else's game")
        #expect(plan.installDir == game.installDir)
        #expect(plan.launchExe == game.exe)
        #expect(plan.installMethod == "windows-steam-in-bottle")
        for variant in game.variants {
            #expect(plan.launchExe != variant, "\(variant) is a Frontier build variant, not the game")
        }
    }

    @Test("Each runs on WineForge, the runner that carries Cellar's wineserver fix for Frontier's online thread (#261)",
          arguments: JurassicWorldEvolutionTests.games)
    func runner(_ game: Expected) throws {
        let plan = try Self.plan(game.slug)
        #expect(plan.runnerID == game.runner)
        #expect(plan.runnerID.hasPrefix("wineforge"))
    }

    @Test("Each needs a running Steam client, so the launch goes through it", arguments: JurassicWorldEvolutionTests.games)
    func needsSteam(_ game: Expected) throws {
        let plan = try Self.plan(game.slug)
        #expect(plan.needsLiveSession)
        #expect(plan.launchContext.throughClient, "with no files on disk the launch goes through Steam")
        let drm = try #require(plan.facts.drm)
        #expect(drm.contains("Denuvo") && drm.contains("Steamworks"))
        #expect(plan.facts.anticheat == "none")
    }

    @Test("Each starts on D3DMetal; only the DirectX 11 one offers a fallback", arguments: JurassicWorldEvolutionTests.games)
    func backends(_ game: Expected) throws {
        let plan = try Self.plan(game.slug)
        #expect(plan.facts.graphicsAPI == game.api)
        #expect(plan.backend == GraphicsBackend.d3dmetal.rawValue)
        #expect(plan.fallbackBackend == game.fallback?.rawValue,
                "DXVK stops at DirectX 11; a DirectX 12 game offered it would be offered a route that cannot start it")
        #expect(BackendChoice.retry(current: plan.backend, primary: plan.profileBackend,
                                    fallback: plan.fallbackBackend) == game.fallback)
    }

    @Test("None claims more than has been run", arguments: JurassicWorldEvolutionTests.games)
    func honest(_ game: Expected) throws {
        let plan = try Self.plan(game.slug)
        #expect(plan.facts.status == "untested", "not playable until `cellar verify` passes")
        #expect(plan.facts.notes?.contains("Not yet launched under Cellar") == true)
        #expect(plan.onlineHosts.isEmpty, "online_hosts names hosts seen in a run, and none of these has had one")
        #expect(plan.facts.evidence.onMac == game.macReports)
        #expect(try Self.fields(game.slug)["metal_validation"] == nil,
                "PC2's validation-layer workaround costs frame rate; copy it only once a run shows this game needs it")
    }

    @Test("What the game page shows verbatim is in a player's words", arguments: JurassicWorldEvolutionTests.games)
    func plainWords(_ game: Expected) throws {
        let facts = try Self.plan(game.slug).facts
        let shown = [facts.notes, facts.online, facts.requiresAccount].compactMap { $0 }.joined(separator: " ").lowercased()
        for word in ["bottle", "runner", "wine", "prefix", "d3dmetal", "dxvk", "moltenvk", "renderer", " log ", "profile", ".ini", "avx"] {
            #expect(!shown.contains(word), "'\(game.slug)' shows '\(word)' to the player")
        }
    }

    @Test("Each claims its own game's process, never a sibling's or Planet Coaster's", arguments: JurassicWorldEvolutionTests.games)
    func needles(_ game: Expected) throws {
        let needles = try Self.plan(game.slug).gameProcessNeedles
        #expect(needles.contains(game.exe))
        for needle in needles { #expect(!needle.lowercased().contains("steam.exe")) }
        let common = "C:\\Program Files (x86)\\Steam\\steamapps\\common\\"
        let mine = "\(common)\(game.installDir)\\\(game.exe)"
        #expect(needles.contains { mine.contains($0) })
        let others = Self.games.filter { $0.slug != game.slug }.map { "\(common)\($0.installDir)\\\($0.exe)" } + [
            "\(common)Planet Coaster 2\\PlanetCoaster2.exe",
            "\(common)Planet Zoo\\PlanetZoo.exe",
        ]
        for process in others {
            #expect(!needles.contains { process.contains($0) }, "'\(game.slug)' would claim \(process)")
        }
    }

    @Test("A copy Steam's client installed is found where Steam puts it", arguments: JurassicWorldEvolutionTests.games)
    func findsClientInstalledCopy(_ game: Expected) throws {
        let plan = try Self.plan(game.slug)
        let fm = FileManager.default
        #expect(plan.directLaunchExe == nil)
        let exe = plan.prefix.appendingPathComponent(
            "drive_c/Program Files (x86)/Steam/steamapps/common/\(game.installDir)/\(game.exe)")
        try fm.createDirectory(at: exe.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("MZ".utf8).write(to: exe)
        defer { try? fm.removeItem(at: plan.prefix) }
        #expect(plan.directLaunchExe?.path == exe.path)
        #expect(!plan.canLaunchStoreFree, "the files being there does not make Denuvo's Steam check go away")
    }

    @Test("Each game gets its own bottle, apart from Frontier's other games")
    func separateBottles() throws {
        let bottles = try (Self.games.map(\.slug) + ["planet-coaster-2", "planet-zoo"]).map { try Self.plan($0).bottleName }
        #expect(Set(bottles).count == bottles.count)
    }

}
