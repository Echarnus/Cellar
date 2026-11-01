import CellarDomain
import Foundation
import Testing
@testable import CellarData
import CellarInfrastructure

/// DLC for a game Cellar downloaded itself (#185).
///
/// Planet Coaster 2's DLC came down with the game — `Win64/ovldata/ContentPDLC1…6` arrive inside
/// depot 2688951 — yet the game showed none of it, because the bottle's Steam had no record of the
/// copy and a game asks the client whether each DLC is installed. These tests hold Cellar to
/// entering the copy in the client's library: the right folder, the depots DepotDownloader really
/// installed, the build Steam serves, and never over the client's own copy.
@Suite(.serialized)
struct SteamLibraryEntryTests {

    /// Planet Coaster 2's depots exactly as DepotDownloader recorded them on Kenneth's Mac
    /// (2026-11-01): two Steamworks redistributables and the game's one content depot.
    static let pc2Depots: [UInt32: UInt64] = [
        228_989: 5_753_583_882_400_741_046,
        228_990: 1_829_726_630_299_308_803,
        2_688_951: 9_131_339_752_266_044_125,
    ]

    // MARK: - Fixtures

    /// A downloaded Steam game in a bottle that has a Steam client, with `depot.config` on disk.
    func downloadedGame(depots: [UInt32: UInt64] = pc2Depots, client: Bool = true) throws -> GamePlan {
        let plan = try TestHome.plan("""
        [game]
        name = "Library Fixture"
        steam_appid = 2688950
        store = "steam"
        [install]
        install_dir = "Library Fixture"
        exe = "Game.exe"
        """, slug: "library-entry")
        try TestHome.installFakeGame(into: plan, at: "Game.exe")
        try writeDepotConfig(depots, into: plan.depotGameDir)
        if client {
            let steam = SteamBottle.steamDirectory(in: plan.prefix)
            try FileManager.default.createDirectory(at: steam.appendingPathComponent("steamapps"),
                                                    withIntermediateDirectories: true)
            try Data("MZ".utf8).write(to: steam.appendingPathComponent("steam.exe"))
        }
        return plan
    }

    /// `depot.config` the way DepotDownloader writes it: a protobuf map, raw DEFLATE.
    func writeDepotConfig(_ depots: [UInt32: UInt64], into game: URL) throws {
        var proto: [UInt8] = []
        func varint(_ value: UInt64) -> [UInt8] {
            var v = value, out: [UInt8] = []
            repeat {
                var byte = UInt8(v & 0x7f); v >>= 7
                if v != 0 { byte |= 0x80 }
                out.append(byte)
            } while v != 0
            return out
        }
        for (depot, manifest) in depots.sorted(by: { $0.key < $1.key }) {
            let entry = [0x08] + varint(UInt64(depot)) + [0x10] + varint(manifest)
            proto += [0x0a] + varint(UInt64(entry.count)) + entry
        }
        let compressed = try (Data(proto) as NSData).compressed(using: .zlib) as Data
        let dir = game.appendingPathComponent(".DepotDownloader")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try compressed.write(to: dir.appendingPathComponent("depot.config"))
    }

    func manifest(_ plan: GamePlan) -> String? {
        try? String(contentsOf: SteamLibraryEntry.manifestURL(steamDirectory: SteamBottle.steamDirectory(in: plan.prefix),
                                                              appID: 2_688_950), encoding: .utf8)
    }

    func libraryFolder(_ plan: GamePlan) -> URL {
        SteamBottle.steamDirectory(in: plan.prefix).appendingPathComponent("steamapps/common/Library Fixture")
    }

    // MARK: - Registering

    @Test("A downloaded copy is entered in the client's library: Steam then counts it installed")
    func registersDownloadedCopy() throws {
        let plan = try downloadedGame()
        #expect(!SteamBottle.isGameInstalled(in: plan.prefix, appID: 2_688_950))

        #expect(SteamLibraryEntry.register(plan, clientRunning: false) == .registered)

        // The same check every launch route and the library use.
        #expect(SteamBottle.isGameInstalled(in: plan.prefix, appID: 2_688_950))
        #expect(SteamBottle.installDirectory(in: plan.prefix, appID: 2_688_950) == "Library Fixture")
        #expect(SteamLibraryEntry.isLink(libraryFolder(plan), to: plan.depotGameDir))
        #expect(SteamLibraryEntry.isCellarEntry(plan))
        // The link points at the download: nothing was copied or moved.
        #expect(FileManager.default.fileExists(atPath: libraryFolder(plan).appendingPathComponent("Game.exe").path))
    }

    @Test("The manifest names the game's depots as installed and the redistributables as shared")
    func manifestContents() throws {
        let plan = try downloadedGame()
        SteamLibraryEntry.register(plan, clientRunning: false)
        let state = try #require(manifest(plan).flatMap { TextVDF.parse($0)?.block("AppState") })

        #expect(state.string("appid") == "2688950")
        #expect(state.string("StateFlags") == "4")
        #expect(state.string("installdir") == "Library Fixture")
        // Steam only updates it when Steam starts it; Cellar starts it and keeps it current.
        #expect(state.string("AutoUpdateBehavior") == "1")
        let installed = try #require(state.block("InstalledDepots"))
        #expect(installed.entries.map(\.key) == ["2688951"])
        #expect(installed.block("2688951")?.string("manifest") == "9131339752266044125")
        let shared = try #require(state.block("SharedDepots"))
        #expect(shared.string("228989") == "228980")
        #expect(shared.string("228990") == "228980")
    }

    @Test("The build id comes from Steam's own app-info cache, so Steam doesn't 'update' the copy")
    func buildIDFromAppInfo() throws {
        let plan = try downloadedGame()
        let cache = SteamAppInfo.cacheFile(steamDirectory: SteamBottle.steamDirectory(in: plan.prefix))
        try FileManager.default.createDirectory(at: cache.deletingLastPathComponent(), withIntermediateDirectories: true)
        try AppInfoFixture.v29(apps: [(2_688_950, "20871234")]).write(to: cache)

        SteamLibraryEntry.register(plan, clientRunning: false)
        let state = try #require(manifest(plan).flatMap { TextVDF.parse($0)?.block("AppState") })
        #expect(state.string("buildid") == "20871234")
        #expect(state.string("TargetBuildID") == "20871234")
    }

    @Test("Registering again with nothing changed leaves the file alone")
    func idempotent() throws {
        let plan = try downloadedGame()
        #expect(SteamLibraryEntry.register(plan, clientRunning: false, now: Date(timeIntervalSince1970: 1)) == .registered)
        let first = manifest(plan)
        #expect(SteamLibraryEntry.register(plan, clientRunning: false, now: Date(timeIntervalSince1970: 2)) == .unchanged)
        #expect(manifest(plan) == first)
    }

    @Test("After an update the manifest follows the new depots")
    func followsUpdates() throws {
        let plan = try downloadedGame()
        SteamLibraryEntry.register(plan, clientRunning: false)
        var patched = Self.pc2Depots
        patched[2_688_951] = 42
        try writeDepotConfig(patched, into: plan.depotGameDir)

        #expect(SteamLibraryEntry.register(plan, clientRunning: false) == .registered)
        let state = try #require(manifest(plan).flatMap { TextVDF.parse($0)?.block("AppState") })
        #expect(state.block("InstalledDepots")?.block("2688951")?.string("manifest") == "42")
    }

    @Test("A copy Cellar entered in Steam's library is still Cellar's to update")
    func updatesStayCellars() throws {
        let plan = try downloadedGame()
        #expect(GameUpdates.managesUpdates(plan))
        SteamLibraryEntry.register(plan, clientRunning: false)
        #expect(GameUpdates.managesUpdates(plan))
    }

    @Test("Cellar's entry keeps Cellar's launch route: started beside the client, never via rungameid")
    func keepsCellarsLaunchRoute() throws {
        // Found on Kenneth's Mac: with the entry in place the launch took Steam's own route, waited
        // for a client that never came up, and Planet Coaster 2 didn't start.
        let plan = try downloadedGame()
        SteamLibraryEntry.register(plan, clientRunning: false)
        #expect(SteamBottle.isGameInstalled(in: plan.prefix, appID: 2_688_950))
        #expect(!SteamAdapter.isClientCopy(plan, appID: 2_688_950))
        #expect(SteamAdapter.startsGameItself(clientCopy: SteamAdapter.isClientCopy(plan, appID: 2_688_950),
                                              forceStore: true, gameAppAvailable: false))
    }

    @Test("The client's own install is still the client's copy")
    func clientsOwnCopyIsClientCopy() throws {
        let plan = try downloadedGame()
        let steam = SteamBottle.steamDirectory(in: plan.prefix)
        let own = libraryFolder(plan)
        try FileManager.default.createDirectory(at: own, withIntermediateDirectories: true)
        try Data("MZ".utf8).write(to: own.appendingPathComponent("Game.exe"))
        try "\"AppState\"\n{\n\t\"StateFlags\"\t\t\"4\"\n\t\"installdir\"\t\t\"Library Fixture\"\n}\n"
            .write(to: SteamLibraryEntry.manifestURL(steamDirectory: steam, appID: 2_688_950), atomically: true, encoding: .utf8)
        #expect(SteamAdapter.isClientCopy(plan, appID: 2_688_950))
        #expect(!GameUpdates.managesUpdates(plan), "Steam keeps its own copy current")
    }

    // MARK: - When it must not

    @Test("The client's own copy is never overwritten or relinked")
    func leavesSteamsOwnCopy() throws {
        let plan = try downloadedGame()
        let own = libraryFolder(plan)
        try FileManager.default.createDirectory(at: own, withIntermediateDirectories: true)
        try Data("MZ".utf8).write(to: own.appendingPathComponent("Game.exe"))

        guard case .skipped = SteamLibraryEntry.register(plan, clientRunning: false) else {
            Issue.record("registered over Steam's own copy"); return
        }
        #expect(!SteamLibraryEntry.isLink(own, to: plan.depotGameDir))
        #expect(manifest(plan) == nil)
        #expect(!SteamLibraryEntry.isCellarEntry(plan))
    }

    @Test("An empty folder Steam left behind is replaced by the link")
    func replacesEmptyFolder() throws {
        let plan = try downloadedGame()
        try FileManager.default.createDirectory(at: libraryFolder(plan), withIntermediateDirectories: true)
        #expect(SteamLibraryEntry.register(plan, clientRunning: false) == .registered)
        #expect(SteamLibraryEntry.isLink(libraryFolder(plan), to: plan.depotGameDir))
    }

    @Test("Nothing is written while the client runs — it reads its library only at start-up")
    func notWhileRunning() throws {
        let plan = try downloadedGame()
        guard case .skipped = SteamLibraryEntry.register(plan, clientRunning: true) else {
            Issue.record("wrote under a running client"); return
        }
        #expect(manifest(plan) == nil)
    }

    @Test("No client in the bottle, or no Cellar download: nothing to enter")
    func needsClientAndDownload() throws {
        let noClient = try downloadedGame(client: false)
        guard case .skipped = SteamLibraryEntry.register(noClient, clientRunning: false) else {
            Issue.record("registered without a client"); return
        }

        let notDownloaded = try downloadedGame()
        try FileManager.default.removeItem(at: notDownloaded.depotGameDir.appendingPathComponent(".DepotDownloader"))
        guard case .skipped = SteamLibraryEntry.register(notDownloaded, clientRunning: false) else {
            Issue.record("registered a copy Cellar didn't download"); return
        }
    }

    // MARK: - Uninstalling

    @Test("Uninstalling removes the link and the manifest along with the files")
    func uninstallRemovesEntry() throws {
        let plan = try downloadedGame()
        SteamLibraryEntry.register(plan, clientRunning: false)
        let items = Uninstall.gameFileItems(plan)
        #expect(items.contains { $0.label == "Steam library link" && $0.url.path == libraryFolder(plan).path })
        #expect(items.contains { $0.label == "Steam manifest" })
        // Counted as a link, not as the 37 GB it points at.
        #expect(items.first { $0.label == "Steam library link" }?.bytes == 0)
    }

    // MARK: - Steam's app-info cache

    @Test("appinfo.vdf v29: the public build id is read through the string table")
    func appInfoV29() {
        let data = AppInfoFixture.v29(apps: [(10, "111"), (2_688_950, "20871234"), (20, "222")])
        #expect(SteamAppInfo.buildID(appID: 2_688_950, in: data) == 20_871_234)
        #expect(SteamAppInfo.buildID(appID: 10, in: data) == 111)
        #expect(SteamAppInfo.buildID(appID: 99, in: data) == nil)
    }

    @Test("appinfo.vdf v28: keys spelled inline")
    func appInfoV28() {
        let data = AppInfoFixture.v28(apps: [(2_688_950, "555")])
        #expect(SteamAppInfo.buildID(appID: 2_688_950, in: data) == 555)
    }

    @Test("A cache that doesn't parse is nil, never a guess")
    func appInfoGarbage() {
        #expect(SteamAppInfo.buildID(appID: 1, in: Data([0xde, 0xad, 0xbe, 0xef])) == nil)
        var truncated = AppInfoFixture.v29(apps: [(2_688_950, "1")])
        truncated.removeLast(40)
        #expect(SteamAppInfo.buildID(appID: 2_688_950, in: truncated) == nil)
    }
}

/// Builds `appinfo.vdf` bytes in the client's own layout.
enum AppInfoFixture {
    static func le32(_ v: UInt32) -> [UInt8] { (0..<4).map { UInt8((v >> (8 * $0)) & 0xff) } }
    static func le64(_ v: UInt64) -> [UInt8] { (0..<8).map { UInt8((v >> (8 * UInt64($0))) & 0xff) } }
    static func cstr(_ s: String) -> [UInt8] { Array(s.utf8) + [0] }

    /// appinfo → { common { name }, depots { branches { public { buildid } } } }
    static func kv(buildID: String, key: (String) -> [UInt8]) -> [UInt8] {
        var b: [UInt8] = []
        b += [0x00] + key("appinfo")
        b += [0x00] + key("common") + [0x01] + key("name") + cstr("Fixture") + [0x02] + key("type") + le32(1) + [0x08]
        b += [0x00] + key("depots")
        b += [0x00] + key("branches") + [0x00] + key("public")
        b += [0x01] + key("buildid") + cstr(buildID) + [0x07] + key("timeupdated") + le64(1_700_000_000)
        b += [0x08, 0x08, 0x08, 0x08, 0x08]
        return b
    }

    static func entry(appID: UInt32, kv: [UInt8]) -> [UInt8] {
        let header = le32(2) + le32(0) + le64(0) + [UInt8](repeating: 0, count: 20) + le32(0)
            + [UInt8](repeating: 0, count: 20)
        let body = header + kv
        return le32(appID) + le32(UInt32(body.count)) + body
    }

    static func v28(apps: [(UInt32, String)]) -> Data {
        var b = le32(SteamAppInfo.magic28) + le32(1)
        for (id, build) in apps { b += entry(appID: id, kv: kv(buildID: build, key: cstr)) }
        b += le32(0)
        return Data(b)
    }

    static func v29(apps: [(UInt32, String)]) -> Data {
        let table = ["appinfo", "common", "name", "type", "depots", "branches", "public", "buildid", "timeupdated"]
        let key: (String) -> [UInt8] = { le32(UInt32(table.firstIndex(of: $0)!)) }
        var body: [UInt8] = []
        for (id, build) in apps { body += entry(appID: id, kv: kv(buildID: build, key: key)) }
        body += le32(0)
        let headerSize = 4 + 4 + 8
        let offset = UInt64(headerSize + body.count)
        var b = le32(SteamAppInfo.magic29) + le32(1) + le64(offset) + body
        b += le32(UInt32(table.count))
        for s in table { b += cstr(s) }
        return Data(b)
    }
}
