import Foundation

/// The steps getting a game onto the Mac really goes through, so the app can draw a bar instead of
/// a spinner that says the same thing for twenty minutes.
///
/// Install is one button: it sets up whatever is missing (the Windows runtime, the bottle, a store
/// client) and then fetches the game. Each phase is reported only once it is genuinely under way,
/// and only a phase with a real denominator carries a fraction — DepotDownloader states how much of
/// the depot is down; a Wine prefix being built does not, so that one is an honest indeterminate
/// bar rather than a guessed percentage (skills/ux.md).
public enum InstallPhase: String, Sendable, CaseIterable {
    /// Downloading and unpacking the Wine runner. Once per Mac, shared by every game.
    case runtime
    /// Creating and initialising the game's bottle.
    case bottle
    /// Installing the store's client into the bottle.
    case client
    /// Fetching the game's files.
    case downloading
    /// Running the game's own installer (GOG).
    case installing

    public func title(game: String, store: GameStore) -> String {
        switch self {
        case .runtime:     return "Getting the Windows runtime"
        case .bottle:      return "Building \(game)'s bottle"
        case .client:      return "Installing \(store.displayName) into the bottle"
        case .downloading: return "Downloading \(game)"
        case .installing:  return "Installing \(game)"
        }
    }

    /// One sentence on what is happening, where the title alone would leave a question.
    public func detail(store: GameStore) -> String {
        switch self {
        case .runtime:
            return "A one-time download, shared by every game you add."
        case .bottle:
            return "Windows' folders and settings, just for this game."
        case .client:
            return store.descriptor.hasSilentInstaller
                ? "Silent — there is nothing to click."
                : "Blizzard's installer opens a window — click through it."
        case .downloading:
            return "Straight from your library. You can keep using your Mac."
        case .installing:
            return "The installer runs with no window, so this bar is the progress."
        }
    }
}

/// Where an install stands: the phase, and how far through it when that can be measured.
public struct InstallProgress: Sendable, Equatable {
    public let phase: InstallPhase
    /// 0…1, or nil when the phase has no honest denominator.
    public let fraction: Double?

    public init(_ phase: InstallPhase, fraction: Double? = nil) {
        self.phase = phase
        self.fraction = fraction.map { min(max($0, 0), 1) }
    }
}

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

/// Reads DepotDownloader's per-file progress lines — ` 12.34% game\data\file.pak` — for how much of
/// the depot is down. The number is the whole depot's, not the file's, which is what makes it a bar.
public enum DepotProgress {
    public static func fraction(in line: String) -> Double? {
        let trimmed = line.drop { $0 == " " }
        guard let percent = trimmed.firstIndex(of: "%") else { return nil }
        let number = trimmed[trimmed.startIndex..<percent]
        // The tool formats with the machine's locale, so a Belgian Mac writes "12,34%".
        guard !number.isEmpty, number.count <= 6,
              number.allSatisfy({ $0.isNumber || $0 == "." || $0 == "," }),
              let value = Double(number.replacingOccurrences(of: ",", with: ".")),
              (0...100).contains(value) else { return nil }
        let after = trimmed[trimmed.index(after: percent)...]
        guard after.isEmpty || after.first == " " else { return nil }
        return value / 100
    }
}
