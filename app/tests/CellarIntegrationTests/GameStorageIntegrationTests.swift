import CellarDomain
import Foundation
import Testing
@testable import CellarData

/// Tier A: a game moved to another drive, inside a real bottle Cellar created — seen by the library,
/// counted in Storage, found at launch through the link, and removed from both places on uninstall
/// without touching the bottle or the drive.
@Suite(.serialized)
struct GameStorageIntegrationTests {

    @Test("Move, list, uninstall: a moved game behaves like any other game, end to end")
    func movedGameLifecycle() throws {
        IT.ensure()
        let slug = IT.writeProfile("""
        [game]
        name = "Moved Game"
        store = "steam"
        steam_appid = "480"
        [compatibility]
        needs_live_session = false
        [launch]
        exe = "bin/game.exe"
        """, slug: "it-moved")
        let plan = try Game.plan(slug: slug)
        let bottle = try PrefixManager.create(name: plan.bottleName, backend: .d3dmetal, runner: "wineforge")
        defer {
            GameStorage.record(slug: slug, location: nil)
            try? PrefixManager.remove(name: bottle.name)
        }

        // The game's files, as a depot download leaves them inside the bottle.
        let bin = plan.depotGameDir.appendingPathComponent("bin", isDirectory: true)
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        try Data(repeating: 1, count: 64 * 1024).write(to: bin.appendingPathComponent("game.exe"))

        let drive = IT.scratch("external-drive")
        try GameStorage.move(plan, to: drive)
        let moved = drive.appendingPathComponent("Cellar Games/\(slug)", isDirectory: true)

        // The library and Storage both know where it went.
        let summary = try #require(Game.summaries().first { $0.slug == slug })
        #expect(summary.isOnOtherDrive)
        #expect(summary.missingDrive == nil)
        let usage = try #require(GameStorage.usage().first { $0.label.hasPrefix("Moved Game") })
        #expect(usage.label.contains("(on "), "Storage says which drive it is on")
        #expect(usage.bytes > 0, "and counts the files there, not the zero-byte link")

        // A launch finds the exe through the link left in the bottle.
        #expect(plan.directLaunchExe?.resolvingSymlinksInPath().path.hasPrefix(
            moved.resolvingSymlinksInPath().path) == true)

        // Uninstalling the game takes the moved files and the link, and leaves the bottle and drive.
        try Uninstall.perform(Uninstall.plan(for: plan, scope: .game), for: plan)
        #expect(!FileManager.default.fileExists(atPath: moved.path))
        #expect(FileManager.default.fileExists(atPath: drive.path), "never the drive itself")
        #expect(FileManager.default.fileExists(atPath: bottle.url.appendingPathComponent("bottle.toml").path),
                "a game-only uninstall keeps the bottle")
    }
}
