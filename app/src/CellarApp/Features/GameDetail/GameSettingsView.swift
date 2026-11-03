import CellarDomain
import SwiftUI

/// A game's settings in a window of their own, opened from Settings… in the sidebar's right-click
/// menu: the same switches as the page's Display and performance section, so the two can't differ.
struct GameSettingsView: View {
    static let width: CGFloat = 460
    static let height: CGFloat = 320

    let game: GameSummary

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if game.bottleExists {
                    GameSettingsSection(game: game)
                } else {
                    Text("\(game.name)'s settings are here once it is installed.")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
        }
        .frame(width: Self.width, height: Self.height)
    }
}
