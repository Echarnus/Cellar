import SwiftUI
import AppKit
import CellarKit

/// Steam's public CDN artwork for a game (no auth). Used to make the library look like Steam.
enum Artwork {
    static func url(_ appID: Int?, _ kind: String) -> URL? {
        guard let appID else { return nil }
        return URL(string: "https://cdn.cloudflare.steamstatic.com/steam/apps/\(appID)/\(kind)")
    }
    static func portrait(_ appID: Int?) -> URL? { url(appID, "library_600x900.jpg") }
    static func hero(_ appID: Int?) -> URL? { url(appID, "library_hero.jpg") }
    static func logo(_ appID: Int?) -> URL? { url(appID, "logo.png") }
}

/// Remote image with a graceful fallback (the extracted .icns, then a glyph). AsyncImage handles
/// fetching and URLCache handles caching.
struct RemoteArt<Fallback: View>: View {
    let url: URL?
    let fallback: Fallback
    init(_ url: URL?, @ViewBuilder fallback: () -> Fallback) { self.url = url; self.fallback = fallback() }

    var body: some View {
        if let url {
            AsyncImage(url: url, transaction: Transaction(animation: .easeOut(duration: 0.25))) { phase in
                switch phase {
                case .success(let img): img.resizable()
                case .empty: ZStack { fallback; ProgressView().controlSize(.small) }
                default: fallback
                }
            }
        } else {
            fallback
        }
    }
}

/// A game's own icon from its extracted `.icns`, with a placeholder fallback.
struct GameIcon: View {
    let path: String?
    let size: CGFloat
    var body: some View {
        ZStack {
            if let path, let img = NSImage(contentsOfFile: path) {
                Image(nsImage: img).resizable()
            } else {
                LinearGradient(colors: [Color(.sRGB, red: 0.48, green: 0.12, blue: 0.23),
                                        Color(.sRGB, red: 0.24, green: 0.06, blue: 0.12)],
                               startPoint: .top, endPoint: .bottom)
                Image(systemName: "wineglass").font(.system(size: size*0.42, weight: .medium)).foregroundStyle(.white.opacity(0.85))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
    }
}
