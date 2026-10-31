import CellarDomain
import SwiftUI
import AppKit

/// The storefronts' own marks.
///
/// A generic game-controller glyph tells a player nothing; the Steam valve and the Battle.net orb
/// are recognised instantly, and that recognition is the whole point of separating the stores.
///
/// There are two ways to get one on screen, and Cellar uses both, in this order:
///
/// 1. **The store's real artwork, from the copy already on this machine** — the `.icns` inside the
///    store's Mac app, the icon Wine extracted from the Windows client's `.exe` while setting the
///    bottle up, or a loose `.ico` the client ships. That is the storefront's own mark, not an
///    impression of it, and it costs nothing to be exact.
/// 2. **A vector mark drawn here**, when the store isn't installed and there is nothing to point at.
///
/// What Cellar never does is **ship** anyone's logo. Cellar's hard rule is that it redistributes
/// nobody's proprietary assets (`AGENTS.md`, `docs/LEGAL.md`), and a bundled PNG of Valve's or
/// Blizzard's logo would break it — as well as being artwork this GPL-3.0 repository has no right
/// to relicense. Grafting from the player's own install is the same move Cellar makes for Apple's
/// D3DMetal, for the same reason.
///
/// So the drawn marks below are not placeholders — for a store the player hasn't installed they are
/// what ships, and they have to be good. Use is nominative either way: the mark labels which store a
/// game came from. It is not a badge of endorsement, and Cellar says so in `NOTICE`.
public struct StoreMark: View {
    let store: GameStore
    var size: CGFloat
    /// Whether to prefer the store's real artwork when this machine has it.
    ///
    /// Almost always yes. It is `false` only where the *drawn* mark is the subject: the snapshot
    /// tests measure the vectors, and what they must measure cannot depend on which storefronts
    /// happen to be installed on the machine running them — otherwise the suite passes or fails by
    /// accident of the developer's Mac, and stops saying anything about what ships.
    var artwork: Bool

    public init(store: GameStore, size: CGFloat = 14, artwork: Bool = true) {
        self.store = store
        self.size = size
        self.artwork = artwork
    }

    public var body: some View {
        mark
            // Decorative to VoiceOver. A mark never stands alone — position + mark + word is the rule
            // (skills/ux.md) — so the word beside it is what gets read, once, rather than "Steam" twice.
            .accessibilityHidden(true)
    }

    @ViewBuilder private var mark: some View {
        if artwork, let image = StoreIcons.image(for: store) {
            // Clipped to the mark's own silhouette rather than always a circle: GOG's outline is a
            // rounded tile, and `StoreBadge` rings whatever shape this returns. Real artwork has to
            // occupy the same footprint as the drawn mark, or the ring stops fitting.
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
                .clipShape(StoreMark.outline(of: store, size: size))
        } else {
            drawn
        }
    }

    @ViewBuilder private var drawn: some View {
        switch store {
        case .steam:      SteamMark(size: size)
        case .battlenet:  BattleNetMark(size: size)
        case .gog:        GOGMark(size: size)
        }
    }

    /// The mark's own silhouette, for anything that has to ring or clip it.
    ///
    /// Not every mark is a disc: GOG's is a rounded tile, and a badge ring that assumed a circle
    /// would cut its corners off. Anything drawing *around* a mark asks here rather than guessing.
    public static func outline(of store: GameStore, size: CGFloat) -> AnyInsettableShape {
        switch store {
        case .gog:  AnyInsettableShape(RoundedRectangle(cornerRadius: size * GOGMark.corner, style: .continuous))
        default:    AnyInsettableShape(Circle())
        }
    }
}
