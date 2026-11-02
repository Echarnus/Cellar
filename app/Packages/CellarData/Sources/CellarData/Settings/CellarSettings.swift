import CellarDomain
import Foundation

/// Cellar-wide settings both the CLI and the app read: `settings.toml` beside the bottles. A file
/// rather than `UserDefaults`, because the app and the `cellar` binary it drives are two processes
/// with two defaults domains, and a choice made in one has to reach a game started by the other.
public enum CellarSettings {
    public static var url: URL { Paths.appSupport.appendingPathComponent("settings.toml") }

    /// The language every game uses unless it has its own; nil means follow the Mac.
    public static var language: String? { BottleConfig.fields(url)[languageKey] }

    public static func setLanguage(_ language: GameLanguage?) throws {
        if let language {
            try BottleConfig.set(key: languageKey, to: language.code, section: "general", in: url)
        } else {
            try BottleConfig.unset(key: languageKey, in: url)
        }
    }

    static let languageKey = "language"

    // MARK: - Display and performance, for every game

    /// The switches a player sets once for every game, in Settings: taste, not crash workarounds.
    /// A game's own page can still differ, and a profile that needs a value for its game still
    /// sets it — the order is in `PerformanceSettings.resolve`.
    public static let everyGameSettings: [PerformanceSetting] = [.retina, .metalFXUpscaling, .metalHUD]

    /// The every-game switches set in `settings.toml`, by key. Only those three are read from the
    /// file: a hand-written `metal_validation` there must not slow every game down.
    public static func performance(at url: URL = url) -> [String: String] {
        let keys = Set(everyGameSettings.map(\.key))
        return BottleConfig.fields(url).filter { keys.contains($0.key) }
    }

    /// Whether `setting` is on for every game.
    public static func isOn(_ setting: PerformanceSetting, at url: URL = url) -> Bool {
        performance(at: url)[setting.key] == "true"
    }

    public static func set(_ setting: PerformanceSetting, on: Bool, at url: URL = url) throws {
        guard everyGameSettings.contains(setting) else {
            throw CellarError.invalidArgument("\(setting.key) is set per game, not for every game.")
        }
        try BottleConfig.set(key: setting.key, to: on ? "true" : "false", section: "performance", in: url)
    }
}
