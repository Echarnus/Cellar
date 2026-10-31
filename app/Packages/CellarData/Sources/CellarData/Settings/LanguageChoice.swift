import CellarDomain
import Foundation

/// Which language a game will get, and why — so `cellar language` and the app can say whether it
/// is following the Mac or a choice the player made.
public struct LanguageChoice: Equatable, Sendable {
    public enum Source: String, Sendable { case system, allGames, thisGame }

    public let language: GameLanguage
    public let source: Source

    /// Later wins: the Mac's language → the player's choice for every game → their choice for this
    /// game. A value that doesn't name a language is ignored, so the layer under it stands.
    public static func resolve(game: String?, global: String?,
                               system: GameLanguage = .system()) -> LanguageChoice {
        if let game = game.flatMap(GameLanguage.named) { return LanguageChoice(language: game, source: .thisGame) }
        if let global = global.flatMap(GameLanguage.named) { return LanguageChoice(language: global, source: .allGames) }
        return LanguageChoice(language: system, source: .system)
    }

    /// The one for every game, from Cellar's settings file.
    public static func global(system: GameLanguage = .system()) -> LanguageChoice {
        resolve(game: nil, global: CellarSettings.language, system: system)
    }
}
