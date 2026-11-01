import CellarDomain
import Foundation
import Testing
@testable import CellarData

/// Tier A: a Steam game Cellar downloaded, entered in the bottle client's library so its DLC is
/// seen (#185) — inside a real bottle Cellar created, through the library, and out again on uninstall.
@Suite(.serialized)
struct SteamLibraryEntryIntegrationTests {

    @Test("Download → Steam's library → uninstall: the copy is entered, counted, and leaves no trace")
    func downloadedCopyLifecycle() throws {
        IT.ensure()
        let slug = IT.writeProfile("""
        [game]
        name = "Library Game"
        store = "steam"
        steam_appid = "2688950"
        [compatibility]
        needs_live_steam = true
        [install]
        install_dir = "Library Game"
        exe = "Win64/game.exe"
        """, slug: "it-library")
        let plan = try Game.plan(slug: slug)
        let bottle = try PrefixManager.create(name: plan.bottleName, backend: .d3dmetal, runner: "wineforge")
        defer { try? PrefixManager.remove(name: bottle.name) }

        // The bottle has a Steam client (just its exe — nothing here starts it).
        let steam = SteamBottle.steamDirectory(in: plan.prefix)
        try FileManager.default.createDirectory(at: steam.appendingPathComponent("steamapps/common"),
                                                withIntermediateDirectories: true)
        try Data("MZ".utf8).write(to: steam.appendingPathComponent("steam.exe"))

        // A depot download as DepotDownloader leaves it: the game, its DLC folder, depot.config.
        let win64 = plan.depotGameDir.appendingPathComponent("Win64", isDirectory: true)
        try FileManager.default.createDirectory(at: win64.appendingPathComponent("ovldata/ContentPDLC1"),
                                                withIntermediateDirectories: true)
        try Data([0x4D, 0x5A] + [UInt8](repeating: 0, count: 62)).write(to: win64.appendingPathComponent("game.exe"))
        try Data(repeating: 1, count: 4096).write(to: win64.appendingPathComponent("ovldata/ContentPDLC1/pack.ovl"))
        // 228990 (a redistributable) and 2688951 (the game) → raw-DEFLATE protobuf, as on disk.
        let proto: [UInt8] = [0x0a, 0x0b, 0x08, 0xfe, 0xfc, 0x0d, 0x10, 0x83, 0xa6, 0xc0, 0xd8, 0xd0, 0x05,
                              0x0a, 0x07, 0x08, 0xb7, 0x8f, 0xa4, 0x01, 0x10, 0x2a]
        let dd = plan.depotGameDir.appendingPathComponent(".DepotDownloader", isDirectory: true)
        try FileManager.default.createDirectory(at: dd, withIntermediateDirectories: true)
        try ((Data(proto) as NSData).compressed(using: .zlib) as Data).write(to: dd.appendingPathComponent("depot.config"))
        #expect(DepotManifests.installed(in: plan.depotGameDir)?[2_688_951] == 42)

        // Entered in the client's library: Steam (and Cellar's own checks) now see it as installed,
        // through the link, with the DLC folder in it.
        #expect(SteamLibraryEntry.register(plan, clientRunning: false) == .registered)
        #expect(SteamBottle.isGameInstalled(in: plan.prefix, appID: 2_688_950))
        let library = steam.appendingPathComponent("steamapps/common/Library Game")
        #expect(FileManager.default.fileExists(atPath: library.appendingPathComponent("Win64/ovldata/ContentPDLC1/pack.ovl").path))
        #expect(Game.isGameInstalled(plan))
        #expect(GameUpdates.managesUpdates(plan), "still Cellar's download to keep current")
        // A launch still starts the downloaded exe — the same file, whichever path finds it.
        #expect(plan.directLaunchExe?.resolvingSymlinksInPath().path
            == win64.appendingPathComponent("game.exe").resolvingSymlinksInPath().path)

        // Uninstalling the game removes files, link and manifest, and nothing else of Steam's.
        try Uninstall.perform(Uninstall.plan(for: plan, scope: .game), for: plan)
        #expect(!FileManager.default.fileExists(atPath: plan.depotGameDir.path))
        #expect(!Uninstall.isSymbolicLink(library), "no dangling link left in Steam's library")
        #expect(!FileManager.default.fileExists(atPath: steam.appendingPathComponent("steamapps/appmanifest_2688950.acf").path))
        #expect(FileManager.default.fileExists(atPath: steam.appendingPathComponent("steam.exe").path))
        #expect(!SteamBottle.isGameInstalled(in: plan.prefix, appID: 2_688_950))
    }
}
