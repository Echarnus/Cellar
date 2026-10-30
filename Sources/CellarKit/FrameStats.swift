import Foundation

/// A game's frame rate, measured rather than eyeballed — read back from the Metal performance HUD's
/// own log.
///
/// With `MTL_HUD_ENABLED=1` and `MTL_HUD_LOG_ENABLED=1`, Metal writes one line a second per process:
///
///     metal-HUD: <first frame>,<field>,<field>,<interval>,<gpu time>,<interval>,<gpu time>,…
///
/// — the frame number the line starts at, two bookkeeping fields (memory, or missed frames: Apple's
/// two documents disagree, and Cellar reads neither), then one present-interval / GPU-time pair per
/// frame, in milliseconds. That is enough to say the thing a player actually needs to know: not just
/// how fast, but *what is holding it back*. The GPU time against the frame time answers it — a GPU
/// busy for the whole frame is the limit; a GPU idle for half of it is waiting on the CPU, which for
/// a translated Windows game means Rosetta and the draw calls, and no graphics setting will move it.
/// (Measured by hand for Planet Coaster 2 in docs/RESEARCH.md; this makes it a command.)
public struct FrameStats: Equatable, Sendable {
    /// What limits the frame rate. Decided from the GPU's share of the frame time.
    public enum Limit: String, Equatable, Sendable {
        /// The GPU is busy for (nearly) the whole frame.
        case gpu
        /// The GPU finishes early and waits: the CPU side — game logic, translation, draw calls.
        case cpu
        /// Held at a display refresh rate by vsync or the game's own frame cap.
        case capped
        /// Somewhere between the two; neither side clearly dominates.
        case balanced
    }

    public let frames: Int
    public let averageFPS: Double
    /// The frame rate of the slowest 1% of frames — the stutter a player feels.
    public let onePercentLowFPS: Double
    public let averageFrameMs: Double
    public let averageGPUMs: Double
    public let limit: Limit

    /// GPU time as a share of frame time, 0…1.
    public var gpuShare: Double { averageFrameMs > 0 ? min(averageGPUMs / averageFrameMs, 1) : 0 }

    /// Fewer frames than this and the numbers are noise (a loading screen, a menu flicker).
    static let minimumFrames = 30
    /// GPU busy for this share of the frame or more: the GPU is the limit.
    static let gpuBoundShare = 0.85
    /// GPU busy for this share or less: it is waiting for the CPU.
    static let cpuBoundShare = 0.6
    /// Refresh rates a vsync'd or frame-capped game settles on.
    static let refreshRates: [Double] = [30, 60, 120, 144]

    /// One parsed `metal-HUD:` line.
    struct Line: Equatable {
        let firstFrame: Int
        let intervals: [Double]
        let gpuTimes: [Double]
        /// The process that wrote it, when the source says (the unified log does, a stderr file does not).
        let pid: Int?
    }

    /// Parse one line, wherever it came from: a `log show` line with its timestamp and
    /// `process[pid:tid]` prefix, or the bare line a stderr log holds. Anything else is `nil`.
    static func line(_ raw: String) -> Line? {
        guard let marker = raw.range(of: "metal-HUD:") else { return nil }
        let fields = raw[marker.upperBound...]
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
        guard fields.count >= 5, let first = Int(fields[0]) else { return nil }
        let values = fields.dropFirst(3).map { Double($0) }
        // Pairs only; a line cut off mid-write (odd count, or a non-number) is dropped whole rather
        // than half-trusted.
        guard values.count >= 2, values.count % 2 == 0, !values.contains(where: { $0 == nil }) else { return nil }
        let numbers = values.compactMap { $0 }
        var intervals: [Double] = []
        var gpu: [Double] = []
        var index = 0
        while index + 1 < numbers.count {
            intervals.append(numbers[index])
            gpu.append(numbers[index + 1])
            index += 2
        }
        return Line(firstFrame: first, intervals: intervals, gpuTimes: gpu, pid: pid(in: raw[..<marker.lowerBound]))
    }

    /// `wine64-preloader[4242:1a2b3c]` → 4242.
    private static func pid(in prefix: Substring) -> Int? {
        guard let range = prefix.range(of: #"\[(\d+):"#, options: .regularExpression) else { return nil }
        return Int(prefix[range].dropFirst().dropLast())
    }

    /// Statistics for the game in `text`, or `nil` when it holds too few frames to say anything.
    ///
    /// The text can hold more than one process — Steam's own windows draw through Metal and get the
    /// same HUD, since the HUD variables are set on the client the game inherits them from — and
    /// more than one run of the game. Lines are chained into streams by frame number (each line
    /// starts where the last one stopped), split by process where the source names one, and the
    /// stream with the most frames is the game: it draws every frame, Steam's tray window almost never.
    public static func measure(_ text: String) -> FrameStats? {
        let lines = text.split(whereSeparator: \.isNewline).compactMap { line(String($0)) }
        guard let stream = longestStream(lines) else { return nil }
        return summarise(intervals: stream.flatMap(\.intervals), gpuTimes: stream.flatMap(\.gpuTimes))
    }

    static func longestStream(_ lines: [Line]) -> [Line]? {
        var streams: [[Line]] = []
        for line in lines {
            // Continue the stream this line follows on from: same process when known, and starting
            // at (or a little after — the HUD may skip a frame between lines) where that one ended.
            let next = streams.lastIndex { (stream: [Line]) -> Bool in
                guard let last = stream.last, last.pid == line.pid else { return false }
                let expected = last.firstFrame + last.intervals.count
                return line.firstFrame >= expected && line.firstFrame <= expected + max(last.intervals.count, 2)
            }
            if let next { streams[next].append(line) } else { streams.append([line]) }
        }
        return streams.max { (a: [Line], b: [Line]) -> Bool in
            a.reduce(0) { $0 + $1.intervals.count } < b.reduce(0) { $0 + $1.intervals.count }
        }
    }

    static func summarise(intervals rawIntervals: [Double], gpuTimes rawGPU: [Double]) -> FrameStats? {
        // A zero interval is the HUD's first frame, not a frame that took no time.
        let pairs = zip(rawIntervals, rawGPU).filter { $0.0 > 0 }
        guard pairs.count >= minimumFrames else { return nil }
        var intervals = pairs.map { $0.0 }
        var gpu = pairs.map { $0.1 }
        // Documented as milliseconds. Should a build ever log seconds, every frame would read as
        // under a millisecond — no game runs at 1000+ FPS through Wine, so take that as seconds.
        if median(intervals) < 1 {
            intervals = intervals.map { $0 * 1000 }
            gpu = gpu.map { $0 * 1000 }
        }
        let frameMs = intervals.reduce(0, +) / Double(intervals.count)
        let gpuMs = gpu.reduce(0, +) / Double(gpu.count)
        // The 99th-percentile frame time, as an FPS: what the slowest 1% of frames run at.
        let sorted = intervals.sorted()
        let slow = sorted[min(sorted.count - 1, Int((Double(sorted.count) * 0.99).rounded(.down)))]
        let fps = 1000 / frameMs
        return FrameStats(frames: intervals.count, averageFPS: fps, onePercentLowFPS: 1000 / slow,
                          averageFrameMs: frameMs, averageGPUMs: gpuMs,
                          limit: limit(fps: fps, frameMs: frameMs, gpuMs: gpuMs))
    }

    static func limit(fps: Double, frameMs: Double, gpuMs: Double) -> Limit {
        let share = frameMs > 0 ? gpuMs / frameMs : 0
        if share >= gpuBoundShare { return .gpu }
        // Sitting right on a refresh rate with GPU to spare is a cap, not a CPU limit: vsync makes
        // the frame wait for the display, and that wait looks exactly like an idle GPU.
        if refreshRates.contains(where: { abs(fps - $0) / $0 < 0.03 }) { return .capped }
        return share <= cpuBoundShare ? .cpu : .balanced
    }

    private static func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        return sorted.isEmpty ? 0 : sorted[sorted.count / 2]
    }
}

extension FrameStats {
    /// Where the HUD's lines end up. Apple documents the format, not the destination, so Cellar
    /// looks in both places it can be: the unified log, and the stderr of the process that launched
    /// the game (`Paths.logs`, where every client and game launch is written).
    public enum Source {
        /// `log show` for the last `seconds` seconds — the lines Metal sent to the system log.
        public static func unifiedLog(seconds: Int) -> String {
            Shell.run("/usr/bin/log", ["show", "--last", "\(seconds)s", "--style", "compact",
                                       "--predicate", #"eventMessage CONTAINS "metal-HUD:""#]).stdout
        }

        /// The launch logs Cellar wrote for this bottle and game, if they were written to within the
        /// last `seconds` — an older file is an earlier session, and its numbers would mislead.
        public static func launchLogs(bottle: String, slug: String, seconds: Int, now: Date = Date()) -> String {
            let names = ["steam-\(bottle).log", "battlenet-\(bottle).log", "game-\(slug).log"]
            return names.compactMap { name -> String? in
                let url = Paths.logs.appendingPathComponent(name)
                guard let modified = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date,
                      now.timeIntervalSince(modified) <= Double(seconds),
                      let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
                // One HUD line a second: the tail holds the window asked for, and old runs further up
                // must not be chained into it.
                let hud = text.split(whereSeparator: \.isNewline).filter { $0.contains("metal-HUD:") }
                return hud.suffix(seconds).joined(separator: "\n")
            }.joined(separator: "\n")
        }
    }
}
