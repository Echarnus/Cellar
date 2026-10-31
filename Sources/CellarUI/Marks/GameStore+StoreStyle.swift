import CellarDomain
import SwiftUI
import CellarKit

/// How a store looks and reads in the app.
///
/// Cellar now speaks to more than one storefront, and the player has to be able to tell — at a
/// glance, from across the room — whether a game comes from Steam or from Battle.net, because the
/// answer changes what the next button does. Three signals carry that, always together:
///
/// 1. **Position** — the library is grouped by store, so a game's neighbours already tell you.
/// 2. **A mark** — the store's own logo (see `StoreMark`): its real icon where the store is
///    installed on this machine, a vector Cellar draws where it isn't. On the cover and in the
///    header. A real mark is recognised where a generic glyph has to be read.
/// 3. **A word** — the store's name, spelled out, next to the mark.
///
/// No signal ever stands alone. Steam's and Battle.net's brands are both blue, so colour could
/// never have carried this by itself; and a mark with no label is a puzzle for anyone who has not
/// met it before. Position, mark and word travel together everywhere.
extension GameStore {
    /// The store's accent, from CellarKit's descriptor so the CLI and the app agree.
    public var tint: Color {
        let rgb = descriptor.accentColorComponents
        return Color(.sRGB, red: rgb.red, green: rgb.green, blue: rgb.blue, opacity: 1)
    }

    public var symbol: String { descriptor.symbolName }
}
