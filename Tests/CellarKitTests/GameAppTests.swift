import CellarDomain
import Foundation
import Testing
@testable import CellarKit

/// Game Mode needs the game's process to come from a bundle categorised as a game. `GameApp` builds
/// that bundle around a copy of the runner's loader; these tests check the bundle and the start.
@Suite(.serialized)
struct GameAppTests {
    /// A runner laid out the way Wine 7+ installs: `bin/wine` a symlink to the loader, which sits
    /// beside `ntdll.so`. The "loader" is a script that records its arguments.
    func modernRunner() throws -> (binary: URL, loader: URL) {
        let root = TestHome.scratch("game-app-runner")
        let unix = root.appendingPathComponent("lib/wine/x86_64-unix", isDirectory: true)
        let bin = root.appendingPathComponent("bin", isDirectory: true)
        try FileManager.default.createDirectory(at: unix, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        let loader = unix.appendingPathComponent("wine")
        try "#!/bin/sh\necho \"$@\"\n".write(to: loader, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: loader.path)
        try Data().write(to: unix.appendingPathComponent("ntdll.so"))
        let binary = bin.appendingPathComponent("wine")
        try FileManager.default.createSymbolicLink(at: binary, withDestinationURL: loader)
        return (binary, loader)
    }

    @Test("The loader copied is the real file behind the runner's wine, never the symlink")
    func findsRealLoader() throws {
        let runner = try modernRunner()
        #expect(GameApp.loader(for: runner.binary)?.path == runner.loader.resolvingSymlinksInPath().path)
    }

    @Test("A runner without ntdll.so beside its loader is started the usual way")
    func skipsOtherLayouts() throws {
        let bin = TestHome.scratch("game-app-gptk").appendingPathComponent("bin", isDirectory: true)
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        let wine64 = bin.appendingPathComponent("wine64")
        try Data().write(to: wine64)
        #expect(GameApp.loader(for: wine64) == nil)
        #expect(GameApp.prepare(name: "X", slug: "x-\(UUID().uuidString.prefix(6))", runnerBinary: wine64, icon: nil) == nil)
    }

    @Test("The game's app says it is a game, named and identified as the game, and runs Wine as Wine expects")
    func bundleDeclaresAGame() throws {
        let runner = try modernRunner()
        let slug = "pc2-\(UUID().uuidString.prefix(6))".lowercased()
        let executable = try #require(GameApp.prepare(name: "Planet Coaster 2", slug: slug,
                                                      runnerBinary: runner.binary, icon: nil))
        let app = GameApp.bundleURL(slug: slug)
        #expect(executable.path == app.appendingPathComponent("Contents/MacOS/wine").path)
        #expect(try Data(contentsOf: executable) == Data(contentsOf: runner.loader))
        #expect(FileManager.default.isExecutableFile(atPath: executable.path))

        let data = try Data(contentsOf: app.appendingPathComponent("Contents/Info.plist"))
        let info = try #require(try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        #expect(info["LSApplicationCategoryType"] as? String == "public.app-category.games")
        #expect(info["LSSupportsGameMode"] as? Bool == true)
        #expect(info["CFBundleName"] as? String == "Planet Coaster 2")
        #expect(info["CFBundleExecutable"] as? String == "wine")
        #expect(info["CFBundleIdentifier"] as? String == "it.clercq.cellar.game.\(slug)")
        // What Wine embeds in its own loader: without these the Mac driver would start as a regular
        // app with no Wine application class.
        #expect(info["LSUIElement"] as? String == "1")
        #expect(info["NSPrincipalClass"] as? String == "WineApplication")
        // Not the player's launcher: Reset and Uninstall must never confuse the two.
        #expect(!AppBundle.isGenerated(app))
    }

    @Test("A runner update replaces the copied loader")
    func followsRunnerUpdates() throws {
        let runner = try modernRunner()
        let slug = "upd-\(UUID().uuidString.prefix(6))".lowercased()
        let first = try #require(GameApp.prepare(name: "Game", slug: slug, runnerBinary: runner.binary, icon: nil))
        try "#!/bin/sh\necho updated\n".write(to: runner.loader, atomically: true, encoding: .utf8)
        let second = try #require(GameApp.prepare(name: "Game", slug: slug, runnerBinary: runner.binary, icon: nil))
        #expect(first == second)
        #expect(try String(contentsOf: second, encoding: .utf8).contains("updated"))
    }

    @Test("The bundled loader starts, with the game's arguments and its output in the log")
    func spawnsFromTheBundle() throws {
        let runner = try modernRunner()
        let slug = "run-\(UUID().uuidString.prefix(6))".lowercased()
        let executable = try #require(GameApp.prepare(name: "Game", slug: slug, runnerBinary: runner.binary, icon: nil))
        let log = TestHome.scratch("game-app-log").appendingPathComponent("game.log")
        let wine = WineRunner(binary: runner.binary, prefix: TestHome.scratch("game-app-prefix"))
        try wine.spawn(["C:\\Games\\Game.exe", "-windowed"], log: log, bundledLoader: executable)

        var written = ""
        for _ in 0..<50 where !written.contains("Game.exe") {
            Thread.sleep(forTimeInterval: 0.1)
            written = (try? String(contentsOf: log, encoding: .utf8)) ?? ""
        }
        #expect(written.contains("C:\\Games\\Game.exe -windowed"))
    }
}
