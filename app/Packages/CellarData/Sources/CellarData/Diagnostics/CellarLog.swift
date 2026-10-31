import CellarDomain
import Foundation

/// A rolling, append-only event log shared by the CLI and the app.
///
/// It exists so a failure can be explained *after* it happened: both binaries write to one file
/// under `~/Library/Application Support/Cellar/logs`, it rotates at a fixed size so it can never
/// eat the disk, and `Diagnostics.exportReport` folds it into a single text file the player can
/// attach to a bug report.
///
/// Writing never throws and never fails a caller — a game must not fail to launch because a log
/// file could not be opened.
public final class CellarLog: @unchecked Sendable {
    public static let shared = CellarLog()

    /// ~1.5 MB of history at most: many sessions deep, still small enough to send.
    private static let maxBytesPerFile = 512_000
    private static let rotations = 2          // cellar.log + cellar.log.1 + cellar.log.2

    private let lock = NSLock()
    private let fileManager = FileManager.default

    /// `CELLAR_LOG_LEVEL=off` silences the file entirely; anything else names the floor.
    private let minimumLevel: LogLevel?
    /// `CELLAR_LOG_STDERR=1` mirrors entries to stderr, for developing against the CLI.
    private let mirrorsToStderr: Bool
    private let source: String

    private init() {
        let env = ProcessInfo.processInfo.environment
        switch env["CELLAR_LOG_LEVEL"]?.lowercased() {
        case .none, .some(""):            minimumLevel = .debug
        case .some("off"), .some("none"): minimumLevel = nil
        case .some(let raw):              minimumLevel = LogLevel(rawValue: raw) ?? .debug
        }
        mirrorsToStderr = env["CELLAR_LOG_STDERR"] == "1"
        switch ProcessInfo.processInfo.processName {
        case "CellarApp", "Cellar": source = "app"
        case "cellar":              source = "cli"
        case let other:             source = String(other.prefix(8))
        }
    }

    // MARK: - Writing

    public static func debug(_ category: LogCategory, _ message: String, subject: String? = nil) {
        shared.write(.debug, category, message, subject)
    }

    public static func info(_ category: LogCategory, _ message: String, subject: String? = nil) {
        shared.write(.info, category, message, subject)
    }

    public static func warn(_ category: LogCategory, _ message: String, subject: String? = nil) {
        shared.write(.warn, category, message, subject)
    }

    public static func error(_ category: LogCategory, _ message: String, subject: String? = nil) {
        shared.write(.error, category, message, subject)
    }

    /// Log a thrown error in the words the player was given — a `CellarError` already ends with the
    /// command or button that fixes it, and the log should not paraphrase that away.
    public static func failure(_ category: LogCategory, _ what: String, _ error: Error,
                               subject: String? = nil) {
        shared.write(.error, category, "\(what): \(describe(error))", subject)
    }

    public static func describe(_ error: Error) -> String {
        if let error = error as? CellarError { return error.description }
        return error.localizedDescription
    }

    private func write(_ level: LogLevel, _ category: LogCategory, _ message: String, _ subject: String?) {
        guard let minimumLevel, level >= minimumLevel else { return }
        // Credentials are taken out *here*, before anything reaches the disk — not only when a report
        // is exported. A token that made it into the file once sits in every backup of it, and the
        // log is exactly what a player attaches to a public issue (OWASP MASVS-STORAGE-2).
        let entry = LogEntry(date: Date(), level: level, source: source, category: category,
                             subject: subject.flatMap { $0.isEmpty ? nil : $0 },
                             message: Diagnostics.redactCredentials(message))
        let line = entry.line + "\n"
        if mirrorsToStderr { FileHandle.standardError.write(Data(line.utf8)) }

        lock.lock()
        defer { lock.unlock() }
        append(line)
    }

    /// Whether this process has already narrowed the log's permissions. Once is enough: every file
    /// it creates afterwards is created private.
    private var isPrivate = false

    private func append(_ line: String) {
        let url = Self.fileURL
        try? fileManager.createDirectory(at: url.deletingLastPathComponent(),
                                         withIntermediateDirectories: true)
        if !isPrivate {
            // The log names games, paths and what went wrong with a sign-in: the player's to read,
            // not every account's on the Mac. Covers logs written before this was enforced.
            PrivateFiles.restrict(directory: Paths.logs)
            for file in Self.files { PrivateFiles.restrict(file: file) }
            isPrivate = true
        }
        rotateIfNeeded(url)
        guard let handle = try? FileHandle(forWritingTo: url) else {
            // First write on a fresh install, or straight after a rotation: there is no file to open.
            try? PrivateFiles.write(Data(line.utf8), to: url)
            return
        }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: Data(line.utf8))
    }

    /// Roll `cellar.log` → `.1` → `.2` and drop what falls off the end. Bounded by construction:
    /// a log that grows forever is one nobody can send.
    ///
    /// The lock is per-process. If the app and the CLI happen to cross the size threshold in the
    /// same instant, one of them can lose a line to the other's rename — deliberately accepted:
    /// a cross-process lock on every write would make logging a thing that can block a launch,
    /// which is the one thing it must never be.
    private func rotateIfNeeded(_ url: URL) {
        guard let size = try? fileManager.attributesOfItem(atPath: url.path)[.size] as? Int,
              size >= Self.maxBytesPerFile else { return }
        try? fileManager.removeItem(at: Self.rotatedURL(Self.rotations))
        for index in stride(from: Self.rotations - 1, through: 0, by: -1) {
            let from = Self.rotatedURL(index)
            guard fileManager.fileExists(atPath: from.path) else { continue }
            try? fileManager.moveItem(at: from, to: Self.rotatedURL(index + 1))
        }
    }

    // MARK: - Reading

    /// The file being written to right now.
    public static var fileURL: URL { rotatedURL(0) }

    private static func rotatedURL(_ index: Int) -> URL {
        Paths.logs.appendingPathComponent(index == 0 ? "cellar.log" : "cellar.log.\(index)")
    }

    /// Every retained file, oldest first — the order they must be read in to be a history.
    public static var files: [URL] {
        (0...rotations).reversed()
            .map(rotatedURL)
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// The whole retained history as text, oldest line first.
    public static func history() -> String {
        files.compactMap { try? String(contentsOf: $0, encoding: .utf8) }.joined()
    }

    /// Parsed entries, newest last, after filtering. `limit` keeps the most recent ones.
    public static func entries(limit: Int = 100, minimumLevel: LogLevel = .debug,
                               category: LogCategory? = nil, subject: String? = nil) -> [LogEntry] {
        let matches = history()
            .split(separator: "\n", omittingEmptySubsequences: true)
            .compactMap { LogEntry.parse(String($0)) }
            .filter { $0.level >= minimumLevel }
            .filter { category == nil || $0.category == category }
            .filter { subject == nil || $0.subject == subject }
        return limit > 0 ? Array(matches.suffix(limit)) : matches
    }

    /// Total bytes kept on disk, for a screen that tells the player what they are about to send.
    public static var historySize: Int {
        files.reduce(0) { total, url in
            let size = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int
            return total + (size ?? 0)
        }
    }

    /// Drop the history. Only ever called because the player asked for it.
    public static func clear() {
        for url in files { try? FileManager.default.removeItem(at: url) }
    }

    static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        // Local time with its offset: the player reads this against their own clock, and the
        // offset keeps it unambiguous once the file is sent to someone in another timezone.
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()
}
