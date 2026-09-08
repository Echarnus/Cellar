import SwiftUI
import AppKit
import CellarKit

/// The storefronts' own marks.
///
/// A generic game-controller glyph tells a player nothing; the Steam valve and the Battle.net orb
/// are recognised instantly, and that recognition is the whole point of separating the stores.
///
/// There are two ways to get one on screen, and Cellar uses both, in this order:
///
/// 1. **The store's real artwork, from the copy already on this machine** — the `.icns` inside
///    Steam.app, or the `.ico` Windows Steam keeps in the bottle Cellar itself installed. That is
///    Valve's own mark, not an impression of it, and it costs nothing to be exact.
/// 2. **A vector mark drawn here**, when the store isn't installed and there is nothing to point at.
///
/// What Cellar never does is **ship** anyone's logo. Every storefront's brand guidelines forbid it
/// in some form (see `StoreIcon` and `docs/LEGAL.md`), and a logo file in `Resources/` would also be
/// artwork this GPL-3.0 repository has no right to relicense. Grafting from the player's own install
/// is the same move Cellar makes for Apple's D3DMetal, for the same reason.
///
/// So the drawn marks below are not placeholders — for a store the player hasn't installed they are
/// what ships, and they have to be good. Use is nominative either way: the mark labels which store a
/// game came from. It is not a badge of endorsement, and Cellar says so in `NOTICE`.
struct StoreMark: View {
    let store: GameStore
    var size: CGFloat = 14

    var body: some View {
        if let image = StoreIcons.image(for: store) {
            // Clipped to a circle so every store's mark occupies the same footprint, whichever
            // source it came from: Steam's `.ico` is already a circle on transparency, and a
            // macOS app icon's squircle trims to one cleanly. `StoreBadge` rings that footprint,
            // and the ring can only sit right if the shape underneath is predictable.
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
                .clipShape(Circle())
        } else {
            drawn
        }
    }

    @ViewBuilder private var drawn: some View {
        switch store {
        case .steam:      SteamMark(size: size)
        case .battlenet:  BattleNetMark(size: size)
        case .gog:        GOGMark(size: size)
        case .standalone: StandaloneMark(size: size)
        }
    }
}

/// Resolved store artwork, looked up once per store and kept for the life of the process.
///
/// `StoreMark` renders in every library row, so this has to be a dictionary lookup by the second
/// call. The first call touches the filesystem — a handful of `fileExists` checks, and at most one
/// `sips` conversion the very first time a bottle's `.ico` is seen. That happens once ever, not
/// once per launch, because the converted PNG is cached on disk by `StoreIcon`.
enum StoreIcons {
    private static var cache: [GameStore: NSImage?] = [:]

    static func image(for store: GameStore) -> NSImage? {
        if let known = cache[store] { return known }
        let image = StoreIcon.mark(store).flatMap { NSImage(contentsOf: $0) }
        cache[store] = image
        return image
    }

    /// Forget what was resolved, so a store that has just been installed starts showing its own
    /// mark without a relaunch. Called when the library reloads after `cellar setup`.
    static func refresh() { cache.removeAll() }
}

/// Valve's mark: the large valve wheel, the connecting rod, and the smaller wheel below it, on the
/// dark navy Steam has used since 2013. The big wheel sits **upper-right** and the small one
/// lower-left, with the rod running out to the lower-left edge — mirroring that reads as a
/// dumbbell, which is the tell that a Steam logo has been drawn from memory.
private struct SteamMark: View {
    let size: CGFloat

    private var navy: Color { Color(.sRGB, red: 0.10, green: 0.16, blue: 0.22, opacity: 1) }

    var body: some View {
        ZStack {
            Circle().fill(
                LinearGradient(colors: [Color(.sRGB, red: 0.16, green: 0.24, blue: 0.33, opacity: 1), navy],
                               startPoint: .topLeading, endPoint: .bottomTrailing))

            // The rod, drawn first so both wheels sit on top of its ends. It runs from the small
            // wheel out past the lower-left edge of the disc, as in Valve's mark.
            Capsule()
                .fill(.white)
                .frame(width: size * 0.50, height: size * 0.10)
                .rotationEffect(.degrees(-45))
                .offset(x: -size * 0.09, y: size * 0.09)

            // Upper-right valve wheel — the big one. Its hole has to stay open at 12pt, which is
            // what sets every other proportion here.
            ZStack {
                Circle().fill(.white).frame(width: size * 0.44)
                Circle().fill(navy).frame(width: size * 0.19)
            }
            .offset(x: size * 0.13, y: -size * 0.13)

            // Lower-left wheel, roughly half the size — the proportion that makes it read as Steam.
            ZStack {
                Circle().fill(.white).frame(width: size * 0.26)
                Circle().fill(navy).frame(width: size * 0.10)
            }
            .offset(x: -size * 0.14, y: size * 0.14)
        }
        .frame(width: size, height: size)
    }
}

/// Blizzard's mark: the Battle.net orb — two hooked arcs winding into a portal, on its cyan-blue.
private struct BattleNetMark: View {
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle().fill(
                LinearGradient(colors: [Color(.sRGB, red: 0.16, green: 0.73, blue: 1.0, opacity: 1),
                                        Color(.sRGB, red: 0.0, green: 0.40, blue: 0.85, opacity: 1)],
                               startPoint: .top, endPoint: .bottom))

            // Outer sweep: most of a ring, opened at the lower right so it reads as a spiral
            // rather than a plain circle.
            Circle()
                .trim(from: 0.06, to: 0.78)
                .stroke(.white, style: StrokeStyle(lineWidth: size * 0.13, lineCap: .round))
                .frame(width: size * 0.60)
                .rotationEffect(.degrees(-90))

            // Inner sweep, wound the other way — the hook that closes the orb.
            Circle()
                .trim(from: 0.06, to: 0.72)
                .stroke(.white, style: StrokeStyle(lineWidth: size * 0.13, lineCap: .round))
                .frame(width: size * 0.28)
                .rotationEffect(.degrees(90))
        }
        .frame(width: size, height: size)
    }
}

/// GOG's mark: the purple disc with its initial. GOG's own logo is a wordmark, and "GOG" set at
/// 14pt is a smudge — so the mark keeps the brand's purple and its first letter, which is what
/// actually reads at library-row size. Purple also does real work here: Steam and Battle.net are
/// both blue, so GOG is the one store colour can help distinguish (it still never carries it alone).
/// GOG is also the store this is most often what ships: Cellar talks to GOG over HTTP and never
/// stands a Galaxy client up, so there is usually no install to take real artwork from.
private struct GOGMark: View {
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle().fill(
                LinearGradient(colors: [Color(.sRGB, red: 0.72, green: 0.38, blue: 0.90, opacity: 1),
                                        Color(.sRGB, red: 0.44, green: 0.16, blue: 0.66, opacity: 1)],
                               startPoint: .topLeading, endPoint: .bottomTrailing))
            Text("G")
                .font(.system(size: size * 0.66, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                // The glyph's own bearing sits it slightly high in the circle; nudge it back.
                .offset(y: size * 0.01)
        }
        .frame(width: size, height: size)
    }
}

/// No store: a plain box, so "these files are just on disk" reads as deliberately different from
/// the branded marks rather than as a store Cellar failed to identify.
private struct StandaloneMark: View {
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle().fill(Color(.sRGB, red: 0.42, green: 0.44, blue: 0.48, opacity: 1))
            Image(systemName: "shippingbox.fill")
                .font(.system(size: size * 0.5, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
    }
}
