import CellarDomain
import SwiftUI

/// The entries of a game's menu, top level then **Troubleshooting** — the same content inside the
/// page's "…" button and the library's right-click menu.
struct GameMenuContent: View {
    let game: GameSummary
    let actions: GameActions
    @Binding var language: GameLanguageMenu.Selection

    var body: some View {
        let menu = GameMenu(game: game)
        ForEach(Array(menu.main.enumerated()), id: \.offset) { index, group in
            if index > 0 { Divider() }
            ForEach(group, id: \.self) { item in entry(item) }
        }
        Divider()
        Menu {
            ForEach(Array(menu.troubleshooting.enumerated()), id: \.offset) { index, group in
                if index > 0 { Divider() }
                ForEach(group, id: \.self) { item in entry(item) }
            }
        } label: {
            Text("Troubleshooting")
        }
    }

    @ViewBuilder private func entry(_ item: GameMenu.Item) -> some View {
        let title = item.title(for: game)
        switch item {
        case .language:
            GameLanguageMenu(game: game, state: $language)
        case .moveBack:
            Button(title) { actions.perform(item) }.disabled(game.missingDrive != nil)
        default:
            Button(title, role: item.isDestructive ? .destructive : nil) { actions.perform(item) }
        }
    }
}
