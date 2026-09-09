import Foundation
import Testing
@testable import CellarKit

/// What a removal takes with it.
///
/// Cellar does not live in one folder: besides `~/Library/Application Support/Cellar` it writes
/// launcher `.app`s into `~/Applications` and lines into the native Steam client's shortcut
/// database. `Uninstall` has always cleaned both for a single game; `Reset` did not, so a full
/// reset left a Launchpad of icons that opened nothing. These pin the two halves of the promise:
///
/// - **everything Cellar made is found** — by identity, so a renamed launcher is still ours;
/// - **nothing else is** — a player's own `.app` of the same name is never a candidate.
///
/// The second half is the one worth having. Reset deletes without a per-item prompt, so a
/// false positive here is somebody else's application removed silently.
@Suite(.serialized)
struct CleanupTests {

    private func makeApp(named name: String, identifier: String, executable: String) throws -> URL {
        let dir = TestHome.applicationsDirectory
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let app = dir.appendingPathComponent("\(name).app", isDirectory: true)
        try? FileManager.default.removeItem(at: app)
        let macOS = app.appendingPathComponent("Contents/MacOS", isDirectory: true)
        try FileManager.default.createDirectory(at: macOS, withIntermediateDirectories: true)
        try "#!/bin/sh\nexit 0\n".write(to: macOS.appendingPathComponent(executable),
                                       atomically: true, encoding: .utf8)
        let plist: [String: Any] = ["CFBundleIdentifier": identifier,
                                    "CFBundleExecutable": executable]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: app.appendingPathComponent("Contents/Info.plist"))
        return app
    }

    @Test("A launcher Cellar generated is recognised as Cellar's")
    func generatedLauncherIsFound() throws {
        TestHome.ensure()
        let app = try AppBundle.generate(name: "Fixture Game \(UUID().uuidString.prefix(6))",
                                         slug: "fixture-cleanup", cellarBinary: "/usr/bin/true").app
        defer { try? FileManager.default.removeItem(at: app) }

        #expect(AppBundle.isGenerated(app))
        #expect(AppBundle.generatedApps().contains(app))
    }

    @Test("Identity, not name: a launcher the player renamed is still Cellar's")
    func renamedLauncherIsStillOurs() throws {
        TestHome.ensure()
        let made = try AppBundle.generate(name: "Before \(UUID().uuidString.prefix(6))",
                                          slug: "fixture-renamed", cellarBinary: "/usr/bin/true").app
        let renamed = made.deletingLastPathComponent()
            .appendingPathComponent("After \(UUID().uuidString.prefix(6)).app", isDirectory: true)
        try FileManager.default.moveItem(at: made, to: renamed)
        defer { try? FileManager.default.removeItem(at: renamed) }

        #expect(AppBundle.isGenerated(renamed))
        #expect(AppBundle.generatedApps().contains(renamed))
    }

    @Test("Somebody else's app is never a candidate, whatever it is called")
    func foreignAppIsLeftAlone() throws {
        TestHome.ensure()
        // Deliberately named like a game Cellar ships a profile for.
        let theirs = try makeApp(named: "Planet Coaster 2 \(UUID().uuidString.prefix(6))",
                                 identifier: "com.frontier.planetcoaster2", executable: "launcher")
        defer { try? FileManager.default.removeItem(at: theirs) }

        #expect(!AppBundle.isGenerated(theirs))
        #expect(!AppBundle.generatedApps().contains(theirs))
    }

    @Test("Cellar.app is not swept up by its own reset")
    func cellarAppIsNotAGeneratedLauncher() throws {
        TestHome.ensure()
        // The shape install-app.sh writes: our identifier prefix, but the real app's executable.
        // Without the executable check this would be deleted by `cellar reset`, mid-run.
        let cellar = try makeApp(named: "Cellar \(UUID().uuidString.prefix(6))",
                                 identifier: "it.clercq.cellar.app", executable: "CellarApp")
        defer { try? FileManager.default.removeItem(at: cellar) }

        #expect(!AppBundle.isGenerated(cellar))
        #expect(!AppBundle.generatedApps().contains(cellar))
    }

    @Test("A bundle with no readable Info.plist is not ours")
    func unreadableBundleIsNotOurs() throws {
        TestHome.ensure()
        let dir = TestHome.applicationsDirectory
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let app = dir.appendingPathComponent("Empty \(UUID().uuidString.prefix(6)).app", isDirectory: true)
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: app) }

        #expect(!AppBundle.isGenerated(app))
    }

    @Test("Reset plans to remove the launchers Cellar made, not just its own folder")
    func resetCoversGeneratedLaunchers() throws {
        TestHome.ensure()
        let app = try AppBundle.generate(name: "Reset Fixture \(UUID().uuidString.prefix(6))",
                                         slug: "fixture-reset", cellarBinary: "/usr/bin/true").app
        defer { try? FileManager.default.removeItem(at: app) }

        let planned = Reset.plan().compactMap(\.url)
        #expect(planned.contains(app),
                "a reset that leaves launchers behind gives the player icons that open nothing")
    }

    @Test("Reset says what it is leaving behind rather than implying it took everything")
    func resetNamesWhatItKeeps() throws {
        TestHome.ensure()
        let cellar = TestHome.applicationsDirectory.appendingPathComponent("Cellar.app", isDirectory: true)
        try? FileManager.default.removeItem(at: cellar)
        _ = try makeApp(named: "Cellar", identifier: "it.clercq.cellar.app", executable: "CellarApp")
        defer { try? FileManager.default.removeItem(at: cellar) }

        let items = Reset.plan()
        #expect(Reset.leftBehind(after: items).contains(cellar))

        // …and --everything takes it, so the promise can actually be kept.
        let all = Reset.plan(includingCellarItself: true)
        #expect(all.compactMap(\.url).contains(cellar))
        #expect(!Reset.leftBehind(after: all).contains(cellar))
    }
}
