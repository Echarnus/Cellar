import CellarDomain
import Foundation
import Testing
@testable import CellarData

/// The engine's small helpers: terminal styling, removal items, the Steam app-id file and the GOG
/// session. Each is a few lines, and each says something the player reads or relies on.
@Suite struct EngineHelperTests {
    @Test("Styling wraps text in ANSI codes only on a terminal, and each check status has its symbol")
    func terminalStyling() {
        // A test's stdout is usually a pipe, where styling switches itself off; on a terminal it
        // wraps the text. Either way the text itself is untouched.
        func styled(_ text: String, _ code: String) -> String {
            Term.useColor ? "\u{001B}[\(code)m\(text)\u{001B}[0m" : text
        }
        #expect(Term.green("ok") == styled("ok", "32"))
        #expect(Term.yellow("ok") == styled("ok", "33"))
        #expect(Term.red("ok") == styled("ok", "31"))
        #expect(Term.cyan("ok") == styled("ok", "36"))
        #expect(Term.dim("ok") == styled("ok", "2"))
        #expect(Term.bold("ok") == styled("ok", "1"))
        #expect(Term.symbol(for: .ok) == styled("✓", "32"))
        #expect(Term.symbol(for: .warn) == styled("!", "33"))
        #expect(Term.symbol(for: .fail) == styled("✗", "31"))
        #expect(Term.symbol(for: .info) == styled("•", "36"))
    }

    @Test("A removal item names a home path with ~, and is told apart by kind and path")
    func removalItemPaths() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let inHome = RemovalItem(label: "Game files", url: home.appendingPathComponent("Games/x"),
                                 bytes: 1, kind: .path, isGameData: true)
        let elsewhere = RemovalItem(label: "Game files", url: URL(fileURLWithPath: "/Volumes/Drive/x"),
                                    bytes: 1, kind: .path, isGameData: true)
        let shortcut = RemovalItem(label: "Entry in your Steam library", url: home.appendingPathComponent("Games/x"),
                                   bytes: 0, kind: .steamShortcut, isGameData: false)

        #expect(inHome.displayPath == "~/Games/x")
        #expect(elsewhere.displayPath == "/Volumes/Drive/x")
        #expect(inHome.id != shortcut.id)
        #expect(inHome.id.hasSuffix(inHome.url.path))
    }

    @Test("A downloaded Steam game gets Valve's steam_appid.txt naming its app")
    func steamAppIDFile() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("steamdrm-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        SteamDRM.markAppDirectory(folder, appID: 588430)

        let written = try String(contentsOf: folder.appendingPathComponent("steam_appid.txt"), encoding: .utf8)
        #expect(written == "588430\n")
    }

    @Test("A GOG token is refreshed a minute before it runs out, and bytes decode as UTF-8")
    func gogSessionFreshness() {
        let fresh = GOGSession(accessToken: "a", refreshToken: "r", userID: "u", expiresAt: Date().addingTimeInterval(3600))
        let expiring = GOGSession(accessToken: "a", refreshToken: "r", userID: "u", expiresAt: Date().addingTimeInterval(30))
        #expect(fresh.isFresh)
        #expect(!expiring.isFresh)

        #expect(String(decoding: Data("héllo".utf8)) == "héllo")
        #expect(String(decoding: Data([0xFF, 0xFE])) == "")
    }

    @Test("Archives extract with the system tools, and a broken one fails with its name")
    func archives() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("archive-\(UUID().uuidString)")
        let source = root.appendingPathComponent("source")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try "hello\n".write(to: source.appendingPathComponent("file.txt"), atomically: true, encoding: .utf8)

        let tar = root.appendingPathComponent("files.tar.gz")
        try run("/usr/bin/tar", ["-czf", tar.path, "-C", source.path, "file.txt"])
        try Archive.extractTar(tar, to: root.appendingPathComponent("from-tar"))
        #expect(try String(contentsOf: root.appendingPathComponent("from-tar/file.txt"), encoding: .utf8) == "hello\n")

        let zip = root.appendingPathComponent("files.zip")
        try run("/usr/bin/ditto", ["-c", "-k", source.appendingPathComponent("file.txt").path, zip.path])
        try Archive.unzip(zip, to: root.appendingPathComponent("from-zip"))
        #expect(try String(contentsOf: root.appendingPathComponent("from-zip/file.txt"), encoding: .utf8) == "hello\n")

        let broken = root.appendingPathComponent("broken.tar.gz")
        try "not an archive".write(to: broken, atomically: true, encoding: .utf8)
        #expect(throws: CellarError.self) { try Archive.extractTar(broken, to: root.appendingPathComponent("x")) }
        #expect(throws: CellarError.self) { try Archive.unzip(broken, to: root.appendingPathComponent("y")) }
        #expect(throws: CellarError.self) { try Archive.withMountedDMG(broken) { $0 } }
    }

    private func run(_ tool: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0, "\(tool) \(arguments.joined(separator: " ")) failed")
    }
}
