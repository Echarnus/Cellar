import Foundation

/// Observing Windows processes from the macOS side.
///
/// Wine reports a process's *Windows* command line to `ps`, and that command line carries no hint
/// of which bottle it belongs to. So everything here matches on substrings of the command line —
/// an exe name, an install directory — and is bottle-blind by construction. Callers that need
/// per-bottle certainty must pick a needle that only one bottle could produce.
public enum ProcessWatch {
    /// Whether any process's command line contains `needle` (case-insensitive, literal).
    public static func isRunning(_ needle: String) -> Bool {
        Shell.run("/bin/sh", ["-c", "ps -axo command | grep -vi grep | grep -qiF \"\(needle)\""]).succeeded
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
    public static func superviseStart(attempts: Int,
                                      appearSeconds: Int = 24,
                                      settleSeconds: Int = 16,
                                      backoffSeconds: TimeInterval = 8,
                                      cleanup: () -> Void,
                                      start: () throws -> Void,
                                      isUp: () -> Bool,
                                      progress: (String) -> Void = { _ in }) throws {
        for attempt in 1...max(1, attempts) {
            cleanup()
            if attempt > 1 { Thread.sleep(forTimeInterval: backoffSeconds) }

            try start()

            var appeared = false
            let appearDeadline = Date().addingTimeInterval(TimeInterval(appearSeconds))
            while Date() < appearDeadline {
                Thread.sleep(forTimeInterval: 2)
                if isUp() { appeared = true; break }
            }
            if !appeared {
                progress("Attempt \(attempt): the game didn't start; retrying…")
                continue
            }

            var survived = true
            let settleDeadline = Date().addingTimeInterval(TimeInterval(settleSeconds))
            while Date() < settleDeadline {
                Thread.sleep(forTimeInterval: 2)
                if !isUp() { survived = false; break }
            }
            if survived {
                if attempt > 1 { progress("Up after \(attempt) attempts.") }
                return
            }
            progress("Attempt \(attempt): hit the D3DMetal startup race; cleaning up and retrying…")
        }
        throw CellarError.ioFailure(
            "The game kept failing to stay up after \(attempts) attempts. Try launching again.")
    }
}
