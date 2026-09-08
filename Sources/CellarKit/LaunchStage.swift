import Foundation

/// Who is being launched, and by which route — everything the wording of a stage depends on.
///
/// The route matters as much as the store: the same Steam game can run through the client or, when
/// its profile says no live session is needed, straight from its exe. Saying "handing Steam the
/// command" when no Steam is involved would be the sort of small lie the UX rules exist to prevent.
public struct LaunchContext: Sendable {
    public let game: String
    public let store: GameStore
    /// Whether the launch goes through the store's client rather than running the exe directly.
    public let throughClient: Bool

    public init(game: String, store: GameStore, throughClient: Bool) {
        self.game = game
        self.store = store
        self.throughClient = throughClient
    }
}

/// The steps a launch really goes through, named so a player can be shown where they are.
///
/// Starting a Windows game on a Mac is not instant: a store client may have to be woken, the launch
/// command handed over, and the D3DMetal startup race survived. That is a minute or two in which a
/// lone spinner says nothing. These stages are what Cellar can *observe* — each is reported only
/// once it has genuinely been reached, and the list a game shows is the list its route will actually
/// take. A DRM-free game that runs bare never shows "Opening Steam", because it never opens Steam.
///
/// Deliberately not a percentage. Cellar cannot know how long Steam will take to be ready, and a bar
/// that guessed would be the same lie as a ✓ for something it can't check (skills/ux.md).
public enum LaunchStage: String, Sendable, CaseIterable {
    /// Resolving the profile, the runner and the bottle.
    case preparing
    /// Bringing the store's client up and waiting until it can take a command.
    case client
    /// Issuing the launch — a `steam://rungameid`, a Battle.net `--exec`, or the exe itself.
    case starting
    /// Watching for the game's own process to appear and stay up.
    case waiting
    /// The game is up.
    case running
    /// The player is playing; Cellar is waiting to close the layer behind them.
    case playing
    /// The game was quit and the layer is down.
    case closed

    /// The stages this launch will pass through, in order — the checklist worth showing.
    ///
    /// `running` and after are outcomes, not steps, so they are not in the list.
    public static func sequence(_ context: LaunchContext) -> [LaunchStage] {
        context.throughClient ? [.preparing, .client, .starting, .waiting]
                              : [.preparing, .starting, .waiting]
    }

    /// The heading for this step. Store-specific where the promise differs: Steam comes up silently,
    /// Battle.net puts a window on screen, and a bare game opens nothing at all.
    public func title(_ context: LaunchContext) -> String {
        switch self {
        case .preparing: return "Preparing the bottle"
        case .client:    return "Opening \(context.store.displayName)"
        case .starting:  return "Starting \(context.game)"
        case .waiting:   return "Waiting for \(context.game) to appear"
        case .running:   return "\(context.game) is running"
        case .playing:   return "Playing"
        case .closed:    return "\(context.game) closed"
        }
    }

    /// One sentence saying what is happening and, where it matters, what the player will see.
    public func detail(_ context: LaunchContext) -> String {
        let game = context.game
        switch self {
        case .preparing:
            return "Checking the Windows runtime and this game's bottle."
        case .client:
            switch context.store {
            case .steam:
                return "Steam starts in the background with no window. \(game) will not start reliably until it is ready, so Cellar waits."
            case .battlenet:
                return "Blizzard's app has to be running before it can be told to launch \(game). Its window may appear — leave it open."
            case .gog, .standalone:
                return "Opening \(context.store.displayName)."
            }
        case .starting:
            return context.throughClient
                ? "Cellar is handing \(context.store.displayName) the command to launch \(game)."
                : "Cellar is running the game's own program through Wine."
        case .waiting:
            return "Apple's graphics layer sometimes drops a game a few seconds in. Cellar watches for that and quietly starts it again, so this can take a couple of tries."
        case .running:
            return "Cellar closes everything it opened as soon as you quit."
        case .playing:
            return "Have fun. Cellar shuts the layer down when you quit the game."
        case .closed:
            return "The layer is shut down."
        }
    }
}

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
