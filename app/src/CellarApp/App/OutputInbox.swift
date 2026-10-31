import Foundation

/// Where a command's output waits between the pipe's reader thread and the main actor.
///
/// The reader used to start a main-actor task for every read. During a download that was one task
/// per pipe read, queued faster than the main actor could work through them. Now a read lands here,
/// and only the first read after a drain asks the main actor to come and take what has gathered,
/// so a burst becomes one hop instead of hundreds.
nonisolated final class OutputInbox: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()
    private var waitingForDrain = false

    /// Keep `chunk`. True when the main actor has to be asked to drain: nothing was waiting yet.
    func put(_ chunk: Data) -> Bool {
        lock.lock(); defer { lock.unlock() }
        data.append(chunk)
        guard !waitingForDrain else { return false }
        waitingForDrain = true
        return true
    }

    /// Everything gathered since the last drain.
    func take() -> Data {
        lock.lock(); defer { lock.unlock() }
        waitingForDrain = false
        defer { data = Data() }
        return data
    }
}
