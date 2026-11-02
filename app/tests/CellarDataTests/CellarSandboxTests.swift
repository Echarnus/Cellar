import CellarDomain
import Foundation
import Testing
@testable import CellarData

/// A sandbox can never change the player's real installation (#204).
///
/// #190: the test home *linked* the real WineForge runner, FakeWine wrote through the link, and
/// every Play afterwards started nothing. These tests stand up a stand-in "real" installation in
/// scratch space (so a regression here can never touch the machine's actual one) and prove the
/// three rules: a sandbox never overlaps the real home, what it borrows is a clone that writes
/// can't escape, and a change to a real runner is caught and named.
@Suite struct CellarSandboxTests {
    /// A stand-in real installation with one runner whose `wine` is a recognisable program.
    private func realInstallation() throws -> URL {
        let real = TestHome.scratch("real-cellar")
        let bin = real.appendingPathComponent("runners/wineforge/wine/bin", isDirectory: true)
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        try Data("the real wine".utf8).write(to: bin.appendingPathComponent("wine"))
        try Data("the real wineserver".utf8).write(to: bin.appendingPathComponent("wineserver"))
        let unix = real.appendingPathComponent("runners/wineforge/wine/lib/wine/x86_64-unix", isDirectory: true)
        try FileManager.default.createDirectory(at: unix, withIntermediateDirectories: true)
        try Data("the real ntdll".utf8).write(to: unix.appendingPathComponent("ntdll.so"))
        try Data("a dll nobody guards".utf8).write(to: unix.appendingPathComponent("user32.so"))
        return real
    }

    private func contents(_ url: URL) -> String? {
        try? String(contentsOf: url, encoding: .utf8)
    }

    // MARK: - A sandbox never overlaps the real home

    @Test("A sandbox beside the real installation is accepted")
    func separateHome() throws {
        let real = try realInstallation()
        try CellarSandbox.requireSeparate(TestHome.scratch("sandbox"), realHome: real)
    }

    @Test("The real installation, a folder inside it, or a folder around it is refused")
    func overlappingHomes() throws {
        let real = try realInstallation()
        for home in [real, real.appendingPathComponent("runners"),
                     real.appendingPathComponent("not-made-yet/home"), real.deletingLastPathComponent()] {
            #expect(throws: CellarError.self, "\(home.path) overlaps the real home") {
                try CellarSandbox.requireSeparate(home, realHome: real)
            }
        }
    }

    @Test("A link that leads into the real installation is refused, even below a folder not made yet")
    func linkedHome() throws {
        let real = try realInstallation()
        let link = TestHome.scratch("linked").appendingPathComponent("home")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
        #expect(CellarSandbox.overlapsRealHome(link.appendingPathComponent("runners/wineforge/wine/bin/wine"),
                                               realHome: real))
        #expect(throws: CellarError.self) { try CellarSandbox.requireSeparate(link, realHome: real) }
    }

    @Test("This test run's own sandbox is separate from the machine's real Cellar")
    func thisRunIsSeparate() throws {
        try CellarSandbox.requireSeparate(Paths.appSupport)
        #expect(!CellarSandbox.overlapsRealHome(Paths.runners))
    }

    // MARK: - What a sandbox borrows is a clone

    @Test("Writing into a cloned runner leaves the real runner as it was — the #190 write, refused")
    func cloneIsIndependent() throws {
        let real = try realInstallation()
        let source = real.appendingPathComponent("runners/wineforge", isDirectory: true)
        let copy = TestHome.scratch("sandbox").appendingPathComponent("runners/wineforge", isDirectory: true)
        try CellarSandbox.clone(source, to: copy, realHome: real)

        #expect(!CellarSandbox.isSymbolicLink(copy), "a clone, not a link")
        let wine = copy.appendingPathComponent("wine/bin/wine")
        #expect(contents(wine) == "the real wine")
        // What FakeWine does to a runner it is handed.
        try Data("#!/bin/sh\n# Cellar's fake Wine: records the call, runs nothing.\nexit 0\n".utf8).write(to: wine)
        #expect(contents(source.appendingPathComponent("wine/bin/wine")) == "the real wine")
    }

    @Test("A link inside the borrowed tree that leads home becomes a copy of what it pointed at")
    func linksHomeAreDetached() throws {
        let real = try realInstallation()
        let source = TestHome.scratch("borrowed")
        try FileManager.default.createDirectory(at: source.appendingPathComponent("lib"), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: source.appendingPathComponent("lib/bin"),
            withDestinationURL: real.appendingPathComponent("runners/wineforge/wine/bin"))
        try Data("local".utf8).write(to: source.appendingPathComponent("lib/libfoo.1.dylib"))
        try FileManager.default.createSymbolicLink(atPath: source.appendingPathComponent("lib/libfoo.dylib").path,
                                                   withDestinationPath: "libfoo.1.dylib")

        let copy = TestHome.scratch("sandbox").appendingPathComponent("borrowed")
        try CellarSandbox.clone(source, to: copy, realHome: real)

        let bin = copy.appendingPathComponent("lib/bin")
        #expect(!CellarSandbox.isSymbolicLink(bin), "the link home was replaced")
        #expect(!CellarSandbox.overlapsRealHome(bin.appendingPathComponent("wine"), realHome: real))
        try Data("overwritten".utf8).write(to: bin.appendingPathComponent("wine"))
        #expect(contents(real.appendingPathComponent("runners/wineforge/wine/bin/wine")) == "the real wine")
        #expect(CellarSandbox.isSymbolicLink(copy.appendingPathComponent("lib/libfoo.dylib")),
                "a link that stays inside the copy is left alone")
    }

    @Test("Cloning into the real installation, or over something already there, is refused")
    func cloneRefusals() throws {
        let real = try realInstallation()
        let source = real.appendingPathComponent("runners/wineforge", isDirectory: true)
        #expect(throws: CellarError.self) {
            try CellarSandbox.clone(source, to: real.appendingPathComponent("runners/second"), realHome: real)
        }
        let taken = TestHome.scratch("sandbox")
        #expect(throws: CellarError.self) { try CellarSandbox.clone(source, to: taken, realHome: real) }
        #expect(!FileManager.default.fileExists(atPath: real.appendingPathComponent("runners/second").path))
    }

    // MARK: - A change to a real runner is caught and named

    @Test("A fingerprint covers what a runner starts from, and nothing else")
    func fingerprintCoversTheGuardedFiles() throws {
        let real = try realInstallation()
        let print = CellarSandbox.Fingerprint.of(runnersAt: real.appendingPathComponent("runners"))
        #expect(Set(print.files.keys) == ["wineforge/wine/bin/wine", "wineforge/wine/bin/wineserver",
                                          "wineforge/wine/lib/wine/x86_64-unix/ntdll.so"])
    }

    @Test("Changed, added and removed runner files are each named; an untouched runner has no changes")
    func fingerprintChanges() throws {
        let real = try realInstallation()
        let runners = real.appendingPathComponent("runners")
        let before = CellarSandbox.Fingerprint.of(runnersAt: runners)
        #expect(CellarSandbox.Fingerprint.of(runnersAt: runners).changes(since: before).isEmpty)

        let bin = runners.appendingPathComponent("wineforge/wine/bin")
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: bin.appendingPathComponent("wine"))
        try FileManager.default.removeItem(at: bin.appendingPathComponent("wineserver"))
        try Data("new".utf8).write(to: bin.appendingPathComponent("wine64"))

        #expect(CellarSandbox.Fingerprint.of(runnersAt: runners).changes(since: before) == [
            "wineforge/wine/bin/wine was changed",
            "wineforge/wine/bin/wine64 was added",
            "wineforge/wine/bin/wineserver was removed",
        ])
    }

    @Test("A folder of runners that isn't there fingerprints as empty")
    func missingRunners() {
        #expect(CellarSandbox.Fingerprint.of(runnersAt: TestHome.scratch().appendingPathComponent("none")).files.isEmpty)
    }
}
