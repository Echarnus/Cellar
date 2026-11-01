import CellarDomain
import Foundation
import Testing
@testable import CellarData

/// Game Mode needs the game's process to come from a bundle categorised as a game. `GameApp` builds
/// that bundle around a copy of the runner's loader; these tests check the bundle and the start.
@Suite(.serialized)
struct GameAppTests {
    static let recorder = "#!/bin/sh\necho \"$@ noexec=$WINELOADERNOEXEC\"\n"

    func executable(_ url: URL, _ body: String = recorder) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try body.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }

    /// WineForge's layout, as found on a real install: `bin/wine` a real file (the first-run
    /// wrapper), and beside `ntdll.so` in `lib/wine/x86_64-unix` the loader every Windows process
    /// actually runs as. The "loaders" are scripts that record their arguments.
    func wineForgeRunner() throws -> (binary: URL, inner: URL) {
        let root = TestHome.scratch("game-app-wineforge")
        let unix = root.appendingPathComponent("lib/wine/x86_64-unix", isDirectory: true)
        let binary = root.appendingPathComponent("bin/wine")
        try executable(binary, "#!/bin/sh\necho wrapper\n")
        let inner = unix.appendingPathComponent("wine")
        try executable(inner)
        try Data().write(to: unix.appendingPathComponent("ntdll.so"))
        return (binary, inner)
    }

    @Test("WineForge: the loader copied is the one every game process runs as, not bin/wine")
    func copiesTheInnerLoader() throws {
        // The first version copied bin/wine's layout only when ntdll.so sat beside it, so on
        // WineForge no game app was made and Planet Coaster 2 went on running as bare "wine".
        // Copying bin/wine would not do either: it re-execs into the inner loader at startup.
        let runner = try wineForgeRunner()
        let found = try #require(GameApp.loader(for: runner.binary))
        #expect(found.file.path == runner.inner.resolvingSymlinksInPath().path)
        #expect(found.noExec)
    }

    @Test("Wine 10: bin/wine is the loader itself and is started as it always is")
    func wine10Layout() throws {
        let root = TestHome.scratch("game-app-wine10")
        let binary = root.appendingPathComponent("bin/wine")
        try executable(binary)
        let unix = root.appendingPathComponent("lib/wine/x86_64-unix", isDirectory: true)
        try FileManager.default.createDirectory(at: unix, withIntermediateDirectories: true)
        try Data().write(to: unix.appendingPathComponent("ntdll.so"))
        let found = try #require(GameApp.loader(for: binary))
        #expect(found.file.path == binary.resolvingSymlinksInPath().path)
        #expect(!found.noExec)
    }

    @Test("A runner whose loader can be copied makes the game app available; one that can't does not")
    func availability() throws {
        let runner = try wineForgeRunner()
        #expect(GameApp.isAvailable(runnerBinary: runner.binary))
        let wine64 = TestHome.scratch("game-app-unavailable").appendingPathComponent("bin/wine64")
        try executable(wine64)
        #expect(!GameApp.isAvailable(runnerBinary: wine64))
    }

    @Test("A runner with no ntdll.so where Wine looks for it is started the usual way")
    func skipsOtherLayouts() throws {
        let wine64 = TestHome.scratch("game-app-gptk").appendingPathComponent("bin/wine64")
        try executable(wine64)
        #expect(GameApp.loader(for: wine64) == nil)
        #expect(GameApp.prepare(name: "X", slug: "x-\(UUID().uuidString.prefix(6))", runnerBinary: wine64, icon: nil) == nil)
    }

    @Test("The game's app says it is a game, named and identified as the game, and runs Wine as Wine expects")
    func bundleDeclaresAGame() throws {
        let runner = try wineForgeRunner()
        let slug = "pc2-\(UUID().uuidString.prefix(6))".lowercased()
        let start = try #require(GameApp.prepare(name: "Planet Coaster 2", slug: slug,
                                                 runnerBinary: runner.binary, icon: nil))
        let app = GameApp.bundleURL(slug: slug)
        #expect(start.executable.path == app.appendingPathComponent("Contents/MacOS/wine").path)
        #expect(try Data(contentsOf: start.executable) == Data(contentsOf: runner.inner))
        #expect(FileManager.default.isExecutableFile(atPath: start.executable.path))
        // Wine finds ntdll.so beside argv[0], so argv[0] names the runner's loader, not the copy.
        #expect(start.argv0 == runner.inner.resolvingSymlinksInPath().path)
        #expect(start.environment["WINELOADERNOEXEC"] == "1")

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
        let runner = try wineForgeRunner()
        let slug = "upd-\(UUID().uuidString.prefix(6))".lowercased()
        let first = try #require(GameApp.prepare(name: "Game", slug: slug, runnerBinary: runner.binary, icon: nil))
        try executable(runner.inner, "#!/bin/sh\necho updated\n")
        let second = try #require(GameApp.prepare(name: "Game", slug: slug, runnerBinary: runner.binary, icon: nil))
        #expect(first == second)
        #expect(try String(contentsOf: second.executable, encoding: .utf8).contains("updated"))
    }

    @Test("The bundled loader starts with the game's arguments, no re-exec, and its output in the log")
    func spawnsFromTheBundle() throws {
        let runner = try wineForgeRunner()
        let slug = "run-\(UUID().uuidString.prefix(6))".lowercased()
        let start = try #require(GameApp.prepare(name: "Game", slug: slug, runnerBinary: runner.binary, icon: nil))
        let log = TestHome.scratch("game-app-log").appendingPathComponent("game.log")
        let wine = WineRunner(binary: runner.binary, prefix: TestHome.scratch("game-app-prefix"))
        try wine.spawn(["C:\\Games\\Game.exe", "-windowed"], log: log, bundledLoader: start)

        var written = ""
        for _ in 0..<50 where !written.contains("Game.exe") {
            Thread.sleep(forTimeInterval: 0.1)
            written = (try? String(contentsOf: log, encoding: .utf8)) ?? ""
        }
        #expect(written.contains("C:\\Games\\Game.exe -windowed noexec=1"))
        #expect(!written.contains("wrapper"), "the copy ran, not the runner's bin/wine")
    }
}
