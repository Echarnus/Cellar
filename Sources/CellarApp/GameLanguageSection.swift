import CellarDomain
import SwiftUI
import CellarKit

/// Settings › General › Language: the language every game, and the store client that starts it,
/// runs in. Follows the Mac unless the player picks one; a game can still have its own (its •••
/// menu, `GameLanguageMenu`).
///
/// Writes through CellarKit directly rather than through the `cellar` subprocess: it is one line in
/// a settings file, and the app's runner refuses work while a game is playing — a picker that
/// silently did nothing mid-game would be worse than one that bypasses it.
struct GameLanguageSection: View {
    /// nil = follow the Mac. Loaded after the first layout, never from the body (skills/swift.md).
    @State private var chosen: GameLanguage?
    @State private var failure: String?
    private let system = GameLanguage.system()

    var body: some View {
        Section("Language") {
            Picker("Games run in", selection: Binding(get: { chosen }, set: save)) {
                Text("Same as my Mac — \(system.nativeName)").tag(GameLanguage?.none)
                Divider()
                ForEach(GameLanguage.allCases, id: \.self) { language in
                    Text(language.nativeName).tag(GameLanguage?.some(language))
                }
            }
            Text("Games and Steam start in this language from their next launch. A game that doesn't include it shows English. To give one game its own language, use the ••• menu on its page.")
                .font(.caption).foregroundStyle(.secondary)
            if let failure {
                Label(failure, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(.red)
            }
        }
        .task { chosen = CellarSettings.language.flatMap(GameLanguage.named) }
    }

    private func save(_ language: GameLanguage?) {
        do {
            try CellarSettings.setLanguage(language)
            chosen = language
            failure = nil
        } catch {
            failure = "Couldn't save the language: \(CellarLog.describe(error))"
        }
    }
}

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
