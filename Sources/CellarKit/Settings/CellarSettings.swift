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
}
