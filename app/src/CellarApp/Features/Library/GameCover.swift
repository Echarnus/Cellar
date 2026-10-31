import CellarDomain
import SwiftUI
import AppKit
import CellarData
import CellarUI

/// A game's cover, in one place so the sidebar and the header can never disagree about what a
/// game looks like: store art if there is any, the icon extracted from the bottle if not, and
/// Cellar's generated cover otherwise. The store's badge rides along in the corner.
struct GameCover: View {
    let game: GameSummary
    /// Cover width; height follows the 2:3 key-art ratio.
    let width: CGFloat
    var showsBadge = true

    private var height: CGFloat { width * 1.5 }

    var body: some View {
        RemoteArt(Artwork.portrait(game)) {
            if let path = game.iconPath, let image = NSImage(contentsOfFile: path) {
                // An extracted .icns is square; fill the cover with it rather than letterboxing.
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                GeneratedCover(title: game.name, store: game.store, width: width)
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: width * 0.12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: width * 0.12, style: .continuous)
                .strokeBorder(.white.opacity(0.10), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.28), radius: width * 0.06, y: width * 0.03)
        .overlay(alignment: .bottomTrailing) {
            if showsBadge {
                StoreBadge(store: game.store, diameter: max(14, width * 0.30))
                    .offset(x: width * 0.10, y: width * 0.10)
            }
        }
        // Every cover sits beside the game's name in words (the sidebar row, the page header, the
        // launch splash), so to VoiceOver the art is decoration, not a second reading of the title.
        .accessibilityHidden(true)
    }
}
