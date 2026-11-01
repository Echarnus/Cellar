import CellarDomain
import Foundation
@testable import CellarData
import CellarInfrastructure

/// A throwaway Cellar installation for the duration of the test process.
///
/// Cellar keeps everything under one root (`Paths.appSupport`), and `CELLAR_HOME` relocates that
/// root. Pointing it at a temp directory is what makes bottles, runners, logs and generated app
/// bundles safe to create in a test: nothing here can reach the player's real library.
///
/// The environment is written exactly once, from a lazy static, and never mutated again — suites
/// that touch it are `.serialized` so the write can't race a concurrent read.
enum TestHome {
    /// The sandbox root. `Scripts/test.sh` normally supplies it, in which case nothing here touches
    /// the environment at all. Running `swift test` bare still works: the sandbox is created and the
    /// variables written once, from this lazy static.
    static let root: URL = {
        // The tests are a composition root too: wire the real store adapters in, the way the
        // CLI's `main` does, before anything can ask a store a question.
        CellarInfrastructure.install()
        let environment = ProcessInfo.processInfo.environment
        // Symlinks and stray slashes resolved once, here. `/var` is a symlink to `/private/var`
        // and `TMPDIR` ends in a slash, so an unnormalised root compares unequal to the very paths
        // derived from it — and `installStubRunner`'s "am I inside the sandbox?" guard, which is
        // what keeps a test from writing into the player's runner tree, would refuse its own home.
        let raw = (environment["CELLAR_TEST_ROOT"].flatMap { $0.isEmpty ? nil : $0 })
            .map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
                .appendingPathComponent("cellar-tests-\(ProcessInfo.processInfo.processIdentifier)",
                                        isDirectory: true)
        try? FileManager.default.createDirectory(at: raw, withIntermediateDirectories: true)
        let base = raw.resolvingSymlinksInPath().standardizedFileURL

        for (key, url) in [("CELLAR_HOME", base.appendingPathComponent("home", isDirectory: true)),
                           ("CELLAR_PROFILES_DIR", base.appendingPathComponent("profiles", isDirectory: true)),
                           ("CELLAR_APPLICATIONS_DIR", base.appendingPathComponent("Applications", isDirectory: true))] {
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            // Only write when it would actually change — a no-op setenv cannot race a reader.
            if environment[key] != url.path { setenv(key, url.path, 1) }
        }
        return base
    }()

    @discardableResult
    static func ensure() -> URL { root }

    /// Highest-priority profile directory: a slug written here outranks anything Cellar ships.
    static var profilesDirectory: URL {
        ensure().appendingPathComponent("profiles", isDirectory: true)
    }

    /// Where `AppBundle` writes generated launchers during a test.
    static var applicationsDirectory: URL {
        ensure().appendingPathComponent("Applications", isDirectory: true)
    }

    /// A private scratch directory, unique per call — for tests that need a filesystem but not a
    /// whole Cellar home.
    static func scratch(_ label: String = "scratch") -> URL {
        let dir = ensure().appendingPathComponent("\(label)-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Write a profile fixture and return the slug it can be looked up by. Slugs are made unique so
    /// tests never collide with each other or with the profiles the repo ships.
    ///
    /// Every real profile names its store, and `Game.plan` refuses one that doesn't. A fixture that
    /// is about something else and leaves the store out gets `store = "steam"` added; pass
    /// `namingAStore: false` to test the refusal itself.
    @discardableResult
    static func writeProfile(_ toml: String, slug: String = "fixture", namingAStore: Bool = true) -> String {
        let unique = "\(slug)-\(UUID().uuidString.prefix(8))".lowercased()
        let url = profilesDirectory.appendingPathComponent("\(unique).toml")
        let namesStore = toml.range(of: #"(?m)^\s*store\s*="#, options: .regularExpression) != nil
        let text = namingAStore && !namesStore ? "[game]\nstore = \"steam\"\n\n" + toml : toml
        try? text.write(to: url, atomically: true, encoding: .utf8)
        return unique
    }

    /// Write a profile and resolve it into the `GamePlan` the rest of Cellar would see.
    static func plan(_ toml: String, slug: String = "fixture") throws -> GamePlan {
        try Game.plan(slug: writeProfile(toml, slug: slug))
    }

    /// A runner that exists on disk but does nothing.
    ///
    /// `Game.installGame`, `openStoreClient` and `launch` all resolve a runner before they get as
    /// far as the store-specific branch, so without one every store test would stop at "runner
    /// isn't installed" and prove nothing about the store. `RunnerManager` only asks whether
    /// `<runner>/wine/bin/<name>` is executable, so a shell script satisfies it — and these tests
    /// never actually execute it.
    @discardableResult
    static func installStubRunner(id: String = RunnerCatalog.defaultID) -> RunnerInstall? {
        ensure()
        let spec = RunnerCatalog.spec(forID: id) ?? RunnerCatalog.wineforge
        // Refuse to write anywhere but the sandbox. Handing back the runner found elsewhere is what
        // once let `FakeWine` overwrite the player's real `wine` with a script that runs nothing —
        // every Play after that "started" Steam and got nothing (#190). No runner is the answer.
        guard isInside(Paths.appSupport) else { return nil }

        // The integration target links the machine's real runner trees into this same home
        // (`IntegrationSupport.linkRealRunner`). A stub written through that link lands in the
        // player's runner, so the link is taken away first — the link only, never what it points at.
        let runnerDirectory = Paths.runners.appendingPathComponent(spec.id, isDirectory: true)
        if isSymbolicLink(runnerDirectory) {
            try? FileManager.default.removeItem(at: runnerDirectory)
        }
        let bin = runnerDirectory.appendingPathComponent("wine/bin", isDirectory: true)
        let binary = bin.appendingPathComponent(spec.wineBinaryName)
        guard isInside(binary) else { return nil }
        if !FileManager.default.isExecutableFile(atPath: binary.path) {
            try? FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
            try? "#!/bin/sh\nexit 0\n".write(to: binary, atomically: true, encoding: .utf8)
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binary.path)
        }
        guard let install = RunnerManager.find(id: spec.id) else { return nil }
        // Recorded as the runner Cellar installed, the way `RunnerManager.install` records a real
        // one — or Play's integrity check would see a script where `wine` belongs, call the runner
        // damaged and set about downloading a fresh one (`RunnerIntegrity`).
        try? RunnerIntegrity.record(install)
        return install
    }

    /// Whether `url`, with every symbolic link on its way resolved, is inside the sandbox. A path
    /// that merely *starts* in the sandbox can still lead out of it through a link.
    ///
    /// Both sides go through `realPath`: `test.sh` hands over `/var/…//cellar-tests.X` while a
    /// resolved path reads `/private/var/…`, and a file not written yet has to be judged by where
    /// its folder really is.
    static func isInside(_ url: URL) -> Bool {
        let path = realPath(url)
        let home = realPath(root)
        return path == home || path.hasPrefix(home + "/")
    }

    /// Where `url` really is: every link on the way followed, including the ones in folders above a
    /// file that doesn't exist yet — which `resolvingSymlinksInPath` leaves alone, and which is
    /// exactly the case of a script about to be written through a linked runner.
    static func realPath(_ url: URL) -> String {
        var existing = url.standardizedFileURL
        var rest: [String] = []
        while !FileManager.default.fileExists(atPath: existing.path), existing.path != "/" {
            rest.insert(existing.lastPathComponent, at: 0)
            existing = existing.deletingLastPathComponent()
        }
        guard let resolved = realpath(existing.path, nil) else { return url.standardizedFileURL.path }
        defer { free(resolved) }
        return rest.reduce(String(cString: resolved)) { ($0 as NSString).appendingPathComponent($1) }
    }

    static func isSymbolicLink(_ url: URL) -> Bool {
        (try? FileManager.default.destinationOfSymbolicLink(atPath: url.path)) != nil
    }

    /// Create the on-disk shape of a bottle that has `exe` sitting where the profile says it is,
    /// so `directLaunchExe` and friends have something real to find.
    static func installFakeGame(into plan: GamePlan, at relativeExe: String) throws {
        let exe = plan.depotGameDir.appendingPathComponent(relativeExe)
        try FileManager.default.createDirectory(at: exe.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        // "MZ" — Cellar checks the DOS magic before handing anything to Wine.
        try Data([0x4D, 0x5A] + [UInt8](repeating: 0, count: 62)).write(to: exe)
    }
}
