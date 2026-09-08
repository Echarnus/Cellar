import Foundation

/// How loud an entry is. `debug` is kept too — the point of the log is that when a player comes
/// back hours later saying "it crashed", the boring lines around the crash are still there.
public enum LogLevel: String, CaseIterable, Comparable {
    case debug, info, warn, error

    var rank: Int {
        switch self {
        case .debug: return 0
        case .info:  return 1
        case .warn:  return 2
        case .error: return 3
        }
    }

    public static func < (lhs: LogLevel, rhs: LogLevel) -> Bool { lhs.rank < rhs.rank }

    /// Fixed width so the columns line up for whoever opens the file in a text editor.
    var tag: String { rawValue.uppercased().padding(toLength: 5, withPad: " ", startingAt: 0) }

    /// Mark used when the log is printed to a terminal. Colour never carries the level alone.
    public var symbol: String {
        switch self {
        case .debug: return "·"
        case .info:  return "•"
        case .warn:  return "!"
        case .error: return "✗"
        }
    }
}

/// What part of Cellar an entry came from. Kept coarse: enough to filter by, not a taxonomy.
public enum LogCategory: String, CaseIterable {
    case app         // the GUI and the CLI themselves: started, quit, command invoked
    case session     // one play session: launched, exited after N minutes
    case launch      // getting a game to start
    case setup       // runner + bottle + store client
    case install     // downloading/installing a game
    case store       // Steam / Battle.net / GOG client work
    case account     // sign-in state
    case runner      // runner install / removal
    case prefix      // bottle work
    case diagnostics // the log about the log: rotation, export
}

/// One parsed line of the rolling log.
public struct LogEntry {
    public let date: Date
    public let level: LogLevel
    public let source: String       // "cli" or "app" — both write to the same file
    public let category: LogCategory
    public let subject: String?     // game slug, runner id, bottle name…
    public let message: String

    /// The on-disk form: one entry, one line. Flattening belongs here rather than in the writer,
    /// so anything that renders a line gets the same guarantee the parser depends on.
    public var line: String {
        [CellarLog.timestampFormatter.string(from: date), level.tag, source,
         category.rawValue, subject ?? "-", Self.flatten(message)].joined(separator: "  ")
    }

    /// One entry per line, and two spaces are the column separator — so neither may survive
    /// inside a message.
    static func flatten(_ message: String) -> String {
        message
            .replacingOccurrences(of: "\r\n", with: " · ")
            .replacingOccurrences(of: "\n", with: " · ")
            .replacingOccurrences(of: "\t", with: " ")
            .replacingOccurrences(of: " {2,}", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    public init(date: Date, level: LogLevel, source: String, category: LogCategory,
                subject: String?, message: String) {
        self.date = date
        self.level = level
        self.source = source
        self.category = category
        self.subject = subject
        self.message = message
    }

    /// Reads a line back — the app and `cellar logs` both display parsed entries, and a line that
    /// cannot be parsed is skipped rather than shown raw.
    public static func parse(_ line: String) -> LogEntry? {
        let parts = line.components(separatedBy: "  ")
        guard parts.count >= 6,
              let date = CellarLog.timestampFormatter.date(from: parts[0]),
              let level = LogLevel(rawValue: parts[1].trimmingCharacters(in: .whitespaces).lowercased()),
              let category = LogCategory(rawValue: parts[3])
        else { return nil }
        return LogEntry(date: date, level: level, source: parts[2], category: category,
                        subject: parts[4] == "-" ? nil : parts[4],
                        message: parts[5...].joined(separator: "  "))
    }
}

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
        let entry = LogEntry(date: Date(), level: level, source: source, category: category,
                             subject: subject.flatMap { $0.isEmpty ? nil : $0 }, message: message)
        let line = entry.line + "\n"
        if mirrorsToStderr { FileHandle.standardError.write(Data(line.utf8)) }

        lock.lock()
        defer { lock.unlock() }
        append(line)
    }

    private func append(_ line: String) {
        let url = Self.fileURL
        try? fileManager.createDirectory(at: url.deletingLastPathComponent(),
                                         withIntermediateDirectories: true)
        rotateIfNeeded(url)
        guard let handle = try? FileHandle(forWritingTo: url) else {
            // First write on a fresh install: there is no file to open yet.
            try? Data(line.utf8).write(to: url)
            return
        }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: Data(line.utf8))
    }

    /// Roll `cellar.log` → `.1` → `.2` and drop what falls off the end. Bounded by construction:
    /// a log that grows forever is one nobody can send.
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
