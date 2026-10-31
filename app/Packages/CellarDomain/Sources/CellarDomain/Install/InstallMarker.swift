import Foundation

/// A line `cellar install --machine-progress` prints so the app can follow along — the install
/// counterpart of `LaunchMarker`. The prose stays for the terminal; this is parsed and hidden.
public enum InstallMarker {
    public static let prefix = "::cellar-progress::"

    public static func line(_ progress: InstallProgress) -> String {
        var line = prefix + progress.phase.rawValue
        if let fraction = progress.fraction {
            line += " " + String(format: "%.4f", locale: Locale(identifier: "en_US_POSIX"), fraction)
        }
        return line
    }

    public static func progress(in line: String) -> InstallProgress? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix(prefix) else { return nil }
        let parts = trimmed.dropFirst(prefix.count).split(separator: " ", maxSplits: 1)
        guard let first = parts.first, let phase = InstallPhase(rawValue: String(first)) else { return nil }
        let fraction = parts.count > 1 ? Double(parts[1]) : nil
        return InstallProgress(phase, fraction: fraction)
    }
}
