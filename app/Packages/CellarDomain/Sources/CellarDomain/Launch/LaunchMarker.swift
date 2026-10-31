import Foundation

/// A line the `cellar` CLI prints so the app can follow a launch step by step.
///
/// The app drives the CLI as a subprocess — that is how it inherits every tested path — which
/// leaves stdout as the only channel between them. Rather than have the app guess at prose, which
/// would break the moment a sentence is reworded, `cellar launch --machine-progress` prints one of
/// these markers per stage and the app strips them out of what it shows.
public enum LaunchMarker {
    public static let prefix = "::cellar-stage::"

    /// The line to print when `stage` is reached.
    public static func line(_ stage: LaunchStage) -> String { prefix + stage.rawValue }

    /// The stage a line announces, or nil if it is ordinary output.
    public static func stage(in line: String) -> LaunchStage? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix(prefix) else { return nil }
        return LaunchStage(rawValue: String(trimmed.dropFirst(prefix.count)))
    }

    /// Whether this line is a marker rather than something a person should read.
    public static func isMarker(_ line: String) -> Bool {
        line.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix(prefix)
    }
}
