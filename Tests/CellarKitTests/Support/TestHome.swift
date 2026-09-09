import Foundation
@testable import CellarKit

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
    @discardableResult
    static func writeProfile(_ toml: String, slug: String = "fixture") -> String {
        let unique = "\(slug)-\(UUID().uuidString.prefix(8))".lowercased()
        let url = profilesDirectory.appendingPathComponent("\(unique).toml")
        try? toml.write(to: url, atomically: true, encoding: .utf8)
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
        // Refuse to write anywhere but the sandbox. The integration target links real runners into
        // its home, and dropping a stub into the player's runner tree would be a genuine mess.
        guard Paths.appSupport.resolvingSymlinksInPath().standardizedFileURL.path.hasPrefix(root.path)
        else { return RunnerManager.find(id: spec.id) }

        let bin = Paths.runners.appendingPathComponent("\(spec.id)/wine/bin", isDirectory: true)
        let binary = bin.appendingPathComponent(spec.wineBinaryName)
        if !FileManager.default.isExecutableFile(atPath: binary.path) {
            try? FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
            try? "#!/bin/sh\nexit 0\n".write(to: binary, atomically: true, encoding: .utf8)
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binary.path)
        }
        return RunnerManager.find(id: spec.id)
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
