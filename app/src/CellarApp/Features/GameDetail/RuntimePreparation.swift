import CellarDomain
import AppKit
import SwiftUI
import CellarData

// The installer's three jobs that only the app can do: getting the shared parts in the background on
// first launch, moving itself out of the disk image, and taking itself off the Mac again. The
// deciding lives in CellarData (`Preparation`, `InstallLocation`, `Reset` + `SaveGames`); this file
// only asks and shows.

// MARK: - Getting ready in the background

/// `cellar prepare`, run by the app on launch until everything every game shares is on the Mac.
///
/// It starts while the player is reading the welcome tour, so by the time they press Install the
/// runtime and the Steam client are already here. It runs on its own `ActivityStore`, not the
/// library's, so it never holds the Play and Install buttons — a game set up meanwhile waits for it
/// in the CLI (`SetupLock`) and says so in its own activity log.
///
/// One instance, owned by `AppModel` and handed to the views that show it.
@MainActor
@Observable
final class RuntimePreparation {

    enum State: Equatable {
        case idle
        /// The latest line `cellar prepare` printed, for the footer.
        case working(String)
        case ready
        /// It stopped early; each part will be fetched when a game first needs it, so this is a
        /// note, not an error.
        case incomplete
    }
    private(set) var state: State = .idle

    /// The player's choice in Settings. On by default: the whole point is that a first game should
    /// not open on a 3 GB wait, and the welcome tour says it is happening.
    static let defaultsKey = "prepareAheadOfTime"
    var isEnabled: Bool = UserDefaults.standard.object(forKey: RuntimePreparation.defaultsKey) as? Bool ?? true {
        didSet {
            guard isEnabled != oldValue else { return }
            UserDefaults.standard.set(isEnabled, forKey: Self.defaultsKey)
            if isEnabled { startIfNeeded() } else { cancel() }
        }
    }

    @ObservationIgnored private let runner = ActivityStore()

    var isWorking: Bool { if case .working = state { return true } else { return false } }

    /// Starts when it is switched on, something is missing, and there is a CLI to run. Called after
    /// the first window is up, never from inside a view update.
    func startIfNeeded() {
        guard isEnabled, !isWorking, runner.binaryExists else { return }
        guard !Preparation.isComplete else { state = .ready; return }
        state = .working("Starting…")
        runner.run(.prepare, title: String(localized: "Getting Cellar ready"), observe: { [weak self] line in
            let text = line.trimmingCharacters(in: .whitespaces)
            // The CLI drops colour when its output is a pipe; strip escape codes anyway, so a
            // stray one never reaches the footer.
            let plain = text.replacingOccurrences(of: "\u{1B}\\[[0-9;]*m", with: "", options: .regularExpression)
            guard !plain.isEmpty, !plain.hasPrefix("$ "), !plain.hasPrefix("(exit") else { return }
            self?.state = .working(plain)
        }, then: { [weak self] in
            guard let self else { return }
            self.state = Preparation.isComplete ? .ready : .incomplete
        })
    }

    func cancel() {
        guard isWorking else { return }
        runner.cancel()
        state = .incomplete
    }
}
