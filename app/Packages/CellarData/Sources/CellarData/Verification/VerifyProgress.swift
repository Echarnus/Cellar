import CellarDomain
import Foundation

/// How far a `cellar verify` has got, shared with whatever may have to stop it at once (#270).
///
/// A second Ctrl-C, or the kill that follows a first one from whatever started verify, used to
/// end the process on the spot: the bottle's Steam and wineserver stayed up, and the report still
/// said "still running" about the run under way. `VerifyGame.stopNow()` reads this from the
/// signal handler's thread while `run()` writes it, so every field is behind a lock.
public final class VerifyProgress: @unchecked Sendable {
    private let lock = NSLock()
    private var _folder: URL?
    private var _started = Date()
    private var _checks: [VerificationCheck] = []
    private var _attachments: [String] = []
    private var _run: Int?
    private var _completed = 0
    private var _abandoned = false

    public init() {}

    private func locked<T>(_ body: () -> T) -> T {
        lock.lock(); defer { lock.unlock() }
        return body()
    }

    /// Where the report goes, and when verify began.
    func begin(folder: URL, started: Date) { locked { _folder = folder; _started = started } }

    /// Run `number` has started.
    func starting(run number: Int) { locked { _run = number } }

    /// Run `number` is done and closed down, with what it found.
    func finished(run number: Int, checks: [VerificationCheck], attachments: [String]) {
        locked { _checks = checks; _attachments = attachments; _completed = number; _run = nil }
    }

    /// Verify was stopped at once: from here on `run()` writes no report over the one `stopNow` wrote.
    /// True only for the first caller.
    func abandon() -> Bool { locked { defer { _abandoned = true }; return !_abandoned } }

    public var isAbandoned: Bool { locked { _abandoned } }

    struct Snapshot {
        var folder: URL?
        var started: Date
        var checks: [VerificationCheck]
        var attachments: [String]
        var run: Int?
        var completed: Int
    }

    var snapshot: Snapshot {
        locked { Snapshot(folder: _folder, started: _started, checks: _checks, attachments: _attachments,
                          run: _run, completed: _completed) }
    }
}
