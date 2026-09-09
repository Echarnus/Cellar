import SwiftUI
import AppKit
import CellarKit
import CellarUI

/// Where a game's artwork comes from, per store.
///
/// Steam publishes cover and banner art for every AppID on a public CDN, which is why the library
/// looks like a storefront for Steam titles. No other store Cellar speaks to does: Blizzard's art
/// is not addressable by product code and is not ours to hotlink. So the chain is: art the profile
/// declares → the store's public CDN if it has one → Cellar's own generated cover. The last link is
/// not a placeholder to be embarrassed about; it is the design for every store but one.
enum Artwork {
    static func steamCDN(_ appID: Int?, _ kind: String) -> URL? {
        guard let appID else { return nil }
        return URL(string: "https://cdn.cloudflare.steamstatic.com/steam/apps/\(appID)/\(kind)")
    }

    /// 600×900 cover. `artworkAppID` is nil for stores with no public artwork.
    static func portrait(_ game: GameSummary) -> URL? {
        game.artPortraitURL.flatMap(URL.init(string:))
            ?? steamCDN(game.artworkAppID, "library_600x900.jpg")
    }

    /// Wide banner behind the detail header.
    static func hero(_ game: GameSummary) -> URL? {
        game.artHeroURL.flatMap(URL.init(string:))
            ?? steamCDN(game.artworkAppID, "library_hero.jpg")
    }
}

/// Remote image with a graceful fallback. `AsyncImage` handles fetching, `URLCache` the caching.
/// The fallback is shown immediately while loading rather than a spinner over emptiness — for a
/// store with no CDN the fallback *is* the artwork, and it should never flash.
struct RemoteArt<Fallback: View>: View {
    let url: URL?
    let fallback: Fallback
    init(_ url: URL?, @ViewBuilder fallback: () -> Fallback) { self.url = url; self.fallback = fallback() }

    var body: some View {
        if let url {
            AsyncImage(url: url, transaction: Transaction(animation: .easeOut(duration: 0.25))) { phase in
                switch phase {
                case .success(let image): image.resizable()
                default: fallback
                }
            }
        } else {
            fallback
        }
    }
}

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
    }
}

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
