import CellarDomain
import Foundation
import Testing
@testable import CellarData

/// Play checks the runner first and repairs it by itself (#194).
///
/// #190 left a runner whose `wine` was a script that runs nothing; every game "started" into
/// silence and the only way out was a Terminal command. These tests hold the check and the repair
/// to what a player needs: a damaged runner is noticed, replaced, and never left worse than it was.
///
/// They work on the sandbox's `sikarugir` runner, so the default runner the launch suites stand on
/// is never disturbed, and take it away again after each test so no other suite finds it installed.
@Suite(.serialized)
final class RunnerIntegrityTests {
    static let id = RunnerCatalog.sikarugir.id

    deinit {
        try? FileManager.default.removeItem(at: Paths.runners.appendingPathComponent(Self.id, isDirectory: true))
    }

    /// The first bytes of a 64-bit Mach-O, which is all the manifest-less check reads.
    static let machO = Data([0xCF, 0xFA, 0xED, 0xFE] + [UInt8](repeating: 0, count: 60))

    private var root: URL { Paths.runners.appendingPathComponent(Self.id, isDirectory: true) }

    /// A runner on disk with `wine` and `wineserver` holding `contents`, and no manifest.
    @discardableResult
    private func runner(_ contents: Data = machO, label: String = "original") throws -> RunnerInstall {
        TestHome.ensure()
        let fm = FileManager.default
        try? fm.removeItem(at: root)
        let bin = root.appendingPathComponent("wine/bin", isDirectory: true)
        try fm.createDirectory(at: bin, withIntermediateDirectories: true)
        for name in ["wine", "wineserver"] {
            let url = bin.appendingPathComponent(name)
            try contents.write(to: url)
            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        }
        try label.write(to: root.appendingPathComponent("label.txt"), atomically: true, encoding: .utf8)
        return try #require(RunnerManager.find(id: Self.id))
    }

    private var label: String? {
        try? String(contentsOf: root.appendingPathComponent("label.txt"), encoding: .utf8)
    }

    // MARK: - Checking

    @Test("A runner checks out against the checksums recorded when it was installed")
    func recordedIsIntact() throws {
        let install = try runner()
        try RunnerIntegrity.record(install)
        #expect(RunnerIntegrity.check(install) == .intact)
    }

    @Test("A file changed after install is named as damage")
    func changedFileIsDamage() throws {
        let install = try runner()
        try RunnerIntegrity.record(install)
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: install.binDirectory.appendingPathComponent("wineserver"))
        #expect(RunnerIntegrity.check(install) == .damaged(["wine/bin/wineserver"]))
    }

    @Test("A recorded file that has gone is damage")
    func missingFileIsDamage() throws {
        let install = try runner()
        try RunnerIntegrity.record(install)
        try FileManager.default.removeItem(at: install.binDirectory.appendingPathComponent("wineserver"))
        #expect(RunnerIntegrity.check(install) == .damaged(["wine/bin/wineserver"]))
    }

    @Test("With no manifest, real programs pass and scripts where Wine belongs don't — the #190 runner")
    func noManifest() throws {
        #expect(RunnerIntegrity.check(try runner()) == .intact)
        let fake = Data("#!/bin/sh\n# Cellar's fake Wine: records the call, runs nothing.\nexit 0\n".utf8)
        #expect(RunnerIntegrity.check(try runner(fake)) == .damaged(["wine/bin/wine", "wine/bin/wineserver"]))
        #expect(RunnerIntegrity.check(try runner(Data())) == .damaged(["wine/bin/wine", "wine/bin/wineserver"]))
    }

    @Test("A runner folder whose wine has gone is damaged, not 'never installed'")
    func folderWithoutWine() throws {
        let install = try runner()
        try FileManager.default.removeItem(at: install.wineBinary)
        #expect(RunnerIntegrity.check(runnerID: Self.id) == .damaged(["wine/bin/wine"]))
    }

    @Test("A runner that was never installed is nobody's to repair")
    func neverInstalled() throws {
        TestHome.ensure()
        try? FileManager.default.removeItem(at: root)
        #expect(RunnerIntegrity.check(runnerID: Self.id) == nil)
        var installs = 0
        let repaired = try RunnerIntegrity.ensureIntact(runnerID: Self.id, install: { _, _ in
            installs += 1
            throw CellarError.ioFailure("should not be called")
        })
        #expect(!repaired && installs == 0)
    }

    // MARK: - Repairing

    @Test("An intact runner is left alone: nothing downloaded, nothing said")
    func intactIsLeftAlone() throws {
        try RunnerIntegrity.record(try runner())
        var installs = 0
        var phases: [InstallPhase] = []
        let repaired = try RunnerIntegrity.ensureIntact(runnerID: Self.id, update: { phases.append($0.phase) },
                                                        install: { _, _ in installs += 1; throw CellarError.ioFailure("no") })
        #expect(!repaired)
        #expect(installs == 0 && phases.isEmpty)
    }

    @Test("A damaged runner is replaced by a fresh one, says so, and the damaged copy is gone")
    func damagedIsRepaired() throws {
        try runner(Data("#!/bin/sh\nexit 0\n".utf8), label: "damaged")
        var phases: [InstallPhase] = []
        var lines: [String] = []
        let repaired = try RunnerIntegrity.ensureIntact(
            runnerID: Self.id, progress: { lines.append($0) }, update: { phases.append($0.phase) },
            install: { spec, _ in
                #expect(!FileManager.default.fileExists(atPath: root.path), "the damaged copy was set aside first")
                let fresh = try runner(label: "fresh")
                try RunnerIntegrity.record(fresh)
                #expect(spec.id == Self.id)
                return fresh
            })
        #expect(repaired)
        #expect(label == "fresh")
        #expect(phases == [.runtimeRepair])
        #expect(lines.contains { $0.contains("games and saves aren't touched") })
        let aside = (try? FileManager.default.contentsOfDirectory(atPath: Paths.cache.path)) ?? []
        #expect(!aside.contains { $0.hasPrefix("\(Self.id)-damaged-") }, "the damaged copy is deleted once the fresh one checks out")
        let install = try #require(RunnerManager.find(id: Self.id))
        #expect(RunnerIntegrity.check(install) == .intact)
    }

    @Test("A repair that can't download puts the old runner back and says to press Play again")
    func failedRepairRestores() throws {
        try runner(Data("#!/bin/sh\nexit 0\n".utf8), label: "damaged")
        do {
            try RunnerIntegrity.ensureIntact(runnerID: Self.id, install: { _, _ in
                throw CellarError.ioFailure("The Internet connection appears to be offline.")
            })
            Issue.record("expected the launch to stop")
        } catch {
            let message = "\(error)"
            #expect(message.contains("press Play again"))
            #expect(message.contains("offline"))
        }
        #expect(label == "damaged", "the player is never left with less than they had")
    }

    @Test("A fresh copy that fails its own check is not accepted")
    func freshCopyMustCheckOut() throws {
        try runner(Data("#!/bin/sh\nexit 0\n".utf8), label: "damaged")
        #expect(throws: CellarError.self) {
            try RunnerIntegrity.ensureIntact(runnerID: Self.id, install: { _, _ in
                try runner(Data("still a script".utf8), label: "bad fresh")
            })
        }
        #expect(label == "damaged")
    }

    // MARK: - The words

    @Test("The repair step reads as a repair, in the launch and in the sidebar")
    func wording() {
        #expect(InstallPhase.runtimeRepair.title(game: "Planet Coaster 2", store: .steam) == "Repairing the Windows runtime")
        #expect(InstallPhase.runtimeRepair.detail(store: .steam).contains("Your games and saves aren't touched"))
        #expect(GameActivity.working(InstallProgress(.runtimeRepair)).statusText == "Repairing")
    }
}
