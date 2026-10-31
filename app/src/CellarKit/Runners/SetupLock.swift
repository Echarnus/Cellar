import CellarDomain
import Foundation

/// One Cellar setting up shared parts at a time, across processes.
///
/// The app prepares in the background and the player can press Install on a game a second later;
/// both are separate `cellar` processes, and both would otherwise download the same runner into the
/// same directory at once. An advisory `flock` on a file in Cellar's folder serialises them. The
/// kernel drops it when the process exits, however it exits, so a crash never leaves it held.
public enum SetupLock {
    static var file: URL { Paths.appSupport.appendingPathComponent(".setup.lock") }
    nonisolated(unsafe) private static var depth = 0

    /// Run `body` holding the lock, waiting for it if another process has it — and saying so through
    /// `waiting`, because a silent pause looks like a hang (skills/ux.md).
    public static func withLock<T>(waiting: (String) -> Void = { _ in }, _ body: () throws -> T) throws -> T {
        // Re-entrant within one process: a second open() of the file is a second lock owner, and
        // would wait forever on the first. The CLI does its setup work on one thread.
        if depth > 0 { return try body() }
        depth += 1
        defer { depth -= 1 }
        try FileManager.default.createDirectory(at: Paths.appSupport, withIntermediateDirectories: true)
        let fd = open(file.path, O_CREAT | O_RDWR, 0o644)
        guard fd >= 0 else { return try body() }  // no lock is better than no setup
        defer { close(fd) }
        if flock(fd, LOCK_EX | LOCK_NB) != 0 {
            waiting("Waiting for Cellar to finish downloading the parts every game shares…")
            _ = flock(fd, LOCK_EX)
        }
        defer { _ = flock(fd, LOCK_UN) }
        return try body()
    }
}
