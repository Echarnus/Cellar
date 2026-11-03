import Foundation

/// What one game's page says, beside its main button, about what Cellar is doing.
///
/// Cellar has one runner, so while it works every page's button waits. What the page *says* about
/// that work has to be about its own game. It used to fall through to the runner's title, so the
/// Skyrim page — not installed — sat beside a spinner reading "Launching" while Planet Coaster 2
/// started, and went on saying it for the whole time Planet Coaster 2 was played. Downloads were
/// fixed the same way earlier (`GameActivity`); this covers every command.
public enum GamePageStatus: Equatable, Sendable {
    /// Nothing is running.
    case idle
    /// This game is running.
    case playing
    /// This game is downloading or updating: the page draws the bar.
    case installing
    /// This game is waiting in the downloads queue. `position` 1 is the next to start.
    case queued(position: Int)
    /// Cellar is working on this game, or on something every game waits for (a sign-in, the shared
    /// runtime). `title` is the runner's own words; `launch` is whether it is this game starting,
    /// so the page can offer the launch window again.
    case busy(title: String, launch: Bool)
    /// Another game is downloading.
    case anotherGameDownloading
    /// Another game is starting, being played, or closing down.
    case anotherGameRunning
    /// Cellar is doing something else for another game (a repair, a move, a save backup).
    case anotherGameBusy

    /// What the runner is doing, as much of it as a page needs.
    public struct Runner: Equatable, Sendable {
        public var busy: Bool
        /// The game the running command works on (`CellarCommand.game`); nil for app-wide work.
        public var game: String?
        public var title: String
        public var launching: Bool
        public var installing: Bool
        /// The launched game has come up and is being played.
        public var playing: Bool

        public init(busy: Bool, game: String?, title: String = "",
                    launching: Bool = false, installing: Bool = false, playing: Bool = false) {
            self.busy = busy; self.game = game; self.title = title
            self.launching = launching; self.installing = installing; self.playing = playing
        }

        public static let idle = Runner(busy: false, game: nil)
    }

    /// What `slug`'s page says, given the runner and the game's place in the downloads queue.
    public static func of(_ slug: String, runner: Runner, queuePosition: Int?) -> GamePageStatus {
        let own = runner.busy && runner.game == slug
        if own, runner.launching, runner.playing { return .playing }
        if own, runner.installing { return .installing }
        if let queuePosition { return .queued(position: queuePosition) }
        guard runner.busy else { return .idle }
        if let other = runner.game, other != slug {
            if runner.installing { return .anotherGameDownloading }
            return runner.launching ? .anotherGameRunning : .anotherGameBusy
        }
        return .busy(title: runner.title, launch: own && runner.launching)
    }
}
