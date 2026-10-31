import Foundation
@testable import CellarKit

/// A Wine runner that records instead of translating — the test double for the layer.
///
/// Cellar's launch path ends in a `Process` started from the runner's `wine`, and a hermetic test
/// cannot run real Wine. So the sandbox's stub runner gets a `wine` and a `wineserver` that are
/// shell scripts: each call appends its tool, its arguments and the Wine-relevant part of its
/// environment to a log, and does nothing else. That is enough to prove what Cellar *hands* Wine —
/// the exe, the prefix, the locale, the profile's `[env]` — and to watch the lifecycle around it,
/// on every PR, with no runner and no Rosetta. Whether Wine then runs a Windows program is tier B's
/// question (`docs/TESTING.md`), not this one's.
///
/// A call whose first argument is an `.exe` stays alive for as many seconds as the file
/// `<exe>.lifetime` says, so the process a launch waits for is really there to be found by
/// `ProcessWatch`, and really goes away to be waited out. The scripts are a superset of
/// `TestHome.installStubRunner`'s `exit 0`, so a suite that only needs a runner on disk is
/// unaffected by this one having run first.
enum FakeWine {
    struct Call {
        let tool: String
        let arguments: [String]
        let environment: [String: String]
    }

    static var log: URL { TestHome.ensure().appendingPathComponent("fake-wine-calls.log") }

    /// Turn the sandbox's stub runner into the recording double, and return it.
    @discardableResult
    static func install() throws -> RunnerInstall {
        guard let install = TestHome.installStubRunner() else {
            throw CellarError.ioFailure("The sandbox has no stub runner to turn into a fake Wine.")
        }
        try write(script(tool: "wine"), to: install.wineBinary)
        try write(script(tool: "wineserver"), to: install.binDirectory.appendingPathComponent("wineserver"))
        return install
    }

    /// Forget every call recorded so far.
    static func reset() {
        try? FileManager.default.removeItem(at: log)
    }

    /// Every call since the last `reset`, oldest first.
    static func calls() -> [Call] {
        guard let text = try? String(contentsOf: log, encoding: .utf8) else { return [] }
        return text.components(separatedBy: "--- call ").dropFirst().map { block in
            let lines = block.components(separatedBy: "\n")
            var arguments: [String] = []
            var environment: [String: String] = [:]
            for line in lines.dropFirst() {
                if line.hasPrefix("arg=") {
                    arguments.append(String(line.dropFirst(4)))
                } else if let equals = line.firstIndex(of: "=") {
                    environment[String(line[..<equals])] = String(line[line.index(after: equals)...])
                }
            }
            return Call(tool: lines.first ?? "", arguments: arguments, environment: environment)
        }
    }

    /// Make the fake game at `exe` stay up for `seconds` once Wine is asked to run it.
    static func keepAlive(_ exe: URL, seconds: Int) throws {
        try "\(seconds)".write(to: URL(fileURLWithPath: exe.path + ".lifetime"), atomically: true, encoding: .utf8)
    }

    private static func script(tool: String) -> String {
        """
        #!/bin/sh
        # Cellar's fake Wine (Tests/CellarKitTests/Support/FakeWine.swift): records the call, runs nothing.
        {
          echo "--- call \(tool)"
          for arg in "$@"; do echo "arg=$arg"; done
          env | grep -E '^(WINE|LANG=|LC_ALL=|GRAPHICS_BACKEND=|CELLAR_|FIXTURE_)'
        } >> '\(log.path)'
        case "$1" in
          *.exe) if [ -f "$1.lifetime" ]; then sleep "$(cat "$1.lifetime")"; fi ;;
        esac
        exit 0

        """
    }

    private static func write(_ script: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try script.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }
}
