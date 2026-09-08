import Foundation

/// Cellar's version, in one place. The CLI's `--version`, the diagnostics report and the app's
/// About panel all read it from here so a bug report can never name a version that doesn't exist.
public enum CellarVersion {
    public static let current = "0.2.0"
}
