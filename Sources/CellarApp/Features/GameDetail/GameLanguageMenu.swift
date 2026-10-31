import CellarDomain
import SwiftUI
import CellarKit

/// The game page's language submenu: this game's own language, or the one every game uses. Kept in
/// the game's bottle (`bottle.toml`), so it needs one — a game not set up yet has nowhere to keep it.
///
/// Its state lives in `GameDetailView` (`GameLanguageMenu.Selection`), loaded with the page: lifecycle
/// modifiers inside a menu's content are not dependable once AppKit has turned it into menu items.
struct GameLanguageMenu: View {
    struct Selection: Equatable {
        var own: GameLanguage?
        var everyGame: GameLanguage = .system()

        static func load(_ game: GameSummary) -> Selection {
            Selection(own: BottleConfig.language(BottleConfig.url(forBottle: game.bottleName)).flatMap(GameLanguage.named),
                  everyGame: LanguageChoice.global().language)
        }
    }

    let game: GameSummary
    @Binding var state: Selection

    var body: some View {
        Picker("Language", selection: Binding(get: { state.own }, set: save)) {
            Text("Same as every game — \(state.everyGame.nativeName)").tag(GameLanguage?.none)
            Divider()
            ForEach(GameLanguage.allCases, id: \.self) { language in
                Text(language.nativeName).tag(GameLanguage?.some(language))
            }
        }
    }

    private func save(_ language: GameLanguage?) {
        // A menu item has nowhere to show an error; a write that failed leaves the checkmark
        // where it was, which is the truth.
        let file = BottleConfig.url(forBottle: game.bottleName)
        guard (try? BottleConfig.setLanguage(language, in: file)) != nil else { return }
        state.own = language
    }
}
