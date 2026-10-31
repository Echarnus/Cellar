import SwiftUI

/// A piece of game art drawn into a slot whose shape it does not choose — the banner behind a
/// game's title, a cover in the sidebar or the page header.
///
/// Store art comes in whatever shape the store made it (Steam's hero is about 3:1, its cover 2:3, an
/// icon pulled from a bottle is square) and the slot is whatever shape the window is. A bare
/// `resizable()` reconciles the two by stretching, which is how Planet Coaster 2's banner ended up
/// pulled sideways across the header (#163). This keeps the art's own proportions instead:
///
/// - `.fill` covers the whole slot and crops whatever overhangs, centred on `alignment`. The slot
///   never shows an empty edge, and nothing is drawn outside it.
/// - `.fit` shows all of the art, letterboxed inside the slot.
///
/// The slot's size comes from the frame the caller gives it, never from the image, so a 3840-pixel
/// hero cannot push the header wider than the window. High-quality interpolation keeps a large
/// image sharp when it is scaled down to a 34-point cover on a Retina display.
public struct GameArt: View {
    let image: Image
    let mode: ContentMode
    let alignment: Alignment

    public init(_ image: Image, mode: ContentMode = .fill, alignment: Alignment = .center) {
        self.image = image
        self.mode = mode
        self.alignment = alignment
    }

    public var body: some View {
        // `Color.clear` takes the slot's size; the art is laid over it, so its own size never
        // feeds back into the layout, and `clipped()` trims what `.fill` lets overhang.
        Color.clear
            .overlay(alignment: alignment) {
                image
                    .resizable()
                    .interpolation(.high)
                    .antialiased(true)
                    .aspectRatio(contentMode: mode)
            }
            .clipped()
    }
}
