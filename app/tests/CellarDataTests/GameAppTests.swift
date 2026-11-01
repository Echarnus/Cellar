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
        let app = GameApp.bundleURL(name: "Planet Coaster 2", slug: slug)
        // The Dock names a running app after its bundle's file name, not CFBundleName.
        #expect(app.lastPathComponent == "Planet Coaster 2.app")
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

    @Test("The bundle is named as the player reads the game, never after its slug")
    func bundleTakesTheGamesName() {
        #expect(GameApp.fileName(for: "Fallout Shelter", slug: "fallout-shelter") == "Fallout Shelter")
        #expect(GameApp.fileName(for: "Kingdom Come: Deliverance II", slug: "kcd2") == "Kingdom Come\u{A789} Deliverance II",
                "Finder shows a : in a file name as /")
        #expect(GameApp.fileName(for: "Half/Life", slug: "hl") == "Half\u{2215}Life", "a / cannot be in a file name")
        #expect(GameApp.fileName(for: "  ", slug: "blank") == "blank")
        #expect(GameApp.fileName(for: ".hidden", slug: "dot") == "dot", "a leading dot would hide the bundle")
    }

    @Test("A bundle named after the slug, from before, is replaced by the one named after the game")
    func replacesTheSlugNamedBundle() throws {
        let runner = try wineForgeRunner()
        let slug = "fallout-shelter-\(UUID().uuidString.prefix(6))".lowercased()
        let legacy = GameApp.legacyBundleURL(slug: slug)
        try FileManager.default.createDirectory(at: legacy.appendingPathComponent("Contents/MacOS"),
                                                withIntermediateDirectories: true)
        _ = try #require(GameApp.prepare(name: "Fallout Shelter", slug: slug, runnerBinary: runner.binary, icon: nil))
        #expect(!FileManager.default.fileExists(atPath: legacy.path))
        #expect(FileManager.default.fileExists(atPath: GameApp.bundleURL(name: "Fallout Shelter", slug: slug).path))
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

    @Test("A signed loader's copy is signed again as the game's app, so macOS lets it run")
    func resignsTheCopiedLoader() throws {
        // WineForge 0.6.0.8's loader is Developer-ID signed over Wine's own Info.plist. Copied into
        // the game's bundle unchanged, `codesign --verify` said "invalid Info.plist" and macOS
        // killed every start at exec (Code Signature Invalid): Planet Coaster 2 never appeared,
        // eight times in a row, on Kenneth's Mac (2026-11-01). Any signed Mach-O stands in for it.
        let runner = try wineForgeRunner()
        try FileManager.default.removeItem(at: runner.inner)
        try FileManager.default.copyItem(at: URL(fileURLWithPath: "/usr/bin/true"), to: runner.inner)
        let slug = "signed-\(UUID().uuidString.prefix(6))".lowercased()
        let start = try #require(GameApp.prepare(name: "Signed Game", slug: slug, runnerBinary: runner.binary, icon: nil))
        let app = GameApp.bundleURL(name: "Signed Game", slug: slug)

        let verify = Shell.run(GameApp.codesign, ["--verify", "--strict", app.path])
        #expect(verify.succeeded, "the bundle's signature holds: \(verify.stderr)")
        let info = Shell.run(GameApp.codesign, ["-dv", app.path])
        let details = info.stdout + info.stderr
        #expect(details.contains("Signature=adhoc"), "signed as the game's app, not the runner's: \(details)")
        #expect(details.contains("Identifier=it.clercq.cellar.game.\(slug)"))
        // And it really runs.
        #expect(Shell.run(start.executable.path, []).succeeded)

        // Signing changes the copy's bytes; that must not read as a runner update on the next Play.
        let modified = try FileManager.default.attributesOfItem(atPath: start.executable.path)[.modificationDate] as? Date
        _ = try #require(GameApp.prepare(name: "Signed Game", slug: slug, runnerBinary: runner.binary, icon: nil))
        #expect(try FileManager.default.attributesOfItem(atPath: start.executable.path)[.modificationDate] as? Date == modified,
                "an unchanged runner is not copied and signed again on every Play")
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
