import CoreGraphics
import Foundation
import SwiftUI
import Testing
import CellarUI

/// Game art keeps its proportions in a slot of any shape (#163).
///
/// Each test draws a synthetic piece of art — a red disc on a blue field — into a slot of a
/// different shape, and measures the disc. A stretched image draws an ellipse; art that keeps its
/// aspect ratio draws a circle, whatever the slot.
@MainActor
@Suite("Game art")
struct GameArtTests {

    /// `width`×`height` pixels of blue, with a red disc of `discFraction` × the short side centred on it.
    private static func art(width: Int, height: Int, discFraction: Double = 0.25) throws -> Image {
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let ctx = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                         bytesPerRow: 0, space: space,
                                         bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        ctx.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let d = Double(min(width, height)) * discFraction
        ctx.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        ctx.fillEllipse(in: CGRect(x: (Double(width) - d) / 2, y: (Double(height) - d) / 2, width: d, height: d))
        let cg = try #require(ctx.makeImage())
        return Image(decorative: cg, scale: 1)
    }

    private static func isRed(_ p: Snapshot.Bitmap.Pixel) -> Bool { p.r > 0.6 && p.g < 0.35 && p.b < 0.35 }
    private static func isBlue(_ p: Snapshot.Bitmap.Pixel) -> Bool { p.b > 0.6 && p.r < 0.35 && p.g < 0.35 }

    /// Width ÷ height of the red disc's bounding box: 1 for a circle, far from it for a stretched one.
    private static func discAspect(_ bitmap: Snapshot.Bitmap) throws -> Double {
        var minX = Int.max, maxX = Int.min, minY = Int.max, maxY = Int.min
        bitmap.forEachPixel { x, y, p in
            guard isRed(p) else { return }
            minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
        }
        try #require(minX <= maxX, "the disc was not drawn at all")
        return Double(maxX - minX + 1) / Double(maxY - minY + 1)
    }

    /// `view` in a `slot`-sized frame, centred on a grey canvas `canvas` points large.
    private static func render(_ view: some View, slot: CGSize, canvas: CGSize) -> Snapshot.Bitmap {
        Snapshot.render(view.frame(width: slot.width, height: slot.height), size: canvas, scale: 2)
    }

    @Test("A 3:1 hero in a much wider banner fills it without being stretched")
    func heroFillsWideBanner() throws {
        // Steam's library_hero is 3840×1240; the detail header is the window's width by 240 points.
        let hero = try Self.art(width: 384, height: 124)
        let bitmap = Self.render(GameArt(hero), slot: CGSize(width: 400, height: 60),
                                 canvas: CGSize(width: 400, height: 60))
        let aspect = try Self.discAspect(bitmap)
        #expect(abs(aspect - 1) < 0.08, "the disc is \(aspect):1 — the art was stretched")
        // Filled: every corner of the banner is art, not an empty edge.
        for (x, y) in [(0, 0), (bitmap.width - 1, 0), (0, bitmap.height - 1), (bitmap.width - 1, bitmap.height - 1)] {
            #expect(Self.isBlue(bitmap[x, y]), "corner \(x),\(y) is not covered by the art")
        }
    }

    @Test("Art that overhangs its slot is cropped, never drawn over its neighbours")
    func fillIsClipped() throws {
        let hero = try Self.art(width: 384, height: 124)
        // A 400×60 slot in the middle of a 400×180 canvas: the scaled art would be 129 points tall.
        let bitmap = Self.render(GameArt(hero), slot: CGSize(width: 400, height: 60),
                                 canvas: CGSize(width: 400, height: 180))
        let slotTop = bitmap.height / 3, slotBottom = 2 * bitmap.height / 3
        for x in stride(from: 0, to: bitmap.width, by: 37) {
            #expect(!Self.isBlue(bitmap[x, 4]), "art leaked above its slot at x=\(x)")
            #expect(!Self.isBlue(bitmap[x, bitmap.height - 5]), "art leaked below its slot at x=\(x)")
            #expect(Self.isBlue(bitmap[x, slotTop + 4]) || Self.isRed(bitmap[x, slotTop + 4]))
            #expect(Self.isBlue(bitmap[x, slotBottom - 5]) || Self.isRed(bitmap[x, slotBottom - 5]))
        }
    }

    @Test("A square icon fills a 2:3 cover and stays round")
    func squareIconInPortraitCover() throws {
        let icon = try Self.art(width: 128, height: 128, discFraction: 0.5)
        let bitmap = Self.render(GameArt(icon), slot: CGSize(width: 92, height: 138),
                                 canvas: CGSize(width: 92, height: 138))
        let aspect = try Self.discAspect(bitmap)
        #expect(abs(aspect - 1) < 0.08, "the disc is \(aspect):1 — the icon was stretched")
        #expect(Self.isBlue(bitmap[0, 0]) && Self.isBlue(bitmap[bitmap.width - 1, bitmap.height - 1]))
    }

    @Test("A 2:3 cover at sidebar size keeps its shape")
    func portraitCoverAtSidebarSize() throws {
        let cover = try Self.art(width: 600, height: 900, discFraction: 0.6)
        let bitmap = Self.render(GameArt(cover), slot: CGSize(width: 34, height: 51),
                                 canvas: CGSize(width: 34, height: 51))
        let aspect = try Self.discAspect(bitmap)
        #expect(abs(aspect - 1) < 0.12, "the disc is \(aspect):1 at 68×102 pixels")
    }

    @Test("Fit shows the whole picture, letterboxed")
    func fitLetterboxes() throws {
        let wide = try Self.art(width: 200, height: 100)
        let bitmap = Self.render(GameArt(wide, mode: .fit), slot: CGSize(width: 100, height: 100),
                                 canvas: CGSize(width: 100, height: 100))
        let aspect = try Self.discAspect(bitmap)
        #expect(abs(aspect - 1) < 0.08, "the disc is \(aspect):1")
        let mid = bitmap.width / 2
        #expect(!Self.isBlue(bitmap[mid, 4]), "fit should leave a bar above a wide image")
        #expect(!Self.isBlue(bitmap[mid, bitmap.height - 5]), "and one below it")
        #expect(Self.isBlue(bitmap[2, bitmap.height / 2]), "but reach both sides")
        #expect(Self.isBlue(bitmap[bitmap.width - 3, bitmap.height / 2]))
    }
}
