import CellarDomain
import Foundation
import Observation

/// The downloads queue: the game being installed now, the ones waiting their turn, and the calls
/// behind Install, Cancel and Remove.
///
/// Cellar has one runner (`ActivityStore`), so a second install used to do nothing until the first
/// had finished. Now Install while the runner is busy puts the game in `queue`, and the next one
/// starts each time the runner comes free, whatever it had been doing. The rules for the line
/// itself (no doubles, positions, removal) are `InstallQueue`'s, in CellarDomain, where they are
/// unit-tested.
@MainActor
@Observable
final class DownloadsViewModel {
    private(set) var queue = InstallQueue()
    /// The game being installed now, when it was started from here.
    private(set) var current: InstallQueue.Entry?

    @ObservationIgnored private let runner: ActivityStore
    /// Run after each install ends, so the library reads the game's new state from disk.
    @ObservationIgnored private let finished: @MainActor () -> Void

    init(activity: ActivityStore, finished: @escaping @MainActor () -> Void) {
        self.runner = activity
        self.finished = finished
        runner.whenIdle = { [weak self] in self?.startNext() }
    }

    // MARK: - Intents

    /// Install `game` now if Cellar is free, otherwise as soon as what is running and the games
    /// ahead of it are done. A store whose install cannot wait (`StoreDescriptor.queuesInstalls`)
    /// is only ever started now.
    func install(_ game: GameSummary) {
        let entry = InstallQueue.Entry(slug: game.slug, name: game.name, store: game.store)
        if !runner.busy {
            start(entry)
        } else if game.store.descriptor.queuesInstalls {
            queue.enqueue(entry, running: runner.installingSlug)
        }
    }

    /// Stop `slug`'s install if it is running, or take it out of the line if it is waiting. The
    /// games behind it move up; a running one is replaced by the next as soon as it has stopped.
    func cancel(_ slug: String) {
        if runner.installingSlug == slug {
            runner.cancel()
        } else {
            queue.remove(slug)
        }
    }

    // MARK: - Derived

    /// What Cellar is doing with `slug`, for its page and its sidebar row.
    func activity(for slug: String) -> GameActivity? {
        GameActivity.of(slug, running: runner.busy ? runner.installingSlug : nil,
                        progress: runner.installProgress, queue: queue)
    }

    /// Whether Install on `game` would add it to the line rather than start it.
    func wouldQueue(_ game: GameSummary) -> Bool {
        runner.busy && game.store.descriptor.queuesInstalls
    }

    /// The download running now, for the queue panel: its name and what it is doing. Nil when the
    /// runner is doing something else, or nothing.
    var running: (entry: InstallQueue.Entry, activity: GameActivity)? {
        guard runner.busy, let slug = runner.installingSlug,
              let entry = current?.slug == slug ? current : nil else { return nil }
        return (entry, .working(runner.installProgress))
    }

    /// Whether there is anything for the queue panel to show.
    var isEmpty: Bool { running == nil && queue.isEmpty }

    /// What the line is waiting for when it is not a download: a game being played, say.
    var waitingOn: String? {
        guard runner.busy, running == nil, !queue.isEmpty else { return nil }
        return runner.busyTitle
    }

    // MARK: - Running the line

    private func start(_ entry: InstallQueue.Entry) {
        current = entry
        let title = entry.store.descriptor.queuesInstalls
            ? String(localized: "Downloading \(entry.name)")
            : String(localized: "Opening Battle.net")
        runner.install(slug: entry.slug, title: title) { [weak self] in
            self?.current = nil
            self?.finished()
        }
    }

    /// The runner is free: the next game in line starts, if there is one.
    func startNext() {
        guard !runner.busy, let next = queue.next() else { return }
        start(next)
    }
}
