import Foundation

/// How long and how recently each game was played — kept on this Mac, in Cellar's own folder, and
/// never sent anywhere.
///
/// A session is written down when it starts, not only when it ends, so a crash, a force quit or a
/// Mac that ran out of battery still leaves a record. Such a session is closed the next time
/// Cellar reads the record and the game isn't running, ending at the last sign of life Cellar saw:
/// the last line in its log about the game, or the last write to the game's Wine log. That is an
/// estimate in the honest direction — never longer than what was observed.
public enum Playtime {

    public struct Record: Codable, Sendable, Equatable {
        public var totalSeconds: Int = 0
        public var sessions: Int = 0
        public var lastPlayed: Date?
        /// A session that started and hasn't been closed yet.
        public var openSince: Date?
    }

    static var file: URL { Paths.appSupport.appendingPathComponent("playtime.json") }
    private static let lock = NSLock()

    /// The game is up.
    public static func began(slug: String, at date: Date = Date()) {
        update { all in
            var record = all[slug] ?? Record()
            record.openSince = date
            record.lastPlayed = date
            all[slug] = record
        }
    }

    /// The game is gone.
    public static func ended(slug: String, at date: Date = Date()) {
        update { all in
            guard var record = all[slug], let start = record.openSince else { return }
            close(&record, start: start, end: date)
            all[slug] = record
        }
    }

    /// Every game's record, with any session left open by a crash closed first — unless the game
    /// is running right now, which `isRunning` answers.
    public static func all(isRunning: (String) -> Bool = { _ in false }, now: Date = Date()) -> [String: Record] {
        var result: [String: Record] = [:]
        update { all in
            for (slug, record) in all {
                guard let start = record.openSince, !isRunning(slug) else { continue }
                var closed = record
                close(&closed, start: start, end: min(now, lastSignOfLife(slug: slug, after: start) ?? start))
                all[slug] = closed
            }
            result = all
        }
        return result
    }

    static func close(_ record: inout Record, start: Date, end: Date) {
        record.totalSeconds += max(0, Int(end.timeIntervalSince(start)))
        record.sessions += 1
        record.lastPlayed = max(record.lastPlayed ?? end, end)
        record.openSince = nil
    }

    /// The latest moment Cellar knows the game was still going: its last log line, or its Wine
    /// log's last write.
    static func lastSignOfLife(slug: String, after start: Date) -> Date? {
        var candidates: [Date] = CellarLog.entries(limit: 1, subject: slug).map(\.date)
        if let wine = Diagnostics.wineLogs(slug: slug, limit: 1).first,
           let modified = try? wine.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate {
            candidates.append(modified)
        }
        return candidates.filter { $0 >= start }.max()
    }

    /// "12 h 5 min", "45 min", "under a minute".
    public static func describe(seconds: Int) -> String {
        if seconds < 60 { return "under a minute" }
        let hours = seconds / 3600, minutes = (seconds % 3600) / 60
        if hours == 0 { return "\(minutes) min" }
        return minutes == 0 ? "\(hours) h" : "\(hours) h \(minutes) min"
    }

    private static func update(_ change: (inout [String: Record]) -> Void) {
        lock.lock(); defer { lock.unlock() }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var all = (try? Data(contentsOf: file)).flatMap { try? decoder.decode([String: Record].self, from: $0) } ?? [:]
        let before = all
        change(&all)
        guard all != before else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(all) else { return }
        try? FileManager.default.createDirectory(at: Paths.appSupport, withIntermediateDirectories: true)
        try? data.write(to: file, options: .atomic)
    }
}
