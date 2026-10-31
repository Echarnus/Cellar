import Foundation

/// What a use case reports while it works — one typed stream instead of a closure per kind.
///
/// `SetUpGame`, `InstallGame`, `LaunchGame` and `UninstallGame` each take a single
/// `(GameEvent) -> Void`. The CLI prints the sentences and turns the phases and stages into the
/// markers the app reads; a test simply collects them. The words of every `.step` are the ones the
/// player has always read: a use case changes who says them, never what is said.
public enum GameEvent: Equatable, Sendable {
    /// A sentence of progress, as the terminal prints it.
    case step(String)
    /// Where an install (or the update before a launch) has got to — what the app's progress bar shows.
    case install(InstallProgress)
    /// Where a launch has got to — what the app's launch window shows.
    case launch(LaunchStage)

    /// The sentence, for a caller that only prints.
    public var sentence: String? {
        if case .step(let text) = self { return text }
        return nil
    }
}

extension GameEvent {
    /// Hand the event to the closure for its kind — how the `Game` façades keep the signatures
    /// their callers already use.
    public func deliver(progress: (String) -> Void,
                        install: (InstallProgress) -> Void = { _ in },
                        launch: (LaunchStage) -> Void = { _ in }) {
        switch self {
        case .step(let text): progress(text)
        case .install(let value): install(value)
        case .launch(let stage): launch(stage)
        }
    }
}
