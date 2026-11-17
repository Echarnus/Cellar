import CellarDomain
import Foundation
import Testing
@testable import CellarData

/// A runner installed from the player's own files (`runner-artifacts.json`). What has to hold: the
/// files named are the only ones used, each is checked against its own SHA-256, and no mistake in
/// the file ever turns into the catalog's downloads.
@Suite(.serialized)
struct RunnerOverridesTests {
    static let id = "sikarugir"
    static let pin = String(repeating: "ab", count: 32)

    private func scratch() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("cellar-own-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func applied(_ json: String) throws -> RunnerSpec {
        let dir = try scratch()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("runner-artifacts.json")
        try json.write(to: file, atomically: true, encoding: .utf8)
        return RunnerOverrides.applied(to: RunnerCatalog.sikarugir, file: file)
    }

    @Test("The files named for a runner replace the catalog's, whole")
    func replaces() throws {
        let spec = try applied("""
        { "sikarugir": [
            { "kind": "wineEngine", "source": "/builds/wine.tar.xz", "payloadPath": "wine", "sha256": "\(Self.pin)" },
            { "kind": "wrapperFrameworks", "source": "https://example.org/fw.tar.xz", "sha256": "\(Self.pin)" } ] }
        """)
        #expect(spec.artifacts.map(\.url) == ["/builds/wine.tar.xz", "https://example.org/fw.tar.xz"])
        #expect(spec.artifacts.map(\.kind) == [.wineEngine, .wrapperFrameworks])
        #expect(spec.artifacts.map(\.isLocal) == [true, false])
        #expect(spec.artifacts[0].payloadPath == "wine" && spec.artifacts[1].payloadPath.isEmpty)
    }

    @Test("No file, or a file about another runner, leaves the catalog's artifacts")
    func untouched() throws {
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent("cellar-none-\(UUID().uuidString)")
        #expect(RunnerOverrides.applied(to: RunnerCatalog.sikarugir, file: missing).artifacts.count == 2)
        #expect(try applied(#"{ "gptk": [] }"#).artifacts.map(\.url) == RunnerCatalog.sikarugir.artifacts.map(\.url))
    }

    @Test("A file with a mistake in it leaves nothing to install, never the catalog's downloads",
          arguments: [
            "not json",
            #"{ "sikarugir": [ { "kind": "wineEngine", "source": "http://example.org/w.tar.xz", "sha256": "PIN" } ] }"#,
            #"{ "sikarugir": [ { "kind": "wineEngine", "source": "builds/w.tar.xz", "sha256": "PIN" } ] }"#,
            #"{ "sikarugir": [ { "kind": "wineEngine", "source": "/builds/w.tar.xz", "sha256": "abc" } ] }"#,
            #"{ "sikarugir": [ { "kind": "wine", "source": "/builds/w.tar.xz", "sha256": "PIN" } ] }"#,
          ])
    func mistakes(_ json: String) throws {
        #expect(try applied(json.replacingOccurrences(of: "PIN", with: Self.pin)).artifacts.isEmpty)
    }

    /// A Wine engine tarball of the player's own, and the override file naming it with `sha256`
    /// (its real one when nil). Returns the tarball.
    private func ownEngine(in dir: URL, sha256: String? = nil) throws -> URL {
        let fm = FileManager.default
        let bin = dir.appendingPathComponent("tree/wine/bin", isDirectory: true)
        try fm.createDirectory(at: bin, withIntermediateDirectories: true)
        for name in ["wine", "wineserver"] {
            try RunnerIntegrityTests.machO.write(to: bin.appendingPathComponent(name))
            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: bin.appendingPathComponent(name).path)
        }
        let tarball = dir.appendingPathComponent("wine.tar.xz")
        try #require(Shell.run("/usr/bin/tar", ["-cJf", tarball.path, "-C", dir.appendingPathComponent("tree").path, "wine"]).succeeded)
        let entry = ["kind": "wineEngine", "source": tarball.path, "payloadPath": "wine",
                     "sha256": try sha256 ?? Checksum.sha256(of: tarball)]
        try JSONSerialization.data(withJSONObject: [Self.id: [entry]]).write(to: RunnerOverrides.file)
        return tarball
    }

    private func cleanUp(_ dir: URL) {
        for url in [dir, RunnerOverrides.file, Paths.runners.appendingPathComponent(Self.id)] {
            try? FileManager.default.removeItem(at: url)
        }
    }

    @Test("A runner installs from the player's own file, which stays where it was, and checks out against it")
    func installsFromOwnFile() throws {
        TestHome.ensure()
        try Paths.ensureBaseDirectories()
        let dir = try scratch()
        defer { cleanUp(dir) }
        cleanUp(Paths.runners.appendingPathComponent(Self.id))
        let tarball = try ownEngine(in: dir)

        let install = try RunnerManager.install(try #require(RunnerCatalog.spec(forID: Self.id)))
        #expect(FileManager.default.isExecutableFile(atPath: install.wineBinary.path))
        #expect(FileManager.default.fileExists(atPath: tarball.path), "the player's file is not Cellar's to delete")
        #expect(RunnerIntegrity.check(runnerID: Self.id) == .intact)
    }

    @Test("A file that isn't the one named is refused: nothing installed, nothing deleted, nothing downloaded")
    func refusesAnotherFile() throws {
        TestHome.ensure()
        try Paths.ensureBaseDirectories()
        let dir = try scratch()
        defer { cleanUp(dir) }
        cleanUp(Paths.runners.appendingPathComponent(Self.id))
        let tarball = try ownEngine(in: dir, sha256: Self.pin)

        #expect(throws: CellarError.self) {
            try RunnerManager.install(try #require(RunnerCatalog.spec(forID: Self.id)))
        }
        #expect(FileManager.default.fileExists(atPath: tarball.path))
        #expect(RunnerManager.find(id: Self.id) == nil)
    }
}
