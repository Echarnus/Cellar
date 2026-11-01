import Foundation

/// The end of a long log: the last `limit` lines, and a count of the ones let go.
///
/// The activity log used to keep everything a command printed. A Steam download prints a line for
/// every file, so after a large game the log was megabytes of text that SwiftUI laid out again on
/// every read from the pipe, and it went on doing so after the download had finished. Nobody reads
/// the ten-thousandth file name. The end of the log is what explains a failure.
public struct LogTail: Sendable, Equatable {
    public let limit: Int
    /// The longest a single line is kept. A runaway line is cut rather than laid out whole.
    public static let lineLimit = 2_000

    private var lines: [String] = []
    /// Lines that no longer fit, counted so the log can say some are missing.
    public private(set) var dropped = 0

    public init(limit: Int = 1_000) {
        self.limit = max(1, limit)
    }

    public var isEmpty: Bool { lines.isEmpty }
    /// The lines kept, oldest first.
    public var kept: ArraySlice<String> { lines.suffix(limit) }
    /// Every line ever appended, kept or not.
    public var total: Int { dropped + lines.count }

    public mutating func append(_ line: String) {
        lines.append(line.count > Self.lineLimit ? String(line.prefix(Self.lineLimit)) + "…" : line)
        // Trimmed in batches, so appending stays cheap: the array is cut back to `limit` only when
        // it reaches twice that.
        if lines.count >= limit * 2 {
            let extra = lines.count - limit
            lines.removeFirst(extra)
            dropped += extra
        }
    }

    /// The log as it reads on screen: a note about what was let go, the kept lines, and the line
    /// still being written.
    public func text(partial: String = "") -> String {
        let shown = kept
        let hidden = total - shown.count
        var out = ""
        if hidden > 0 {
            out += String(localized: "… \(hidden) earlier lines aren't shown.") + "\n"
        }
        for line in shown {
            out += line
            out += "\n"
        }
        return out + partial
    }
}
