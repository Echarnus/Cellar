import CellarDomain
import Foundation
import Testing
@testable import CellarKit

/// Games moved to another drive: still found where Cellar looks, brought back intact, and a drive
/// that isn't connected said by name.
@Suite(.serialized)
struct GameStorageTests {

    /// A downloaded Steam game, DRM-free, sitting in its bottle's `C:\Games`.
    private func installedGame() throws -> GamePlan {
        TestHome.ensure()
        let slug = TestHome.writeProfile("""
        [game]
        name = "Storage Fixture"
        store = "steam"
        steam_appid = "480"

        [compatibility]
        needs_live_session = false

        [launch]
        exe = "bin/game.exe"
        """, slug: "storage")
        let plan = try Game.plan(slug: slug)
        let bin = plan.depotGameDir.appendingPathComponent("bin", isDirectory: true)
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        try Data(repeating: 7, count: 4096).write(to: bin.appendingPathComponent("game.exe"))
        try Data("level 3".utf8).write(to: plan.depotGameDir.appendingPathComponent("data.pak"))
        return plan
    }

    @Test("A moved game is still launchable from its bottle, and comes back byte for byte")
    func moveAndBack() throws {
        let plan = try installedGame()
        let drive = TestHome.scratch("drive")
        #expect(GameStorage.movableFolder(plan) != nil)

        try GameStorage.move(plan, to: drive)
        let target = drive.appendingPathComponent("Cellar Games/\(plan.slug)")
        #expect(FileManager.default.fileExists(atPath: target.appendingPathComponent("bin/game.exe").path))
        #expect(Uninstall.isSymbolicLink(plan.depotGameDir), "the bottle keeps a link where the folder was")
        #expect(plan.directLaunchExe != nil, "the exe is found through the link")
        #expect(GameStorage.missingDrive(plan) == nil)

        try GameStorage.moveBack(plan)
        #expect(!Uninstall.isSymbolicLink(plan.depotGameDir))
        #expect(try Data(contentsOf: plan.depotGameDir.appendingPathComponent("data.pak")) == Data("level 3".utf8))
        #expect(!FileManager.default.fileExists(atPath: target.path))
        #expect(GameStorage.movedLocation(slug: plan.slug) == nil)
    }

    @Test("A disconnected drive is named, and stops a launch before it reads as not installed")
    func missingDrive() throws {
        let plan = try installedGame()
        let drive = TestHome.scratch("unplugged")
        try GameStorage.move(plan, to: drive)
        defer { GameStorage.record(slug: plan.slug, location: nil) }
        try FileManager.default.removeItem(at: drive)          // the drive is "unplugged"

        #expect(GameStorage.missingDrive(plan) != nil)
        #expect(GameStorage.missingDriveError(plan) != nil)
        #expect(throws: CellarError.self) { try Game.launch(plan) }
    }

    @Test("Uninstalling a moved game removes its files on the other drive too")
    func uninstallFollowsTheMove() throws {
        let plan = try installedGame()
        let drive = TestHome.scratch("drive")
        try GameStorage.move(plan, to: drive)
        defer { GameStorage.record(slug: plan.slug, location: nil) }
        let target = drive.appendingPathComponent("Cellar Games/\(plan.slug)")

        let removal = Uninstall.plan(for: plan, scope: .game)
        #expect(removal.items.contains { $0.url.standardizedFileURL == target.resolvingSymlinksInPath().standardizedFileURL })
        try Uninstall.perform(removal, for: plan)
        #expect(!FileManager.default.fileExists(atPath: target.path))
        #expect(FileManager.default.fileExists(atPath: drive.path), "only Cellar's folder goes, never the drive")
    }

    @Test("Cleaning up keeps the icons and empties the rest of the cache")
    func clean() throws {
        TestHome.ensure()
        let fm = FileManager.default
        try fm.createDirectory(at: Paths.cache.appendingPathComponent("icons"), withIntermediateDirectories: true)
        try fm.createDirectory(at: Paths.cache.appendingPathComponent("installers"), withIntermediateDirectories: true)
        try Data(count: 1000).write(to: Paths.cache.appendingPathComponent("installers/setup.exe"))
        GameStorage.clean()
        #expect(fm.fileExists(atPath: Paths.cache.appendingPathComponent("icons").path))
        #expect(!fm.fileExists(atPath: Paths.cache.appendingPathComponent("installers").path))
    }
}
