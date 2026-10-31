import Foundation

/// The tools a `cellar` command has started and is waiting on, so they stop when it is stopped.
///
/// The app cancels a download by terminating `cellar`. Without this, DepotDownloader outlived it:
/// a cancelled download, or one running when the app quit, went on fetching at full speed with
/// nobody waiting for it. The Mac stayed slow after the download was "over", and the orphan took
/// Steam's logon id back from every download that came after.
public enum ChildProcesses {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var running: [ObjectIdentifier: Process] = [:]
    nonisolated(unsafe) private static var signalSources: [DispatchSourceSignal] = []

    /// Follow `process` until `untrack`. Call it once the process has started.
    public static func track(_ process: Process) {
        lock.lock(); defer { lock.unlock() }
        running[ObjectIdentifier(process)] = process
    }

    public static func untrack(_ process: Process) {
        lock.lock(); defer { lock.unlock() }
        running[ObjectIdentifier(process)] = nil
    }

    /// How many tools are being followed now.
    public static var count: Int {
        lock.lock(); defer { lock.unlock() }
        return running.count
    }

    /// Ask every followed tool to stop (SIGTERM), stop following them, and wait up to `grace` for
    /// them to go. Returns how many were still running when the wait ended.
    @discardableResult
    public static func terminateAll(grace: TimeInterval = 2) -> Int {
        lock.lock()
        let processes = Array(running.values)
        running.removeAll()
        lock.unlock()
        for process in processes where process.isRunning { process.terminate() }
        let deadline = Date().addingTimeInterval(grace)
        while processes.contains(where: \.isRunning), Date() < deadline {
            usleep(20_000)
        }
        return processes.filter(\.isRunning).count
    }

    /// When this process is told to stop (SIGTERM from the app's Cancel, SIGINT from Ctrl-C, SIGHUP
    /// from a closed terminal), stop the followed tools first, then stop the way the signal asked.
    /// Called once, by the CLI's entry point.
    public static func stopWithThisProcess() {
        lock.lock(); defer { lock.unlock() }
        guard signalSources.isEmpty else { return }
        for number in [SIGTERM, SIGINT, SIGHUP] {
            // A handler that does nothing, so the default action no longer ends the process before
            // the children are told; the dispatch source below is what acts. Not SIG_IGN: an ignored
            // signal stays ignored across exec, so every tool started afterwards — DepotDownloader,
            // Wine — would shrug off the very terminate this is for. A handler resets on exec.
            signal(number) { _ in }
            let source = DispatchSource.makeSignalSource(signal: number, queue: .global(qos: .userInitiated))
            source.setEventHandler {
                terminateAll()
                signal(number, SIG_DFL)
                kill(getpid(), number)
            }
            source.resume()
            signalSources.append(source)
        }
    }
}
