import Foundation
import Testing
@testable import CellarKit

/// Watching Windows processes through `ps`. The one thing that has to be right is *not* mistaking
/// something that merely mentions a game for the game itself — a supervised launch decides whether
/// to retry on this answer, so a false "it's alive" is a dead game reported as running.
struct ProcessWatchTests {

    @Test("A crash reporter carrying the game's path is not the game running")
    func crashReporterIsNotTheGame() {
        // Verbatim shape of a real Planet Coaster 2 crash on this Mac: the reporter is handed the
        // game's own exe path, so a plain substring match on "PlanetCoaster2.exe" matches it.
        let reporter = #"crash_reporter.exe -quiet=false -platformid Steam -parentpath C:\Games\planet-coaster-2\PlanetCoaster2.exe -endpoint https://…"#
        #expect(reporter.contains("PlanetCoaster2.exe"), "the reporter really does carry the name")
        #expect(ProcessWatch.impostors.contains { reporter.lowercased().contains($0.lowercased()) },
                "so it has to be excluded by name, or a crashed game reads as a live one")
    }

    @Test("The game's own command line is not excluded by any impostor")
    func theGameItselfStillCounts() {
        let game = #"C:\Games\planet-coaster-2\PlanetCoaster2.exe"#
        #expect(!ProcessWatch.impostors.contains { game.lowercased().contains($0.lowercased()) })
    }

    @Test("Nothing Cellar looks for is running in a test process")
    func nothingIsRunning() {
        // Also proves the shell pipeline is well-formed: a malformed one would exit non-zero for
        // every needle and every "is it running" answer in Cellar would silently become "no".
        #expect(!ProcessWatch.isRunning("cellar-a-needle-that-matches-nothing-\(UUID().uuidString)"))
        #expect(ProcessWatch.isRunning("launchd"), "a process that is always there must still be found")
    }
}
