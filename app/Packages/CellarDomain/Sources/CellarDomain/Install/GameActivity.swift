import Foundation

/// What Cellar is doing with one game right now, if anything, said the same way on its page and
/// in the sidebar.
///
/// Each game answers for itself. The page used to show whatever the app was busy with, so the
/// Skyrim page read "Downloading Planet Coaster 2" beside a greyed-out Install. Planet Coaster's own
/// page meanwhile read "Installed" at 3%, because its exe was already on disk.
public enum GameActivity: Equatable, Sendable {
    /// Waiting its turn. `position` 1 is the next to start.
    case queued(position: Int)
    /// Being worked on. The phase says which part (downloading, setting up, the installer), and
    /// it is nil until the command has said.
    case working(InstallProgress?)

    /// What `slug` is doing, given the game the running command works on, how far that has got,
    /// and the queue.
    public static func of(_ slug: String, running: String?, progress: InstallProgress?,
                          queue: InstallQueue) -> GameActivity? {
        if slug == running { return .working(progress) }
        return queue.position(of: slug).map { .queued(position: $0) }
    }

    /// Fetching files, as opposed to setting things up around them.
    public var isDownloading: Bool {
        guard case .working(let progress) = self else { return false }
        return progress?.phase == .downloading || progress?.phase == .updating
    }

    /// One short phrase for the sidebar and the status chip: "Downloading 34%", "Installing",
    /// "Up next". Only a phase that can be measured gets a number.
    public var statusText: String {
        switch self {
        case .queued(let position):
            return position == 1 ? String(localized: "Up next") : String(localized: "Queued, \(position) in line")
        case .working(let progress):
            // Rounded down, as the bar's own number is, so it never says 100% before the end.
            let percent = progress?.fraction.map {
                (($0 * 100).rounded(.down) / 100).formatted(.percent.precision(.fractionLength(0)))
            }
            switch progress?.phase {
            case .downloading:
                return percent.map { String(localized: "Downloading \($0)") } ?? String(localized: "Downloading")
            case .updating:
                return percent.map { String(localized: "Updating \($0)") } ?? String(localized: "Updating")
            case .updateCheck:
                return String(localized: "Checking for updates")
            case .runtime, .bottle, .client, .clientUpdate, .installing, nil:
                return String(localized: "Installing")
            }
        }
    }

    /// The SF Symbol beside `statusText`.
    public var symbol: String {
        switch self {
        case .queued: return "clock"
        case .working: return isDownloading ? "arrow.down.circle" : "gearshape.2"
        }
    }
}
