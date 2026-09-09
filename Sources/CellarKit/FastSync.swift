import Foundation

/// Which fast synchronisation backend a Wine build implements — the thing that decides whether a
/// game's mutexes and events cost a round trip to wineserver or a few user-space instructions.
///
/// On Linux this is esync/fsync/ntsync. macOS has no futex, so every build there carries its own
/// answer, switched on by its own environment variable, and a build ignores the variables it does
/// not know. Cellar therefore *reads* which variables a build understands from its `ntdll.so`
/// (they are plain strings in the binary) and sets exactly those, rather than setting one and
/// hoping. The two it has met:
///
/// - **msync** (`WINEMSYNC`) — Mach semaphores, marzent's patch, in Sikarugir / Whisky-lineage
///   Wine 10 builds, with **esync** (`WINEESYNC`) as their fallback.
/// - **WFUSync** (`WINEWFUSYNC`) — WineForge's user-space backend on `os_sync_wait_on_address`
///   (macOS 14.4+, the futex equivalent). Its Wine 11 tree carries no msync or esync at all.
public struct FastSync: Equatable, Sendable {
    /// Environment variables the build recognises, each to be set to `1`. Empty means the build
    /// has no fast path Cellar knows of, and every wait goes through wineserver.
    public let variables: [String]

    /// Every variable Cellar knows how to look for, with the name a player reads.
    static let known: [(variable: String, name: String)] = [
        ("WINEWFUSYNC", "WFUSync"),
        ("WINEMSYNC", "msync"),
        ("WINEESYNC", "esync"),
    ]

    /// What a build with no readable `ntdll.so` gets: every variable, since an unknown one is
    /// ignored and the cost of a missing one is the slow path. Tests' stub runners land here.
    public static let unknown = FastSync(variables: known.map(\.variable))
    public static let none = FastSync(variables: [])

    /// The player-facing summary: `"WFUSync"`, `"msync + esync"`, or `"none"`.
    public var summary: String {
        let names = FastSync.known.filter { variables.contains($0.variable) }.map(\.name)
        return names.isEmpty ? "none" : names.joined(separator: " + ")
    }

    /// Scan `ntdll.so` for the variable names. A few megabytes read once per runner per process;
    /// cached because `WineRunner.environment()` is built for every command a launch issues.
    static func probe(ntdll: URL?) -> FastSync {
        guard let ntdll else { return .unknown }
        lock.lock(); defer { lock.unlock() }
        if let hit = cache[ntdll.path] { return hit }
        guard let data = try? Data(contentsOf: ntdll, options: .mappedIfSafe) else { return .unknown }
        let found = known.map(\.variable).filter { data.range(of: Data($0.utf8)) != nil }
        let result = FastSync(variables: found)
        cache[ntdll.path] = result
        return result
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var cache: [String: FastSync] = [:]
}
