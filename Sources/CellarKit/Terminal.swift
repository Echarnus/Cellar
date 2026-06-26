import Foundation

/// Minimal ANSI styling that disables itself when output isn't a TTY or NO_COLOR is set.
public enum Term {
    public static var useColor: Bool {
        if ProcessInfo.processInfo.environment["NO_COLOR"] != nil { return false }
        return isatty(fileno(stdout)) == 1
    }

    private static func wrap(_ string: String, _ code: String) -> String {
        useColor ? "\u{001B}[\(code)m\(string)\u{001B}[0m" : string
    }

    public static func green(_ s: String) -> String { wrap(s, "32") }
    public static func yellow(_ s: String) -> String { wrap(s, "33") }
    public static func red(_ s: String) -> String { wrap(s, "31") }
    public static func cyan(_ s: String) -> String { wrap(s, "36") }
    public static func dim(_ s: String) -> String { wrap(s, "2") }
    public static func bold(_ s: String) -> String { wrap(s, "1") }

    public static func symbol(for status: CheckStatus) -> String {
        switch status {
        case .ok:   return green("✓")
        case .warn: return yellow("!")
        case .fail: return red("✗")
        case .info: return cyan("•")
        }
    }
}
