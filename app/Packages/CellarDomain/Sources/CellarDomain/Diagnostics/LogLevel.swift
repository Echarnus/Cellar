import Foundation

/// How loud an entry is. `debug` is kept too — the point of the log is that when a player comes
/// back hours later saying "it crashed", the boring lines around the crash are still there.
public enum LogLevel: String, CaseIterable, Comparable {
    case debug, info, warn, error

    public var rank: Int {
        switch self {
        case .debug: return 0
        case .info:  return 1
        case .warn:  return 2
        case .error: return 3
        }
    }

    public static func < (lhs: LogLevel, rhs: LogLevel) -> Bool { lhs.rank < rhs.rank }

    /// Fixed width so the columns line up for whoever opens the file in a text editor.
    public var tag: String { rawValue.uppercased().padding(toLength: 5, withPad: " ", startingAt: 0) }

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
