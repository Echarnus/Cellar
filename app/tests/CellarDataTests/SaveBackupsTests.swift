import CellarDomain
import Foundation
import Testing
@testable import CellarData

/// Save games copied out of a bottle before anything that could lose them, and put back intact.
@Suite(.serialized)
struct SaveBackupsTests {

    /// A bottle under the test home with one save folder in Saved Games and one cache in AppData.
    private func bottle(_ name: String = "saves-\(UUID().uuidString.prefix(8))".lowercased()) throws -> URL {
        TestHome.ensure()
        let bottle = Paths.prefixes.appendingPathComponent(name, isDirectory: true)
        let user = bottle.appendingPathComponent("drive_c/users/steamuser", isDirectory: true)
        let save = user.appendingPathComponent("Saved Games/Fixture", isDirectory: true)
        try FileManager.default.createDirectory(at: save.appendingPathComponent("slot1"), withIntermediateDirectories: true)
        try Data((0..<4096).map { UInt8(truncatingIfNeeded: $0 &* 31) }).write(to: save.appendingPathComponent("slot1/game.sav"))
        try Data("settings".utf8).write(to: save.appendingPathComponent("options.ini"))
        let cache = user.appendingPathComponent("AppData/Local/Temp", isDirectory: true)
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        try Data("not a save".utf8).write(to: cache.appendingPathComponent("junk.tmp"))
        return bottle
    }

    private func saveFile(_ bottle: URL, _ path: String = "slot1/game.sav") -> URL {
        bottle.appendingPathComponent("drive_c/users/steamuser/Saved Games/Fixture/\(path)")
    }

    @Test("A restore puts back byte-identical files, and keeps the saves it replaced")
    func roundTrip() throws {
        let bottle = try bottle()
        let original = try Data(contentsOf: saveFile(bottle))
        let backup = try #require(try SaveBackups.backUp(bottle: bottle, reason: .manual))
        #expect(backup.manifest.paths == ["steamuser/Saved Games/Fixture"])
        #expect(!backup.manifest.paths.contains { $0.contains("Temp") }, "caches are not saves")

        try Data("overwritten".utf8).write(to: saveFile(bottle))
        try FileManager.default.removeItem(at: saveFile(bottle, "options.ini"))
        try SaveBackups.restore(backup, into: bottle)

        #expect(try Data(contentsOf: saveFile(bottle)) == original)
        #expect(try Data(contentsOf: saveFile(bottle, "options.ini")) == Data("settings".utf8))

        let all = SaveBackups.list(bottle: bottle.lastPathComponent)
        #expect(all.count == 2)
        #expect(all.contains { $0.manifest.reason == .beforeRestore }, "the replaced saves were kept first")
    }

    @Test("A bottle with no saves gives no backup, rather than an empty one")
    func nothingToCopy() throws {
        TestHome.ensure()
        let empty = Paths.prefixes.appendingPathComponent("empty-\(UUID().uuidString.prefix(8))".lowercased())
        try FileManager.default.createDirectory(at: empty.appendingPathComponent("drive_c/users/steamuser"),
                                                withIntermediateDirectories: true)
        #expect(try SaveBackups.backUp(bottle: empty, reason: .manual) == nil)
        #expect(SaveBackups.list(bottle: empty.lastPathComponent).isEmpty)
    }

    @Test("Only the newest backups are kept, newest first")
    func retention() throws {
        let bottle = try bottle()
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        for i in 0..<(SaveBackups.keep + 3) {
            try SaveBackups.backUp(bottle: bottle, reason: .manual, now: start.addingTimeInterval(Double(i) * 60))
        }
        let all = SaveBackups.list(bottle: bottle.lastPathComponent)
        #expect(all.count == SaveBackups.keep)
        #expect(all.first?.manifest.created == start.addingTimeInterval(Double(SaveBackups.keep + 2) * 60))
    }

    @Test("A profile's save_paths narrow the copy, and links to the Mac's folders are never followed")
    func declaredPaths() throws {
        let bottle = try bottle()
        let user = bottle.appendingPathComponent("drive_c/users/steamuser")
        let declared = SaveBackups.parse(#"Saved Games\Fixture\slot1; Documents/Linked/X ; ../escape"#)
        #expect(declared == ["Saved Games/Fixture/slot1", "Documents/Linked/X"])

        let outside = TestHome.scratch("mac-documents")
        try FileManager.default.createDirectory(at: outside.appendingPathComponent("X"), withIntermediateDirectories: true)
        try Data("mac".utf8).write(to: outside.appendingPathComponent("X/file"))
        try FileManager.default.createDirectory(at: user.appendingPathComponent("Documents"), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: user.appendingPathComponent("Documents/Linked"),
                                                   withDestinationURL: outside)

        let found = SaveBackups.locations(inBottle: bottle, declared: declared)
        #expect(found.map(\.relativePath) == ["steamuser/Saved Games/Fixture/slot1"])
    }

    @Test("Removing a bottle backs its saves up first")
    func removalBacksUp() throws {
        let name = "remove-\(UUID().uuidString.prefix(8))".lowercased()
        let slug = TestHome.writeProfile("""
        [game]
        name = "Removal Fixture"
        store = "gog"
        bottle = "\(name)"
        """, slug: "remove")
        let bottle = try bottle(name)
        let plan = try Game.plan(slug: slug)
        let removal = Uninstall.plan(for: plan, scope: .bottle)
        try Uninstall.perform(removal, for: plan)
        #expect(!FileManager.default.fileExists(atPath: bottle.path))
        let backups = SaveBackups.list(bottle: name)
        #expect(backups.count == 1)
        #expect(backups.first?.manifest.reason == .beforeRemoval)
    }
}
