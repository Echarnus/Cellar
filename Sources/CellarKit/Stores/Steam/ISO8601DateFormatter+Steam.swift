import CellarDomain
import Foundation

extension ISO8601DateFormatter {
    /// `2026-09-08T121314Z` — safe in a filename (no colons, which Finder shows as slashes).
    // ISO8601DateFormatter is documented thread-safe, but Foundation does not mark it Sendable, and
    // this one is configured once and never changed again.
    nonisolated(unsafe) static let filenameSafe: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withYear, .withMonth, .withDay, .withTime, .withTimeZone, .withDashSeparatorInDate]
        return f
    }()
}
