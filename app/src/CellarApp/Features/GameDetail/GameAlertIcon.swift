import CellarDomain
import AppKit
import SwiftUI
import CellarUI

/// A game's cover as an alert icon, so a question about a game shows that game rather than Cellar's
/// keg (Kenneth, #266: "show the game icon of what you are going to remove").
///
/// The same chain as the sidebar's cover, without waiting on the network: the store art the library
/// already downloaded (from the shared URL cache), the icon extracted from the game, and Cellar's
/// generated cover otherwise. Drawn upright at 2:3 in the alert's square slot, with rounded corners.
@MainActor
enum GameAlertIcon {
    static let size: CGFloat = 64

    static func image(for game: GameSummary) -> NSImage? {
        let art: Image? = cachedArt(for: game).map { Image(nsImage: $0) }
            ?? game.iconPath.flatMap(NSImage.init(contentsOfFile:)).map { Image(nsImage: $0) }
        let width = size * 2 / 3
        let cover = Group {
            if let art {
                GameArt(art)
            } else {
                GeneratedCover(title: game.name, store: game.store, width: width)
            }
        }
        .frame(width: width, height: size)
        .clipShape(RoundedRectangle(cornerRadius: width * 0.12, style: .continuous))
        .frame(width: size, height: size)

        let renderer = ImageRenderer(content: cover)
        renderer.scale = 2
        return renderer.nsImage
    }

    /// The portrait art, only if the library has already fetched it: an alert is no place to wait.
    private static func cachedArt(for game: GameSummary) -> NSImage? {
        guard let url = Artwork.portrait(game),
              let cached = URLCache.shared.cachedResponse(for: URLRequest(url: url)) else { return nil }
        return NSImage(data: cached.data)
    }
}
