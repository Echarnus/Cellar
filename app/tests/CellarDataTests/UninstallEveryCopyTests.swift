import CellarDomain
import Foundation
import Testing
@testable import CellarData

/// An uninstall removes every copy of the game, not only the one a launch would start (#304).
///
/// Kenneth uninstalled Fallout Shelter and the library still said "Installed". A Steam game Cellar
/// downloaded can have the bottle's Steam client's own copy beside it, and `Game.isGameInstalled`
/// finds the exe in either, so removing only the first left the game installed.
@Suite(.serialized)
struct UninstallEveryCopyTests {

    private func plan(_ slug: String) throws -> GamePlan {
        try #require(TestHome.installStubRunner() != nil)
        let plan = try TestHome.plan("""
        [game]
        name        = "Copy Fixture"
        store       = "steam"
        steam_appid = 9100001
        [compatibility]
        needs_live_session = true
        [install]
        install_dir = "Copy Fixture"
        exe         = "Bin/copy.exe"
        """, slug: slug)
        try? FileManager.default.removeItem(at: plan.prefix)
        try FileManager.default.createDirectory(at: plan.prefix, withIntermediateDirectories: true)
        return plan
    }

    private func write(_ url: URL, _ text: String = "MZ") throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    /// Cellar's depot download, plus the copy the bottle's Steam client installed itself.
    private func installBothCopies(_ plan: GamePlan) throws -> (depot: URL, steamCopy: URL, steamExe: URL) {
        let steam = SteamBottle.steamDirectory(in: plan.prefix)
        let steamExe = steam.appendingPathComponent("steam.exe")
        try write(steamExe)
        try write(plan.depotGameDir.appendingPathComponent("Bin/copy.exe"))
        let steamCopy = steam.appendingPathComponent("steamapps/common/Copy Fixture")
        try write(steamCopy.appendingPathComponent("Bin/copy.exe"))
        try write(steam.appendingPathComponent("steamapps/appmanifest_9100001.acf"), """
        "AppState"
        {
        \t"appid"\t\t"9100001"
        \t"StateFlags"\t\t"4"
        \t"installdir"\t\t"Copy Fixture"
        }
        """)
        return (plan.depotGameDir, steamCopy, steamExe)
    }

    @Test("Two copies on disk: the uninstall offers both, and afterwards the library says Not installed")
    func removesEveryCopy() throws {
        let plan = try plan("uninstall-every-copy")
        defer { try? FileManager.default.removeItem(at: plan.prefix) }
        let copies = try installBothCopies(plan)
        #expect(Game.isGameInstalled(plan))
        #expect(LoadLibrary.summary(of: plan).nextStep != .install)

        let removal = Uninstall.plan(for: plan, scope: .game)
        let gameFolders = removal.items.filter { ["Game files", "Another copy of the game files"].contains($0.label) }
        #expect(gameFolders.count == 2, "both copies are named before anything is deleted: \(removal.items.map(\.label))")

        try Uninstall.perform(removal, for: plan)
        #expect(!FileManager.default.fileExists(atPath: copies.depot.path))
        #expect(!FileManager.default.fileExists(atPath: copies.steamCopy.path))
        #expect(FileManager.default.fileExists(atPath: copies.steamExe.path), "the Steam client stays")
        #expect(!Game.isGameInstalled(plan), "an uninstalled game must not read Installed")
        #expect(LoadLibrary.summary(of: plan).nextStep == .install)
    }

    @Test("One copy, one folder: a single install is listed once, not twice by two routes")
    func singleCopyListedOnce() throws {
        let plan = try plan("uninstall-single-copy")
        defer { try? FileManager.default.removeItem(at: plan.prefix) }
        try write(plan.depotGameDir.appendingPathComponent("Bin/copy.exe"))
        let removal = Uninstall.plan(for: plan, scope: .game)
        #expect(removal.items.filter(\.isGameData).map(\.label) == ["Game files"])
        try Uninstall.perform(removal, for: plan)
        #expect(!Game.isGameInstalled(plan))
    }
}
