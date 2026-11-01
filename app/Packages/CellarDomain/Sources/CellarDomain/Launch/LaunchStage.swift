import Foundation

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
    /// Waiting for the player to sign in to the store client's own window.
    case signIn
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
    /// The game has quit; Cellar is closing the store client and Wine behind it. Its own stage so
    /// the app stops saying "Playing" the moment the game is gone, not when the teardown ends.
    case closing
    /// The game was quit and the layer is down.
    case closed

    /// The stages this launch will pass through, in order — the checklist worth showing.
    ///
    /// `running` and after are outcomes, not steps, so they are not in the list.
    public static func sequence(_ context: LaunchContext) -> [LaunchStage] {
        // Signing in brings the client up with its window, so there is no separate quiet start.
        if context.signsInFirst { return [.preparing, .signIn, .starting, .waiting] }
        return context.throughClient ? [.preparing, .client, .starting, .waiting]
                                     : [.preparing, .starting, .waiting]
    }

    /// The heading for this step. Store-specific where the promise differs: Steam comes up silently,
    /// Battle.net puts a window on screen, and a bare game opens nothing at all.
    public func title(_ context: LaunchContext) -> String {
        switch self {
        case .preparing: return String(localized: "Preparing the bottle")
        case .signIn:    return String(localized: "Sign in to \(context.store.displayName)")
        case .client:    return String(localized: "Opening \(context.store.displayName)")
        case .starting:  return String(localized: "Starting \(context.game)")
        case .waiting:   return String(localized: "Waiting for \(context.game) to appear")
        case .running:   return String(localized: "\(context.game) is running")
        case .playing:   return String(localized: "Playing")
        case .closing:   return String(localized: "Closing down")
        case .closed:    return String(localized: "\(context.game) closed")
        }
    }

    /// One sentence saying what is happening and, where it matters, what the player will see.
    public func detail(_ context: LaunchContext) -> String {
        let game = context.game
        switch self {
        case .preparing:
            return String(localized: "Checking the Windows runtime and this game's bottle.")
        case .signIn:
            let store = context.store.displayName
            return String(localized: "\(store)'s window is open. Sign in there — the QR code with the \(store) mobile app is quickest. It's once, for every \(store) game, and \(game) starts as soon as you're in.")
        case .client:
            switch context.store {
            case .steam:
                return String(localized: "Steam starts in the background with no window. \(game) will not start reliably until it is ready, so Cellar waits.")
            case .battlenet:
                return String(localized: "Blizzard's app has to be running before it can be told to launch \(game). Its window may appear — leave it open.")
            case .gog:
                return String(localized: "Opening \(context.store.displayName).")
            }
        case .starting:
            return context.throughClient
                ? String(localized: "Cellar is handing \(context.store.displayName) the command to launch \(game).")
                : String(localized: "Cellar is running the game's own program through Wine.")
        case .waiting:
            return String(localized: "Apple's graphics layer sometimes drops a game a few seconds in. Cellar watches for that and quietly starts it again, so this can take a couple of tries.")
        case .running:
            return String(localized: "Cellar closes everything it opened as soon as you quit.")
        case .playing:
            return String(localized: "Have fun. Cellar shuts the layer down when you quit the game.")
        case .closing:
            return context.throughClient
                ? String(localized: "\(game) has quit. Cellar is closing \(context.store.displayName) and Wine behind it.")
                : String(localized: "\(game) has quit. Cellar is closing Wine behind it.")
        case .closed:
            return String(localized: "The layer is shut down.")
        }
    }
}
