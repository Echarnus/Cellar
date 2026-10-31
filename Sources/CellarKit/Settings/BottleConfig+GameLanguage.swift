import CellarDomain
import Foundation

extension BottleConfig {
    /// This bottle's own language, or nil to use the one for every game.
    public static func language(_ url: URL) -> String? { fields(url)[CellarSettings.languageKey] }

    public static func setLanguage(_ language: GameLanguage?, in url: URL) throws {
        if let language {
            try set(key: CellarSettings.languageKey, to: language.code, section: "general", in: url)
        } else {
            try unset(key: CellarSettings.languageKey, in: url)
        }
    }
}
