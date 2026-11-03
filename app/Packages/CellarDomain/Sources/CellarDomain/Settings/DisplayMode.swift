import Foundation

/// Whether a game starts full screen or in a window — the `display_mode` switch (#306).
///
/// Wine has no switch that puts every game in a window: the Mac driver's options under
/// `Software\Wine\Mac Driver` only change *how* full screen is done (`CaptureDisplaysForFullscreen`),
/// and a game decides for itself whether it goes full screen. So Cellar asks the game, the one way
/// that works without editing its settings files: its engine's own start-up switch. An engine that
/// has none documented gets no choice offered (`arguments(engine:)` is nil), never a choice that
/// silently does nothing.
///
/// While playing, the game's own Alt+Enter switches between the two. On a Mac that is ⌘Return:
/// Wine's Mac driver sends the Command keys as Alt unless told otherwise (`dlls/winemac.drv/keyboard.c`,
/// `kVK_Command` → `VK_LMENU`), and Cellar never tells it otherwise.
public enum DisplayMode: String, CaseIterable, Sendable {
    /// No switch passed: the game starts the way it last saved, as it would on Windows.
    case game
    case fullScreen = "fullscreen"
    case window

    /// The spellings `normalise` accepts for each, beside the raw value.
    static func named(_ value: String) -> DisplayMode? {
        switch value.trimmingCharacters(in: .whitespaces).lowercased() {
        case "game", "default", "auto":                        return .game
        case "fullscreen", "full-screen", "full_screen", "full": return .fullScreen
        case "window", "windowed":                             return .window
        default:                                               return nil
        }
    }

    /// The engine families Cellar knows a start-up switch for, by the words a profile's `engine`
    /// uses. Each switch is the engine maker's own documented command-line option:
    /// Unreal (`-fullscreen` / `-windowed`), Unity's standalone player (`-screen-fullscreen 1|0`),
    /// and Valve's Source and Source 2 (`-fullscreen` / `-windowed`).
    enum Engine: CaseIterable {
        case unreal, unity, source

        init?(_ engine: String?) {
            guard let words = engine?.lowercased() else { return nil }
            if words.contains("unreal") { self = .unreal }
            else if words.hasPrefix("unity") { self = .unity }
            else if words == "source" || words.hasPrefix("source ") { self = .source }
            else { return nil }
        }
    }

    /// The arguments that start a game on `engine` this way: empty for `.game`, nil when the engine
    /// has no switch Cellar knows (so no choice is offered for it).
    public func arguments(engine: String?) -> [String]? {
        guard let family = Engine(engine) else { return nil }
        switch (self, family) {
        case (.game, _):                          return []
        case (.fullScreen, .unreal), (.fullScreen, .source): return ["-fullscreen"]
        case (.window, .unreal), (.window, .source):         return ["-windowed"]
        case (.fullScreen, .unity):               return ["-screen-fullscreen", "1"]
        case (.window, .unity):                   return ["-screen-fullscreen", "0"]
        }
    }

    /// Whether Cellar can start a game on `engine` full screen or in a window.
    public static func isChoosable(engine: String?) -> Bool { Engine(engine) != nil }

    /// The segment's label on a game's page.
    public var displayTitle: String {
        switch self {
        case .game:       return String(localized: "Game’s Choice")
        case .fullScreen: return String(localized: "Full Screen")
        case .window:     return String(localized: "Window")
        }
    }

    /// The one line on every game's page about switching while it plays. "Many", not "every": a
    /// game can turn Alt+Enter off, and Cellar cannot tell which ones do.
    public static var whilePlayingHint: String {
        String(localized: "While playing, ⌘Return switches between full screen and a window in many games.")
    }
}
