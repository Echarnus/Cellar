import CellarDomain
import SwiftUI
import AppKit
import CellarKit
import CellarUI

/// The wide banner behind a game's title. Falls back to a store-tinted wash of the generated
/// cover's palette so the header is always composed, never a grey slab.
struct GameBanner: View {
    let game: GameSummary

    var body: some View {
        RemoteArt(Artwork.hero(game)) {
            ZStack {
                GeneratedCover(title: game.name, store: game.store, width: 420)
                    .blur(radius: 60)
                LinearGradient(colors: [game.store.tint.opacity(0.30), .clear],
                               startPoint: .topTrailing, endPoint: .bottomLeading)
            }
        }
        .accessibilityHidden(true)
    }
}
