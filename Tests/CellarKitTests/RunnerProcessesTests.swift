import CellarDomain
import Foundation
import Testing
@testable import CellarKit

/// Quitting a game has to take its Wine with it: Planet Coaster 2 was quit and three `wine`
/// processes stayed in Activity Monitor. What is left after the bottle's wineserver is gone is found
/// by executable path, and stopped only when no server of that runner is still up — a process with a
/// live server may be another bottle's game.
struct RunnerProcessesTests {
    private let root = "/Users/me/Library/Application Support/Cellar/runners/wineforge"

    @Test("With no wineserver left, every process running the runner's binaries is left over")
    func orphansAreFound() {
        let entries = [
            RunnerProcesses.Entry(pid: 501, path: "\(root)/bin/wine"),
            RunnerProcesses.Entry(pid: 502, path: "\(root)/bin/wine-preloader"),
            RunnerProcesses.Entry(pid: 503, path: "/System/Applications/Utilities/Activity Monitor.app/Contents/MacOS/Activity Monitor"),
            // A sibling directory that merely starts with the same name is another runner.
            RunnerProcesses.Entry(pid: 504, path: "\(root)-old/bin/wine"),
        ]
        #expect(RunnerProcesses.leftovers(entries, root: root) == [501, 502])
        #expect(RunnerProcesses.leftovers(entries, root: root + "/") == [501, 502])
    }

    @Test("While a wineserver of the same runner is up, nothing is touched")
    func aLiveServerProtectsEverything() {
        let entries = [
            RunnerProcesses.Entry(pid: 501, path: "\(root)/bin/wine"),
            RunnerProcesses.Entry(pid: 600, path: "\(root)/bin/wineserver"),
        ]
        #expect(RunnerProcesses.leftovers(entries, root: root).isEmpty)
    }

    @Test("Another runner's wineserver does not protect this runner's orphans")
    func otherRunnersDoNotCount() {
        let entries = [
            RunnerProcesses.Entry(pid: 501, path: "\(root)/bin/wine"),
            RunnerProcesses.Entry(pid: 700, path: "/Users/me/Library/Application Support/Cellar/runners/sikarugir/bin/wineserver"),
        ]
        #expect(RunnerProcesses.leftovers(entries, root: root) == [501])
    }

    @Test("Nothing is left over in an empty listing")
    func empty() {
        #expect(RunnerProcesses.leftovers([], root: root).isEmpty)
    }

    @Test("The live listing sees this test process, by the binary it runs")
    func liveListingFindsItself() throws {
        // Proves the libproc wiring: a listing that came back empty would make every sweep a no-op
        // and every "the layer is down" claim untested.
        let me = try #require(RunnerProcesses.running().first { $0.pid == getpid() })
        let expected = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath().lastPathComponent
        #expect(URL(fileURLWithPath: me.path).lastPathComponent == expected)
    }

    @Test("A sweep never stops the process doing the sweeping")
    func neverItself() {
        let me = RunnerProcesses.Entry(pid: getpid(), path: "\(root)/bin/wine")
        #expect(RunnerProcesses.leftovers([me], root: root).isEmpty)
    }

    @Test("A Steam game started beside the client says so in the log")
    func steamAlongsideRoute() {
        let route = LaunchRoute.steamAlongside(exeName: "PlanetCoaster2.exe", appID: 2688950)
        #expect(route.logDescription.contains("Steam"))
        #expect(route.logDescription.contains("PlanetCoaster2.exe"))
    }
}
