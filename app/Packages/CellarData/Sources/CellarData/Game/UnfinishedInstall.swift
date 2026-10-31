import CellarDomain
import Foundation

/// A note in the bottle that an install has started and not yet finished.
///
/// "Installed" used to mean "the exe is on disk", and DepotDownloader writes the exe early. At 3%
/// the game read Installed and offered Play. The note is written before the store's install begins
/// and removed only once it succeeds. While it is there the game is not installed, whatever files
/// exist. A cancelled, failed or interrupted install leaves it behind, so the game reads "Download
/// incomplete" and Install resumes it.
///
/// Kept in the bottle, not beside the game's files: the download tool owns that folder, and a
/// removed bottle takes the note with it.
public enum UnfinishedInstall {
    static let fileName = ".cellar-install-unfinished"

    static func marker(for plan: GamePlan) -> URL {
        plan.prefix.appendingPathComponent(fileName)
    }

    /// Note that `plan`'s install has begun. Needs the bottle, which set-up made before this.
    public static func begin(_ plan: GamePlan) {
        guard FileManager.default.fileExists(atPath: plan.prefix.path) else { return }
        try? Data("\(plan.slug)\n".utf8).write(to: marker(for: plan), options: .atomic)
    }

    /// The install finished: the game's files are the game.
    public static func finish(_ plan: GamePlan) {
        try? FileManager.default.removeItem(at: marker(for: plan))
    }

    /// Whether an install of `plan` started and has not finished.
    public static func isPending(_ plan: GamePlan) -> Bool {
        FileManager.default.fileExists(atPath: marker(for: plan).path)
    }
}
