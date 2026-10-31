import CellarDomain
import SwiftUI
import AppKit
import CellarKit

/// GOG's mark: the white tile with `gog` over `com` in dark blocky lowercase.
///
/// Cellar used to draw a purple disc with a "G" on it. That was an invention — GOG has never used
/// it — and inventing a competitor's logo is the one thing worse than drawing it badly: the player
/// learns a mark that will not match anything they see on gog.com or in GOG Galaxy.
///
/// The real mark is a **rounded white tile**, two lines of stencil-blocky lowercase inside it. It is
/// the odd one out among the marks — light where the others are saturated, square where the others
/// are round — and that is an advantage, not a problem: it is told apart by shape and by value, not
/// by hue, which is what `skills/ux.md` asks for. The letters are drawn from square strokes rather
/// than set in a font, so nothing depends on what is installed and the counters stay open at 11pt.
///
/// The tile keeps a hairline edge so it does not dissolve into a light-mode background.
struct GOGMark: View {
    let size: CGFloat

    /// GOG's near-black, warm rather than neutral, as measured off the mark.
    private var ink: Color { Color(.sRGB, red: 0.16, green: 0.14, blue: 0.13, opacity: 1) }

    /// The tile's corner, as a fraction of the mark. Shared with `StoreMark.outline(of:size:)` so a
    /// badge's ring can never disagree with the tile it is drawn around.
    static let corner: CGFloat = 0.13

    /// Below this, the tile carries a single `g` instead of the whole wordmark.
    ///
    /// Not a preference — arithmetic. The full wordmark is 26 grid cells across; in a 12pt chip on a
    /// 2× screen that is 24 device pixels, so every stroke lands on well under one pixel and the mark
    /// greys into static. The player's own screen is the constraint, and rendering the mark at 8× to
    /// admire it is how that got missed the first time. One glyph is 8 cells wide, which leaves the
    /// strokes ~4px and legible.
    ///
    /// It is still GOG's mark, not a new one: their tile, their letterform, their ink — the wordmark
    /// cropped to its first glyph, the way a favicon crops a logotype. The word "GOG" is beside it in
    /// every lockup and section heading regardless, so nothing rests on the glyph alone.
    static let wordmarkFloor: CGFloat = 20

    var body: some View {
        let corner = size * Self.corner
        ZStack {
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .fill(.white)
            BlockWord(lines: size >= Self.wordmarkFloor ? ["gog", "com"] : ["g"])
                .fill(ink)
                .padding(size * (size >= Self.wordmarkFloor ? 0.12 : 0.20))
        }
        .frame(width: size, height: size)
        .overlay(
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .strokeBorder(Color.black.opacity(0.14), lineWidth: max(0.5, size * 0.02)))
    }
}
