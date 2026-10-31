import CellarDomain
import Foundation

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
