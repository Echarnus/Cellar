import CellarDomain
import Foundation
import Testing
@testable import CellarData

/// Tier A: the integration sandbox borrows a runner the way the Wine tiers do, and a write into
/// the borrowed copy stays in the copy (#204).
///
/// This is the #190 sequence end to end, with a stand-in for the player's runner in scratch space:
/// the runner is cloned into the sandbox's `runners/`, found and recorded by `RunnerManager` and
/// `RunnerIntegrity` exactly like a real install, overwritten with a fake `wine`, and then the
/// sandbox copy reads as damaged (so `cloneRealRunners` replaces it) while the original's bytes
/// and fingerprint are untouched.
@Suite(.serialized)
struct SandboxIsolationTests {
    static let machO = Data([0xCF, 0xFA, 0xED, 0xFE] + [UInt8](repeating: 0, count: 60))

    @Test("A fake Wine written into a cloned runner damages the clone and never the original")
    func fakeWineStaysInTheClone() throws {
        IT.ensure()
        let fm = FileManager.default
        let id = RunnerCatalog.sikarugir.id

        // The stand-in for the player's runner, outside the sandbox's own runners folder.
        let realRunners = IT.scratch("real-runners")
        let original = realRunners.appendingPathComponent(id, isDirectory: true)
        let bin = original.appendingPathComponent("wine/bin", isDirectory: true)
        try fm.createDirectory(at: bin, withIntermediateDirectories: true)
        for name in ["wine", "wineserver"] {
            try Self.machO.write(to: bin.appendingPathComponent(name))
            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: bin.appendingPathComponent(name).path)
        }
        let before = CellarSandbox.Fingerprint.of(runnersAt: realRunners)

        let copy = Paths.runners.appendingPathComponent(id, isDirectory: true)
        try? fm.removeItem(at: copy)
        defer { try? fm.removeItem(at: copy) }
        try CellarSandbox.clone(original, to: copy, realHome: realRunners)

        let install = try #require(RunnerManager.find(id: id), "the clone is a runner Cellar can find")
        try RunnerIntegrity.record(install)
        #expect(RunnerIntegrity.check(install) == .intact)

        try Data("#!/bin/sh\n# Cellar's fake Wine: records the call, runs nothing.\nexit 0\n".utf8)
            .write(to: install.wineBinary)

        #expect(RunnerIntegrity.check(install) == .damaged(["wine/bin/wine"]),
                "the sandbox copy is seen as damaged, so the next Wine tier clones it again")
        #expect(try Data(contentsOf: bin.appendingPathComponent("wine")) == Self.machO)
        #expect(CellarSandbox.Fingerprint.of(runnersAt: realRunners).changes(since: before).isEmpty,
                "the original runner is exactly as it was")
    }
}
