import Foundation
#if canImport(Darwin)
import Darwin   // libproc: proc_listallpids, proc_pidpath
#endif

/// Observing Windows processes from the macOS side.
///
/// Wine reports a process's *Windows* command line to `ps`, and that command line carries no hint
/// of which bottle it belongs to. So everything here matches on substrings of the command line —
/// an exe name, an install directory — and is bottle-blind by construction. Callers that need
/// per-bottle certainty must pick a needle that only one bottle could produce.
public enum ProcessWatch {
    /// Processes that *mention* a game without being it. A crash reporter is started with the game's
    /// own path on its command line (`crash_reporter.exe … -parentpath C:\…\PlanetCoaster2.exe`), so
    /// a plain name match sees it and reports the game alive **after** it has died — which is exactly
    /// when a supervised launch needs to know otherwise. Measured on a real Planet Coaster 2 crash.
    static let impostors = ["crash_reporter.exe", "steamerrorreporter", "winedbg", "wineboot"]

    /// Whether any process's command line contains `needle` (case-insensitive, literal), ignoring
    /// the impostors above.
    public static func isRunning(_ needle: String) -> Bool {
        let excluded = impostors.map { "| grep -viF \"\($0)\" " }.joined()
        return Shell.run("/bin/sh", ["-c",
            "ps -axo command | grep -vi grep | grep -iF \"\(needle)\" \(excluded)| grep -q ."]).succeeded
    }

    /// Whether any of `needles` matches. Used where one thing has several possible spellings
    /// (a Windows path and its unix twin, a launcher and the client it bootstraps).
    public static func isRunningAny(_ needles: [String]) -> Bool {
        needles.contains { isRunning($0) }
    }

    /// Wait for a match to appear. Returns false if it never does.
    @discardableResult
    public static func waitToAppear(_ needles: [String], seconds: Int, poll: TimeInterval = 2) -> Bool {
        let deadline = Date().addingTimeInterval(TimeInterval(seconds))
        while Date() < deadline {
            if isRunningAny(needles) { return true }
            Thread.sleep(forTimeInterval: poll)
        }
        return isRunningAny(needles)
    }

    /// Wait for every match to be gone. Gives it `graceSeconds` to appear first, so we never
    /// return before the thing we are waiting on has actually started.
    public static func waitToExit(_ needles: [String], graceSeconds: Int = 15) {
        waitToAppear(needles, seconds: graceSeconds, poll: 1)
        while isRunningAny(needles) { Thread.sleep(forTimeInterval: 3) }
    }

    /// SIGKILL everything matching, and don't care whether anything was there.
    public static func kill(_ needles: [String]) {
        for needle in needles {
            Shell.run("/usr/bin/pkill", ["-9", "-f", needle])
        }
    }

    /// Start something that may lose a startup race, and keep trying until it stays up.
    ///
    /// D3DMetal 3.0 has an intermittent race that fast-fails a game a few seconds in, before its
    /// window ever appears. The cure is mechanical: clean up, start again, and only believe the
    /// game is running once it has survived a settling period. Both store launch paths funnel
    /// through here so "launch and play" behaves the same whichever client is involved.
    ///
    /// - Parameters:
    ///   - cleanup: kill leftovers from a failed attempt (runs before every attempt).
    ///   - start:   ask the store client to launch the game.
    ///   - isUp:    whether the game's own process is alive.
    ///   - appearSeconds: how long to wait for it to show up at all.
    ///   - settleSeconds: how long it must then stay up to count as launched.
    ///   - stage: coarse step reporting for the app's launch window; a retry legitimately goes back
    ///     to `.starting`, which is what makes a second attempt visible rather than a stall.
    public static func superviseStart(attempts: Int,
                                      appearSeconds: Int = 24,
                                      settleSeconds: Int = 16,
                                      backoffSeconds: TimeInterval = 8,
                                      cleanup: () -> Void,
                                      start: () throws -> Void,
                                      isUp: () -> Bool,
                                      progress: (String) -> Void = { _ in },
                                      stage: (LaunchStage) -> Void = { _ in }) throws {
        for attempt in 1...max(1, attempts) {
            cleanup()
            if attempt > 1 { Thread.sleep(forTimeInterval: backoffSeconds) }

            stage(.starting)
            try start()
            stage(.waiting)

            var appeared = false
            let appearDeadline = Date().addingTimeInterval(TimeInterval(appearSeconds))
            while Date() < appearDeadline {
                Thread.sleep(forTimeInterval: 2)
                if isUp() { appeared = true; break }
            }
            if !appeared {
                progress("Attempt \(attempt): the game didn't start; retrying…")
                CellarLog.warn(.launch, "Start attempt \(attempt) of \(attempts): the game's process "
                    + "never appeared within \(appearSeconds)s. Retrying.")
                continue
            }

            var survived = true
            let settleDeadline = Date().addingTimeInterval(TimeInterval(settleSeconds))
            while Date() < settleDeadline {
                Thread.sleep(forTimeInterval: 2)
                if !isUp() { survived = false; break }
            }
            if survived {
                if attempt > 1 {
                    progress("Up after \(attempt) attempts.")
                    CellarLog.info(.launch, "The game stayed up on attempt \(attempt).")
                }
                return
            }
            progress("Attempt \(attempt): hit the D3DMetal startup race; cleaning up and retrying…")
            CellarLog.warn(.launch, "Start attempt \(attempt) of \(attempts): the game appeared and then "
                + "died inside \(settleSeconds)s — the D3DMetal startup race. Cleaning up and retrying.")
        }
        CellarLog.error(.launch, "Gave up: the game would not stay up after \(attempts) attempts.")
        throw CellarError.ioFailure(
            "The game kept failing to stay up after \(attempts) attempts. Try launching again.")
    }
}

/// The processes running a Wine runner's own binaries, found by the executable the kernel started
/// rather than by command line.
///
/// Wine rewrites a process's arguments to its Windows command line, so `ps` shows
/// `C:\…\steam.exe` with no trace of Wine — while Activity Monitor still shows the same process as
/// `wine`. The executable path is the one thing that does not change: `<runner>/bin/wine`,
/// `<runner>/bin/wineserver`. That makes this the one view of Wine's processes that does not depend
/// on what a game calls itself, and the right one for "is anything of the layer still running".
public enum RunnerProcesses {
    public struct Entry: Equatable, Sendable {
        public let pid: pid_t
        public let path: String
        public init(pid: pid_t, path: String) { self.pid = pid; self.path = path }
    }

    /// Stop what a runner left behind once its bottle's wineserver is gone; returns what was stopped.
    @discardableResult
    public static func sweep(root: URL) -> [pid_t] {
        let pids = leftovers(running(), root: root.resolvingSymlinksInPath().path)
        for pid in pids { kill(pid, SIGKILL) }
        return pids
    }

    /// Which of `entries` are left behind and safe to stop: every process whose executable lives
    /// under `root` — but none at all while a wineserver of that runner is still up.
    ///
    /// A Wine process cannot be told apart by bottle from outside. One whose server is gone is an
    /// orphan whichever bottle it came from; one with a live server may be another bottle's game,
    /// or a setup halfway through, and is not Cellar's to stop.
    static func leftovers(_ entries: [Entry], root: String) -> [pid_t] {
        let base = root.hasSuffix("/") ? root : root + "/"
        let ours = entries.filter { $0.path.hasPrefix(base) && $0.pid != getpid() }
        if ours.contains(where: { ($0.path as NSString).lastPathComponent == "wineserver" }) { return [] }
        return ours.map(\.pid)
    }

    /// Every process this user can see, with the path of the binary it runs.
    static func running() -> [Entry] {
        let count = proc_listallpids(nil, 0)
        guard count > 0 else { return [] }
        // Room for processes started between the two calls.
        var pids = [pid_t](repeating: 0, count: Int(count) + 32)
        let filled = pids.withUnsafeMutableBytes { proc_listallpids($0.baseAddress, Int32($0.count)) }
        guard filled > 0 else { return [] }
        var path = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        return pids.prefix(Int(filled)).compactMap { pid in
            guard pid > 0 else { return nil }
            let length = proc_pidpath(pid, &path, UInt32(path.count))
            guard length > 0 else { return nil }
            let bytes = path.prefix(Int(length)).map { UInt8(bitPattern: $0) }
            return Entry(pid: pid, path: String(decoding: bytes, as: UTF8.self))
        }
    }
}
