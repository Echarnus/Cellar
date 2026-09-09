import Foundation
import Testing
@testable import CellarKit

/// Shared machinery for Cellar's integration tests.
///
/// These tests exist because the unit suite can prove that Cellar *decides* correctly and still
/// tell you nothing about whether a Windows game starts. They are tiered so the expensive,
/// machine-dependent parts stay opt-in:
///
/// | Tier | Switch | What it proves |
/// |---|---|---|
/// | A | always | Bottles, app bundles, Steam shortcuts — real files, no Wine, no network. |
/// | B | `CELLAR_IT=1` | A real runner installs, a real Wine prefix initialises as WoW64, and a Windows PE runs in it. |
/// | C | `CELLAR_IT=1` | A Windows-only game goes profile → bottle → launch → watched → shut down, through Cellar's own code. |
///
/// Tier C runs `winemine.exe` — the Win32 Minesweeper that ships inside every Wine build — unless
/// pointed at a real title with `CELLAR_IT_GAME_URL` / `CELLAR_IT_GAME_EXE`. Cellar never commits a
/// game file, so the test supplies the binary and Cellar supplies everything else.
enum IT {

    // MARK: - Tiers

    static var wineTierEnabled: Bool { flag("CELLAR_IT") }

    /// Tier B and C need Apple Silicon plus a working Rosetta, because every runner Cellar ships is
    /// an x86_64 Wine. Reported rather than assumed, so a skip is never mistaken for a pass.
    static var machineCanRunWine: Bool {
        SystemEnvironment.isAppleSilicon && SystemEnvironment.rosettaWorks
    }

    static func flag(_ name: String) -> Bool {
        let value = ProcessInfo.processInfo.environment[name]?.lowercased() ?? ""
        return ["1", "true", "yes", "on"].contains(value)
    }

    static func value(_ name: String) -> String? {
        ProcessInfo.processInfo.environment[name].flatMap { $0.isEmpty ? nil : $0 }
    }

    // MARK: - Sandbox

    /// A throwaway Cellar home, so an integration run cannot damage the player's bottles.
    /// Runners are the one exception: they are hundreds of megabytes, so an already-installed
    /// runner tree is linked in read-only rather than downloaded again.
    static let home: URL = {
        let environment = ProcessInfo.processInfo.environment
        let root = (environment["CELLAR_TEST_ROOT"].flatMap { $0.isEmpty ? nil : $0 })
            .map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
                .appendingPathComponent("cellar-it-\(ProcessInfo.processInfo.processIdentifier)",
                                        isDirectory: true)

        for (key, url) in [("CELLAR_HOME", root.appendingPathComponent("home", isDirectory: true)),
                           ("CELLAR_PROFILES_DIR", root.appendingPathComponent("profiles", isDirectory: true)),
                           ("CELLAR_APPLICATIONS_DIR", root.appendingPathComponent("Applications", isDirectory: true))] {
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            if environment[key] != url.path { setenv(key, url.path, 1) }
        }
        linkRealRunners()
        return root
    }()

    @discardableResult
    static func ensure() -> URL { home }

    static var profilesDirectory: URL {
        ensure().appendingPathComponent("profiles", isDirectory: true)
    }

    /// Reuse the machine's installed runners instead of re-downloading ~400 MB per test run.
    ///
    /// Each runner is linked *individually*, so `Paths.runners` stays a real directory the sandbox
    /// owns; only the runner trees themselves are shared, and nothing a test does writes into them.
    private static func linkRealRunners() {
        let fm = FileManager.default
        let real = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Cellar/runners", isDirectory: true)
        guard let entries = try? fm.contentsOfDirectory(at: real, includingPropertiesForKeys: nil) else { return }
        try? fm.createDirectory(at: Paths.runners, withIntermediateDirectories: true)
        for runner in entries where RunnerCatalog.spec(forID: runner.lastPathComponent) != nil {
            let link = Paths.runners.appendingPathComponent(runner.lastPathComponent)
            guard !fm.fileExists(atPath: link.path) else { continue }
            try? fm.createSymbolicLink(at: link, withDestinationURL: runner)
        }
    }

    static func scratch(_ label: String) -> URL {
        let dir = ensure().appendingPathComponent("\(label)-\(UUID().uuidString.prefix(8))", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @discardableResult
    static func writeProfile(_ toml: String, slug: String) -> String {
        let unique = "\(slug)-\(UUID().uuidString.prefix(8))".lowercased()
        try? toml.write(to: profilesDirectory.appendingPathComponent("\(unique).toml"),
                        atomically: true, encoding: .utf8)
        return unique
    }

    // MARK: - The repository under test

    /// The repo root, derived from this file's own location, so the profile-database tests read the
    /// real `profiles/` directory regardless of where `swift test` was invoked from.
    static let repositoryRoot: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // CellarIntegrationTests
        .deletingLastPathComponent()   // Tests
        .deletingLastPathComponent()   // <repo>

    static var shippedProfilesDirectory: URL {
        repositoryRoot.appendingPathComponent("profiles", isDirectory: true)
    }

    /// Copy the repo's profile database into the sandbox so discovery works no matter which
    /// directory `swift test` was run from. Done once; fixtures use unique slugs and never collide.
    static let shippedProfilesStaged: Bool = {
        ensure()
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(at: shippedProfilesDirectory,
                                                        includingPropertiesForKeys: nil) else { return false }
        for url in entries where url.pathExtension == "toml" {
            let target = profilesDirectory.appendingPathComponent(url.lastPathComponent)
            try? fm.removeItem(at: target)
            try? fm.copyItem(at: url, to: target)
        }
        return true
    }()

    // MARK: - Runner

    /// The runner tier B and C run through: whatever is already installed (preferring the default),
    /// otherwise the catalog default, installed on demand.
    static func resolveRunner(progress: (String) -> Void = { _ in }) throws -> RunnerInstall {
        ensure()
        if let preferred = value("CELLAR_IT_RUNNER") {
            if let found = RunnerManager.find(id: preferred) { return found }
            guard let spec = RunnerCatalog.spec(forID: preferred) else {
                throw CellarError.invalidArgument("CELLAR_IT_RUNNER names no known runner: \(preferred)")
            }
            return try RunnerManager.install(spec, progress: progress)
        }
        if let byDefault = RunnerManager.find(id: RunnerCatalog.defaultID) { return byDefault }
        if let any = RunnerManager.installed().first { return any }
        return try RunnerManager.install(RunnerCatalog.wineforge, progress: progress)
    }

    // MARK: - The game under test

    /// Where the Windows executable tier C runs comes from.
    enum GameSource {
        /// `winemine.exe` out of the runner itself — a real Win32 PE, always available, zero
        /// download. The default, so the pipeline is provable on any machine.
        case wineBuiltin(name: String)
        /// A third-party Windows-only game the operator pointed the test at.
        case download(url: String, exe: String)

        static var configured: GameSource {
            if let url = IT.value("CELLAR_IT_GAME_URL") {
                return .download(url: url, exe: IT.value("CELLAR_IT_GAME_EXE") ?? "game.exe")
            }
            return .wineBuiltin(name: IT.value("CELLAR_IT_GAME_EXE") ?? "winemine.exe")
        }

        var exeName: String {
            switch self {
            case .wineBuiltin(let name): return name
            case .download(_, let exe): return (exe as NSString).lastPathComponent
            }
        }

        var relativeExe: String {
            switch self {
            case .wineBuiltin(let name): return name
            case .download(_, let exe): return exe
            }
        }

        var label: String {
            switch self {
            case .wineBuiltin(let name): return "\(name) (Wine's own Win32 build)"
            case .download(let url, _): return url
            }
        }
    }

    /// Put the game's files where the profile says they are, exactly as a real install would leave
    /// them, and return the absolute exe.
    @discardableResult
    static func installGameFiles(_ source: GameSource, into plan: GamePlan,
                                 runner: RunnerInstall) throws -> URL {
        let fm = FileManager.default
        let destination = plan.depotGameDir
        try fm.createDirectory(at: destination, withIntermediateDirectories: true)

        switch source {
        case .wineBuiltin(let name):
            guard let origin = wineBuiltin(name, in: runner) else {
                throw CellarError.ioFailure("Runner '\(runner.spec.id)' ships no \(name).")
            }
            let target = destination.appendingPathComponent(name)
            try? fm.removeItem(at: target)
            try fm.copyItem(at: origin, to: target)
            return target

        case .download(let url, let exe):
            let archive = Paths.cache.appendingPathComponent("it-game-\(abs(url.hashValue)).bin")
            if !fm.fileExists(atPath: archive.path) {
                try Downloader.fetch(url, to: archive, showProgress: false)
            }
            if url.lowercased().hasSuffix(".zip") {
                try Archive.unzip(archive, to: destination)
            } else if url.lowercased().contains(".tar") {
                try Archive.extractTar(archive, to: destination)
            } else {
                try? fm.removeItem(at: destination.appendingPathComponent(exe))
                try fm.copyItem(at: archive, to: destination.appendingPathComponent(exe))
            }
            // A zip may nest the game one directory down; find the exe wherever it landed.
            let target = destination.appendingPathComponent(exe)
            if fm.fileExists(atPath: target.path) { return target }
            guard let found = firstFile(named: (exe as NSString).lastPathComponent, under: destination) else {
                throw CellarError.ioFailure("Downloaded \(url) but found no \(exe) inside it.")
            }
            return found
        }
    }

    /// A Windows PE that ships inside the Wine build itself (`winemine.exe`, `notepad.exe`, …).
    static func wineBuiltin(_ name: String, in runner: RunnerInstall) -> URL? {
        let roots = ["lib/wine/x86_64-windows", "lib/wine/i386-windows", "lib64/wine/x86_64-windows"]
        return roots
            .map { runner.wineRoot.appendingPathComponent("\($0)/\(name)") }
            .first { FileManager.default.fileExists(atPath: $0.path) }
    }

    static func firstFile(named name: String, under directory: URL) -> URL? {
        guard let walker = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil)
        else { return nil }
        for case let url as URL in walker where url.lastPathComponent.lowercased() == name.lowercased() {
            return url
        }
        return nil
    }

    // MARK: - Reporting

    /// Integration tests print what they did, because "skipped" and "passed" must never look alike
    /// in a log someone reads to decide whether a change is safe.
    static func log(_ message: String) {
        print("[integration] \(message)")
    }
}
