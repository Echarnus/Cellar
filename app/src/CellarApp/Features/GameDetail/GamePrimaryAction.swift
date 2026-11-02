import CellarDomain
import CellarData
import Foundation

/// The game's one big action — Play, Install (or add to the queue), Set up — in one place, so the
/// page's button and the sidebar's right-click menu always do the same thing.
@MainActor
enum GamePrimaryAction {
    /// Whether the action can run now: not while Cellar is busy (unless Install would only queue
    /// the game), and not while this game is already downloading or queued.
    static func isAvailable(_ game: GameSummary, runner: ActivityStore, downloads: DownloadsViewModel) -> Bool {
        let queues = game.nextStep == .install && downloads.activity(for: game.slug) == nil && downloads.wouldQueue(game)
        return !(runner.busy && !queues) && downloads.activity(for: game.slug) == nil
    }

    /// The menu's words for it: "Add to Queue" when Install would wait its turn.
    static func title(_ game: GameSummary, downloads: DownloadsViewModel) -> String {
        game.nextStep == .install && downloads.wouldQueue(game) ? String(localized: "Add to Queue") : game.actionTitle
    }

    static func perform(_ game: GameSummary, runner: ActivityStore, downloads: DownloadsViewModel,
                        onChange: @escaping () -> Void) {
        switch game.nextStep {
        case .play:
            // The launch gets a window of its own: it is a minute or two of work with several
            // steps, and a spinner beside the button reads as a hang. The frame-rate overlay is a
            // setting like Retina and MetalFX, read from the plan by the launch, so no flag here.
            runner.launch(slug: game.slug, showHUD: false) {
                onChange()
                // Played and quit: the one moment "how did it run?" has an answer.
                if runner.stage == .closed { CompatibilityPrompt.offerAfterSession(game) }
            }
            LaunchSplashWindow.present(game: game, runner: runner, onFinished: { onChange() })
        case .setup:
            runner.run(.setUp(slug: game.slug), title: String(localized: "Setting up"), then: { onChange() })
        case .install:
            // One verb for every store, through the queue: started now when Cellar is free,
            // otherwise when its turn comes.
            downloads.install(game)
        }
    }
}
