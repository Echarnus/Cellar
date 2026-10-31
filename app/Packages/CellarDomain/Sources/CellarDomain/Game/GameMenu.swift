import Foundation

/// What a game's "…" menu offers, and in which words.
///
/// The menu is for a player, not for whoever wrote the runtime. It used to list twelve entries —
/// three of them the same install in different words, and several that only made sense to someone
/// who knows what a Wine bottle is. Now it keeps what a gamer actually reaches for, and everything
/// that is there to fix something goes one level down, under **Troubleshooting**, where it is still
/// one click away for whoever is helping them.
///
/// Decided here rather than in the view so a test can hold the line: no jargon in the top level,
/// and no second way to install a game beside the page's one big button.
public struct GameMenu: Sendable, Equatable {

    public enum Item: Sendable, Equatable, Hashable {
        // The top level.
        case addToApplications
        case addToMacSteam
        case language
        case moveToDrive
        case moveBack
        case uninstall
        // Troubleshooting.
        case repair
        case openClient
        case installThroughClient
        case reapplyClientSettings
        case checkForUpdates
        case saveProfile
        case technicalDetails
        case saveDiagnostics
        case showLogs
        case removeEverything

        /// Whether the entry deletes something, so the view can mark it destructive.
        public var isDestructive: Bool { self == .uninstall || self == .removeEverything }

        /// The entry's words. Plain ones: a game, a drive, the store's own name — never a bottle,
        /// a runner or a prefix.
        public func title(for game: GameSummary) -> String {
            let store = game.store.displayName
            switch self {
            case .addToApplications:     return String(localized: "Add \(game.name) to Applications")
            case .addToMacSteam:         return String(localized: "Add to Steam on This Mac")
            case .language:              return String(localized: "Language")
            case .moveToDrive:           return String(localized: "Move to Another Drive…")
            case .moveBack:              return String(localized: "Move Back to This Mac")
            case .uninstall:             return String(localized: "Uninstall \(game.name)…")
            case .repair:                return String(localized: "Repair \(game.name)")
            case .openClient:            return String(localized: "Open \(store)")
            case .installThroughClient:  return String(localized: "Install with the \(store) app instead")
            case .reapplyClientSettings: return String(localized: "Fix \(store) settings")
            case .checkForUpdates:       return String(localized: "Check for updates")
            case .saveProfile:           return String(localized: "Save Game Settings As…")
            case .technicalDetails:      return String(localized: "Technical Details…")
            case .saveDiagnostics:       return String(localized: "Save Diagnostics Report…")
            case .showLogs:              return String(localized: "Show logs in Finder")
            case .removeEverything:      return String(localized: "Remove \(game.name) Completely…")
            }
        }
    }

    /// The top level, in groups the view separates with dividers.
    public let main: [[Item]]
    /// The Troubleshooting submenu, grouped the same way. Never empty: diagnostics are always there.
    public let troubleshooting: [[Item]]

    public init(game: GameSummary) {
        var everyday: [Item] = [.addToApplications]
        // A shortcut in the Mac's own Steam library, for a player who starts everything from there.
        if game.store == .steam { everyday.append(.addToMacSteam) }
        // The game's language lives in its Windows set-up; before there is one there is nothing to set.
        if game.bottleExists { everyday.append(.language) }

        var storage: [Item] = []
        if game.isOnOtherDrive {
            storage.append(.moveBack)
        } else if game.gameInstalled, game.store != .battlenet {
            // Blizzard's client decides where its games live; moving one behind its back breaks it.
            storage.append(.moveToDrive)
        }

        var removal: [Item] = []
        if game.gameInstalled { removal.append(.uninstall) }

        main = [everyday, storage, removal].filter { !$0.isEmpty }

        // Fixes, store by store. Installing stays the page's one big button; only Steam keeps a
        // second route, and only here, because its own client is the fallback when a download fails.
        var fixes: [Item] = []
        if game.bottleExists { fixes.append(.repair) }
        switch game.store {
        case .steam:
            // A game with no live-session DRM gets no Steam client in its bottle, so the client's own
            // actions only exist where there is (or will be) one.
            if game.needsLiveSession || game.clientInstalled {
                fixes += [.openClient, .installThroughClient]
            }
        case .battlenet:
            fixes += [.openClient, .reapplyClientSettings]
        case .gog:
            break
        }
        if game.update != nil { fixes.append(.checkForUpdates) }

        var details: [Item] = [.technicalDetails, .saveDiagnostics, .showLogs]
        if game.isDraft { details.append(.saveProfile) }

        var reset: [Item] = []
        if game.bottleExists { reset.append(.removeEverything) }

        troubleshooting = [fixes, details, reset].filter { !$0.isEmpty }
    }

    /// Every entry, top level and Troubleshooting both.
    public var allItems: [Item] { (main + troubleshooting).flatMap { $0 } }
}
