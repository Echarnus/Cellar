import CellarDomain
import Foundation
import Testing
@testable import CellarData

/// `cellar perf measure`: the Metal HUD's log lines turned into a frame rate and a verdict on what
/// limits it. The verdict is the part a player acts on — told "the graphics card", they lower
/// settings; told "the processor", they don't bother — so a wrong one costs them an evening.
struct FrameStatsTests {

    /// A HUD line: `count` frames from `first`, each `interval` ms with `gpu` ms of GPU work.
    private func hud(_ first: Int, _ count: Int, interval: Double, gpu: Double, prefix: String = "") -> String {
        let pairs = (0..<count).map { _ in "\(interval),\(gpu)" }.joined(separator: ",")
        return "\(prefix)metal-HUD: \(first),412.5,1830.2,\(pairs)"
    }

    /// `seconds` consecutive lines of 60 frames each.
    private func run(seconds: Int, interval: Double, gpu: Double, from start: Int = 0, prefix: String = "") -> [String] {
        (0..<seconds).map { hud(start + $0 * 60, 60, interval: interval, gpu: gpu, prefix: prefix) }
    }

    @Test("A line parses into its first frame and interval / GPU-time pairs")
    func parsesLine() throws {
        let line = try #require(FrameStats.line("metal-HUD: 120,1,512.0,16.7,9.1,16.6,9.3"))
        #expect(line.firstFrame == 120)
        #expect(line.intervals == [16.7, 16.6])
        #expect(line.gpuTimes == [9.1, 9.3])
        #expect(line.pid == nil)
    }

    @Test("A unified-log line keeps the process id that wrote it")
    func parsesUnifiedLogPrefix() throws {
        let raw = "2026-10-30 21:14:03.512 Df wine64-preloader[4242:1a2b3c] metal-HUD: 60,0,700.1,22.0,12.0"
        let line = try #require(FrameStats.line(raw))
        #expect(line.pid == 4242)
        #expect(line.firstFrame == 60)
    }

    @Test("Lines that are not whole HUD lines are ignored, not half-trusted",
          arguments: ["", "Steam started", "metal-HUD:", "metal-HUD: 1,2,3", "metal-HUD: 1,2,3,16.7",
                      "metal-HUD: x,2,3,16.7,9", "metal-HUD: 1,2,3,16.7,9,16.6"])
    func rejectsPartialLines(_ raw: String) {
        #expect(FrameStats.line(raw) == nil)
    }

    @Test("A GPU busy for the whole frame is the limit")
    func gpuBound() throws {
        let stats = try #require(FrameStats.measure(run(seconds: 5, interval: 40, gpu: 38).joined(separator: "\n")))
        #expect(stats.limit == .gpu)
        #expect(abs(stats.averageFPS - 25) < 0.01)
        #expect(stats.frames == 300)
    }

    @Test("A GPU idle for most of the frame is waiting on the CPU — Planet Coaster 2's heavy park")
    func cpuBound() throws {
        // docs/RESEARCH.md: ~22 FPS (45 ms) with 26 ms of GPU time.
        let stats = try #require(FrameStats.measure(run(seconds: 5, interval: 45, gpu: 26).joined(separator: "\n")))
        #expect(stats.limit == .cpu)
        #expect(abs(stats.averageGPUMs - 26) < 0.01)
    }

    @Test("Sitting on a refresh rate with GPU to spare is a cap, not a CPU limit")
    func capped() throws {
        let stats = try #require(FrameStats.measure(run(seconds: 5, interval: 16.667, gpu: 6).joined(separator: "\n")))
        #expect(stats.limit == .capped)
    }

    @Test("The slowest 1% comes from the slowest frames, not the average")
    func onePercentLow() throws {
        var lines = run(seconds: 4, interval: 20, gpu: 10)
        // Four 100 ms hitches among 244 frames.
        lines.append(hud(240, 4, interval: 100, gpu: 10))
        let stats = try #require(FrameStats.measure(lines.joined(separator: "\n")))
        #expect(stats.onePercentLowFPS < 11)
        #expect(stats.averageFPS > 40)
    }

    @Test("Steam's own HUD lines in the same log do not get mixed into the game's")
    func picksTheGameOverSteam() throws {
        let game = run(seconds: 5, interval: 45, gpu: 26, prefix: "Df wine64-preloader[500:1] ")
        // Steam's tray window: a handful of frames a second, from a different process.
        let steam = (0..<5).map { hud($0 * 2, 2, interval: 500, gpu: 1, prefix: "Df wine64-preloader[400:1] ") }
        let mixed = zip(game, steam).flatMap { [$0.0, $0.1] }.joined(separator: "\n")
        let stats = try #require(FrameStats.measure(mixed))
        #expect(stats.frames == 300)
        #expect(stats.limit == .cpu)
    }

    @Test("A second run of the game in the same file starts a new stream instead of joining the first")
    func splitsRuns() throws {
        let first = run(seconds: 2, interval: 20, gpu: 19)          // 120 frames, GPU-bound
        let second = run(seconds: 4, interval: 45, gpu: 26)         // restarted at frame 0: 240 frames
        let stats = try #require(FrameStats.measure((first + second).joined(separator: "\n")))
        #expect(stats.frames == 240)
        #expect(stats.limit == .cpu)
    }

    @Test("Too few frames to say anything is no answer, not a wrong one")
    func tooFewFrames() {
        #expect(FrameStats.measure(hud(0, 10, interval: 16, gpu: 8)) == nil)
        #expect(FrameStats.measure("") == nil)
    }

    @Test("Intervals logged in seconds are read as seconds")
    func secondsUnits() throws {
        let stats = try #require(FrameStats.measure(run(seconds: 2, interval: 0.04, gpu: 0.038).joined(separator: "\n")))
        #expect(abs(stats.averageFPS - 25) < 0.01)
        #expect(stats.limit == .gpu)
    }

    @Test("Wherever the HUD is on, its log is on too — and an explicit choice is left alone")
    func hudTurnsOnLogging() {
        let wine = WineRunner(binary: URL(fileURLWithPath: "/nonexistent/wine"), prefix: URL(fileURLWithPath: "/tmp/p"))
        #expect(wine.environment(extra: ["MTL_HUD_ENABLED": "1"])["MTL_HUD_LOG_ENABLED"] == "1")
        #expect(wine.environment(extra: ["MTL_HUD_ENABLED": "0"])["MTL_HUD_LOG_ENABLED"] == nil)
        #expect(wine.environment()["MTL_HUD_LOG_ENABLED"] == nil)
        #expect(wine.environment(extra: ["MTL_HUD_ENABLED": "1", "MTL_HUD_LOG_ENABLED": "0"])["MTL_HUD_LOG_ENABLED"] == "0")
    }
}
