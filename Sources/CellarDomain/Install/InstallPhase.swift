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
    /// The client's first self-update: Steam's installer is only a bootstrapper, and the real
    /// client arrives the first time it runs. Cellar runs that start with no window and shows it here.
    case clientUpdate
    /// Fetching the game's files.
    case downloading
    /// Running the game's own installer (GOG).
    case installing
    /// Asking Steam whether a game Cellar downloaded has a newer build. No denominator.
    case updateCheck
    /// Fetching what changed since the copy on disk — a patch, not the whole game.
    case updating

    public func title(game: String, store: GameStore) -> String {
        switch self {
        case .runtime:     return String(localized: "Getting the Windows runtime")
        case .bottle:      return String(localized: "Building \(game)'s bottle")
        case .client:      return String(localized: "Installing \(store.displayName) into the bottle")
        case .clientUpdate: return String(localized: "Updating \(store.displayName)")
        case .downloading: return String(localized: "Downloading \(game)")
        case .installing:  return String(localized: "Installing \(game)")
        case .updateCheck: return String(localized: "Checking for a newer version")
        case .updating:    return String(localized: "Updating \(game)")
        }
    }

    /// One sentence on what is happening, where the title alone would leave a question.
    public func detail(store: GameStore) -> String {
        switch self {
        case .runtime:
            return String(localized: "A one-time download, shared by every game you add.")
        case .bottle:
            return String(localized: "Windows' folders and settings, just for this game.")
        case .client:
            return store.descriptor.hasSilentInstaller
                ? String(localized: "Silent — there is nothing to click.")
                : String(localized: "Blizzard's installer opens a window — click through it.")
        case .clientUpdate:
            return String(localized: "Its first start fetches the full client — once, for every \(store.displayName) game.")
        case .downloading:
            return String(localized: "Straight from your library. You can keep using your Mac.")
        case .installing:
            return String(localized: "The installer runs with no window, so this bar is the progress.")
        case .updateCheck:
            return String(localized: "Asking \(store.displayName) which build is current. Nothing is downloaded yet.")
        case .updating:
            return String(localized: "Only what changed since your last download.")
        }
    }
}
