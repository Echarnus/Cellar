import CellarDomain
import Foundation
#if canImport(Darwin)
import Darwin   // libproc: proc_listallpids, proc_pidpath
#endif

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
        let pids = leftovers(running(), root: canonicalPath(root))
        for pid in pids { kill(pid, SIGKILL) }
        return pids
    }

    /// `root` spelled the way the kernel reports an executable under it: every symlink resolved,
    /// `/private` kept. `URL.resolvingSymlinksInPath` strips a leading `/private`, so a runner under
    /// `/var/folders/…` would never match the `/private/var/folders/…` that `proc_pidpath` returns,
    /// and its leftovers would never be found.
    static func canonicalPath(_ root: URL) -> String {
        guard let resolved = realpath(root.path, nil) else { return root.resolvingSymlinksInPath().path }
        defer { free(resolved) }
        return String(cString: resolved)
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
