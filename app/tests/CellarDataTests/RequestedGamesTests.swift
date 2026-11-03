import CellarDomain
import Foundation
import Testing
@testable import CellarData

/// Five Steam games asked for by name on 2026-11-01, none with a Mac version: the first two Dark
/// Souls in the editions Steam sells today, Fallout 4 and Fallout: New Vegas, and Planet Zoo.
///
/// The traps they carry, each pinned below: Steam sells neither the original Dark Souls nor (as the
/// game a player gets for the name) the original Dark Souls II, so the AppIDs must be the remaster's
/// and Scholar of the First Sin's; New Vegas is DirectX 9 and 32-bit, which D3DMetal cannot start;
/// both Fallouts start through a launcher that writes their settings files, which Skyrim crashed
/// without (#245); and Planet Zoo is Planet Coaster 2's sibling, so it must never claim PC2's
/// process or inherit PC2's own crash workaround unproven. None has been run on a Mac yet.
@Suite(.serialized)
struct RequestedGamesTests {

    /// Staged once, by the database lint, so two suites never delete each other's copies mid-run.
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
        let backend: GraphicsBackend
        let fallback: GraphicsBackend?
        var testDescription: String { slug }
    }

    static let games: [Expected] = [
        // Players on Apple Silicon report it steady through DXVK and crashing often through D3DMetal.
        Expected(slug: "dark-souls-remastered", name: "DARK SOULS: REMASTERED", appID: 570940,
                 installDir: "DARK SOULS REMASTERED", exe: "DarkSoulsRemastered.exe",
                 backend: .dxvk, fallback: .d3dmetal),
        Expected(slug: "dark-souls-2", name: "DARK SOULS II: Scholar of the First Sin", appID: 335300,
                 installDir: "Dark Souls II Scholar of the First Sin", exe: "Game/DarkSoulsII.exe",
                 backend: .d3dmetal, fallback: .dxvk),
        Expected(slug: "fallout-4", name: "Fallout 4", appID: 377160,
                 installDir: "Fallout 4", exe: "Fallout4.exe",
                 backend: .d3dmetal, fallback: .dxmt),
        // DirectX 9: D3DMetal does not translate it, so DXVK leads and WineD3D is the fallback.
        Expected(slug: "fallout-new-vegas", name: "Fallout: New Vegas", appID: 22380,
                 installDir: "Fallout New Vegas", exe: "FalloutNV.exe",
                 backend: .dxvk, fallback: .wined3d),
        Expected(slug: "planet-zoo", name: "Planet Zoo", appID: 703080,
                 installDir: "Planet Zoo", exe: "PlanetZoo.exe",
                 backend: .d3dmetal, fallback: .dxvk),
    ]

    @Test("Each ships as a Steam game with the right AppID, install folder and exe", arguments: RequestedGamesTests.games)
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

    @Test("Each needs a running Steam client, so the launch goes through it", arguments: RequestedGamesTests.games)
    func needsSteam(_ game: Expected) throws {
        let plan = try Self.plan(game.slug)
        #expect(plan.needsLiveSession)
        #expect(plan.launchContext.throughClient, "with no files on disk the launch goes through Steam")
    }

    @Test("Each starts on a backend that translates its DirectX, with a fallback that can work",
          arguments: RequestedGamesTests.games)
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
            #expect(plan.fallbackBackend != GraphicsBackend.d3dmetal.rawValue)
        }
    }

    @Test("None claims more than has been run, or an online host nobody has seen", arguments: RequestedGamesTests.games)
    func honest(_ game: Expected) throws {
        let plan = try Self.plan(game.slug)
        #expect(plan.facts.status == "untested", "not playable until `cellar verify` passes")
        let notes = try #require(plan.facts.notes)
        #expect(notes.contains("Not yet launched under Cellar"))
        #expect(plan.onlineHosts.isEmpty, "online_hosts names hosts seen in a run, and none of these has had one")
        #expect(plan.facts.wheel == nil, "not a racing game: no wheel row")
        let anticheat = try #require(plan.facts.anticheat)
        #expect(!anticheat.lowercased().contains("kernel"))
    }

    @Test("What the game page shows verbatim is in a player's words", arguments: RequestedGamesTests.games)
    func plainWords(_ game: Expected) throws {
        let facts = try Self.plan(game.slug).facts
        let shown = [facts.notes, facts.online, facts.requiresAccount].compactMap { $0 }.joined(separator: " ").lowercased()
        // Delivery checklist P2: no bottle, runner, Wine, prefix, D3DMetal, log or profile on a player screen.
        for word in ["bottle", "runner", "wine", "prefix", "d3dmetal", "dxvk", "moltenvk", "renderer", " log ", "profile", ".ini"] {
            #expect(!shown.contains(word), "'\(game.slug)' shows '\(word)' to the player")
        }
    }

    @Test("Denuvo is named as DRM on Planet Zoo, and nowhere else", arguments: RequestedGamesTests.games)
    func drm(_ game: Expected) throws {
        let drm = try #require(try Self.plan(game.slug).facts.drm)
        #expect(drm.contains("Denuvo") == (game.slug == "planet-zoo"))
        #expect(drm.contains("Steamworks"))
    }

    @Test("The game's own processes are what Cellar watches, never Steam's or a sibling's", arguments: RequestedGamesTests.games)
    func needles(_ game: Expected) throws {
        let needles = try Self.plan(game.slug).gameProcessNeedles
        #expect(needles.contains((game.exe as NSString).lastPathComponent))
        #expect(needles.contains("\\\(game.installDir)\\"))
        for needle in needles { #expect(!needle.lowercased().contains("steam.exe")) }
        // Neighbours that share a maker or an engine with one of these, and are already in Cellar.
        let neighbours = [
            "C:\\Program Files (x86)\\Steam\\steamapps\\common\\Planet Coaster 2\\PlanetCoaster2.exe",
            "C:\\Program Files (x86)\\Steam\\steamapps\\common\\DARK SOULS III\\Game\\DarkSoulsIII.exe",
            "C:\\Program Files (x86)\\Steam\\steamapps\\common\\Skyrim Special Edition\\SkyrimSE.exe",
            "C:\\Program Files (x86)\\Steam\\steamapps\\common\\Fallout Shelter\\FalloutShelter.exe",
        ]
        let others = Self.games.filter { $0.slug != game.slug }.map {
            "C:\\Program Files (x86)\\Steam\\steamapps\\common\\\($0.installDir)\\\($0.exe.replacingOccurrences(of: "/", with: "\\"))"
        }
        for process in neighbours + others {
            #expect(!needles.contains { process.contains($0) }, "'\(game.slug)' would claim \(process)")
        }
    }

    @Test("A copy Steam's client installed is found, down to the nested game binary", arguments: RequestedGamesTests.games)
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

    @Test("Dark Souls means the editions Steam sells, not the delisted originals")
    func darkSoulsEditions() throws {
        // Prepare to Die Edition (211420) left Steam in 2018; the original Dark Souls II (236430) is a
        // different, DirectX 9 program. Either AppID would start a game the player may not own.
        let one = try Self.plan("dark-souls-remastered")
        let two = try Self.plan("dark-souls-2")
        #expect(one.appID == 570940 && one.appID != 211420)
        #expect(two.appID == 335300 && two.appID != 236430)
        #expect(two.facts.notes?.contains("Scholar of the First Sin") == true,
                "a player who owns only the 2014 original must read that this is the other edition")
        let three = try Self.plan("dark-souls-3")
        #expect(Set([one.bottleName, two.bottleName, three.bottleName]).count == 3)
    }

    @Test("New Vegas is the one 32-bit game, and says so")
    func newVegasIs32Bit() throws {
        for game in Self.games {
            let architecture = try Self.fields(game.slug)["architecture"]
            #expect(architecture == (game.slug == "fallout-new-vegas" ? "x86" : "x86-64"), "'\(game.slug)'")
        }
    }

    /// `source > destination` pairs, read the way `first_run_files` is specified (`;`-separated).
    static func firstRunPairs(_ slug: String) throws -> [(source: String, destination: String)] {
        let value = try #require(try Self.fields(slug)["first_run_files"], "'\(slug)' names no first-run files")
        return value.split(separator: ";").compactMap { pair in
            let sides = pair.split(separator: ">", maxSplits: 1)
                .map { $0.trimmingCharacters(in: .whitespaces) }
            return sides.count == 2 ? (sides[0], sides[1]) : nil
        }
    }

    @Test("Both Fallouts get the settings files their launcher would write, where the game looks for them")
    func falloutFirstRunFiles() throws {
        let four = try Self.firstRunPairs("fallout-4")
        #expect(four.map(\.destination) == ["Documents/My Games/Fallout4/Fallout4.ini",
                                            "Documents/My Games/Fallout4/Fallout4Prefs.ini"])
        #expect(four.map(\.source) == ["Fallout4_Default.ini", "Fallout4/Fallout4Prefs.ini"])

        let vegas = try Self.firstRunPairs("fallout-new-vegas")
        #expect(vegas.map(\.destination) == ["Documents/My Games/FalloutNV/Fallout.ini"])
        #expect(vegas.map(\.source) == ["Fallout_default.ini"])

        for (source, destination) in four + vegas {
            #expect(!source.contains("..") && !destination.contains(".."), "a copy may not climb out of its folder")
            #expect(source.hasSuffix(".ini") && destination.hasSuffix(".ini"))
        }
        // The other three have no launcher-written files to stand in for.
        for slug in ["dark-souls-remastered", "dark-souls-2", "planet-zoo"] {
            #expect(try Self.fields(slug)["first_run_files"] == nil, "'\(slug)'")
        }
    }

    @Test("Planet Zoo is its own game: not Planet Coaster 2's bottle, and not its crash workaround unproven")
    func planetZooIsNotPlanetCoaster() throws {
        let zoo = try Self.plan("planet-zoo")
        let coaster = try Self.plan("planet-coaster-2")
        #expect(zoo.appID != coaster.appID)
        #expect(zoo.bottleName != coaster.bottleName)
        #expect(try Self.fields("planet-coaster-2")["metal_validation"] == "true")
        #expect(try Self.fields("planet-zoo")["metal_validation"] == nil,
                "PC2's validation-layer workaround costs frame rate; copy it only once a run shows Planet Zoo needs it")
        // Frontier's crash reporter is built into what `cellar verify` watches for, so the profile
        // needs no crash_processes line to have a crash in Planet Zoo's folder counted as one.
        let table = "C:\\Program Files (x86)\\Steam\\steamapps\\common\\Planet Zoo\\CrashReporter.exe -pid 42"
        #expect(zoo.crashProcesses.isEmpty)
        #expect(CrashSigns.crashReporters(inProcessList: table, extra: zoo.crashProcesses) == [table])
    }

    @Test("Every game gets its own bottle")
    func separateBottles() throws {
        let bottles = try Self.games.map { try Self.plan($0.slug).bottleName }
        #expect(Set(bottles).count == bottles.count)
    }
}
