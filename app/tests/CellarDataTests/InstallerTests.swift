import CellarDomain
import Foundation
import Testing
@testable import CellarData

/// The installer's promises that can be checked without a Mac's Finder or a real Wine:
/// where Cellar thinks it is running from, which save games an uninstall keeps, and that an
/// uninstall run in a sandbox can never reach for the player's real copy of Cellar.
@Suite(.serialized)
struct InstallerTests {

    // MARK: - Where Cellar is running from

    @Test("Running from the disk image, or App Translocation's copy of it, offers the move")
    func offersMoveOffTheDiskImage() {
        #expect(InstallLocation.of(bundlePath: "/Volumes/Cellar/Cellar.app") == .diskImage)
        #expect(InstallLocation.of(bundlePath:
            "/private/var/folders/x1/abc/T/AppTranslocation/1F2E-3D4C/d/Cellar.app") == .translocated)
        #expect(InstallLocation.of(bundlePath: "/Volumes/Cellar/Cellar.app").shouldOfferMove)
    }

    @Test("An installed Cellar is left where the player put it")
    func leavesAnInstalledCopyAlone() {
        for path in ["/Applications/Cellar.app", "/Users/someone/Applications/Cellar.app",
                     "/Users/someone/Games/Cellar.app"] {
            #expect(InstallLocation.of(bundlePath: path) == .installed, "\(path)")
            #expect(!InstallLocation.of(bundlePath: path).shouldOfferMove)
        }
    }

    // MARK: - Save games

    /// A bottle with a game's saves in it, the way Wine lays a user profile out.
    private func makeBottle(_ name: String) throws -> URL {
        let user = Paths.prefixes.appendingPathComponent("\(name)/drive_c/users/player", isDirectory: true)
        let fm = FileManager.default
        func write(_ relative: String, _ text: String) throws {
            let url = user.appendingPathComponent(relative)
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try text.write(to: url, atomically: true, encoding: .utf8)
        }
        try write("Saved Games/Frontier Developments/Planet Coaster 2/park.sav", "my park")
        try write("AppData/LocalLow/Studio/Game/slot1.dat", "progress")
        // Not saves: Wine's and the store client's own state, and an empty default folder.
        try write("AppData/Local/Temp/installer.log", "scratch")
        try write("AppData/Roaming/Microsoft/Windows/whatever.ini", "x")
        try fm.createDirectory(at: user.appendingPathComponent("Documents/My Music"), withIntermediateDirectories: true)
        return user
    }

    @Test("An uninstall finds a bottle's saves and leaves Wine's own folders out")
    func findsSaves() throws {
        TestHome.ensure()
        let bottle = "saves-\(UUID().uuidString.prefix(6))"
        _ = try makeBottle(bottle)
        defer { try? FileManager.default.removeItem(at: Paths.prefixes.appendingPathComponent(bottle)) }

        let mine = SaveGames.locate().filter { $0.bottle == bottle }.map(\.relativePath).sorted()
        #expect(mine == ["player/AppData/LocalLow/Studio", "player/Saved Games/Frontier Developments"])
    }

    @Test("A bottle whose Documents is the Mac's own is not copied — those saves are never deleted")
    func doesNotFollowTheRealDocuments() throws {
        TestHome.ensure()
        let bottle = "linked-\(UUID().uuidString.prefix(6))"
        let user = try makeBottle(bottle)
        defer { try? FileManager.default.removeItem(at: Paths.prefixes.appendingPathComponent(bottle)) }
        let realDocuments = TestHome.scratch("documents")
        try "the player's own file".write(to: realDocuments.appendingPathComponent("taxes.txt"),
                                          atomically: true, encoding: .utf8)
        try FileManager.default.removeItem(at: user.appendingPathComponent("Documents"))
        try FileManager.default.createSymbolicLink(at: user.appendingPathComponent("Documents"),
                                                   withDestinationURL: realDocuments)

        let mine = SaveGames.locate().filter { $0.bottle == bottle }
        #expect(!mine.contains { $0.relativePath.contains("Documents") })
        #expect(SaveGames.someSavesAlreadyInDocuments)
    }

    @Test("Saves are copied out intact, with a note saying where each came from")
    func exportsSaves() throws {
        TestHome.ensure()
        let bottle = "export-\(UUID().uuidString.prefix(6))"
        _ = try makeBottle(bottle)
        defer { try? FileManager.default.removeItem(at: Paths.prefixes.appendingPathComponent(bottle)) }
        let destination = TestHome.scratch("saved-games")

        try SaveGames.export(SaveGames.locate().filter { $0.bottle == bottle }, to: destination)

        let park = destination.appendingPathComponent(
            "\(bottle)/player/Saved Games/Frontier Developments/Planet Coaster 2/park.sav")
        #expect(try String(contentsOf: park, encoding: .utf8) == "my park")
        #expect(FileManager.default.fileExists(
            atPath: destination.appendingPathComponent("About these files.txt").path))
    }

    @Test("Each uninstall's saves go to their own dated folder in Documents")
    func datedDestination() {
        let first = SaveGames.defaultDestination(now: Date(timeIntervalSince1970: 0))
        let second = SaveGames.defaultDestination(now: Date(timeIntervalSince1970: 60))
        #expect(first != second)
        #expect(first.path.contains("Documents/Cellar Saved Games/"))
    }

    // MARK: - Uninstalling Cellar itself

    @Test("A sandboxed Cellar never plans to remove the player's real app, CLI or settings")
    func sandboxStaysInTheSandbox() {
        TestHome.ensure()
        #expect(Reset.isRelocated)
        let planned = Reset.plan(includingCellarItself: true).compactMap(\.url).map(\.path)
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        #expect(!planned.contains("/Applications/Cellar.app"))
        #expect(!planned.contains { $0.hasPrefix(home + "/Library/Preferences") })
        #expect(!planned.contains { $0.hasPrefix(home + "/.local") })
    }

    @Test("Only a bundle that really is Cellar counts as Cellar.app")
    func cellarAppIsFoundByIdentity() throws {
        // In a scratch folder, not the shared test Applications folder that CleanupTests uses.
        let app = TestHome.scratch("apps").appendingPathComponent("Cellar.app", isDirectory: true)
        try FileManager.default.createDirectory(at: app.appendingPathComponent("Contents"),
                                                withIntermediateDirectories: true)
        func write(identifier: String) throws {
            let plist = try PropertyListSerialization.data(
                fromPropertyList: ["CFBundleIdentifier": identifier], format: .xml, options: 0)
            try plist.write(to: app.appendingPathComponent("Contents/Info.plist"))
        }
        try write(identifier: "com.example.someone-elses-cellar")
        #expect(!Reset.isCellarApp(app), "an app that merely shares the name is not ours to delete")
        try write(identifier: Reset.appIdentifier)
        #expect(Reset.isCellarApp(app))
    }

    // MARK: - Getting ready

    @Test("The setup lock is re-entrant within one process, so nested setup cannot hang")
    func setupLockIsReentrant() throws {
        TestHome.ensure()
        let value = try SetupLock.withLock { try SetupLock.withLock { 42 } }
        #expect(value == 42)
    }

    @Test("Preparation lists only what is missing, and never the Steam client when it is left out")
    func preparationListsWhatIsMissing() {
        TestHome.ensure()
        let missing = Preparation.missing(includeSteam: false)
        #expect(!missing.contains(.steamClient))
        for part in missing { #expect(!Preparation.isReady(part)) }
    }
}
