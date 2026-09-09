import SwiftUI
import AppKit

/// Renders a SwiftUI view to pixels **without launching the app**.
///
/// This is the piece that lets Cellar's user-visible work be verified in the background. The repo's
/// rule is that a GUI change is verified by looking at it, never by reading the diff — but "look at
/// it" used to mean installing the app and launching it, which blocks whoever is at the keyboard.
/// Rendering offscreen keeps the rule (something really is drawn, and the pixels are inspected) and
/// gives it back as a test that runs in a terminal.
///
/// It is a *complement* to launching, not a replacement: a snapshot proves a view draws what it is
/// supposed to draw. It cannot prove the window resizes, the menu works, or the click lands.
public enum Snapshot {

    /// A rendered view, as pixels that can be measured.
    public struct Bitmap: Sendable {
        public let width: Int
        public let height: Int
        /// Opaque sRGB, 4 bytes per pixel, row-major from the top-left.
        public let rgba: [UInt8]

        public init(width: Int, height: Int, rgba: [UInt8]) {
            self.width = width
            self.height = height
            self.rgba = rgba
        }

        public struct Pixel: Equatable, Sendable {
            public let r: Double, g: Double, b: Double, a: Double

            /// Rough perceptual lightness, 0…1 — enough to tell a mark's white ink from its disc.
            public var luminance: Double { 0.2126 * r + 0.7152 * g + 0.0722 * b }
        }

        public subscript(x: Int, y: Int) -> Pixel {
            precondition(x >= 0 && x < width && y >= 0 && y < height,
                         "pixel \(x),\(y) is outside \(width)x\(height)")
            let i = (y * width + x) * 4
            return Pixel(r: Double(rgba[i]) / 255, g: Double(rgba[i + 1]) / 255,
                         b: Double(rgba[i + 2]) / 255, a: Double(rgba[i + 3]) / 255)
        }

        /// Every pixel, with its coordinates — the basis for the geometry assertions.
        public func forEachPixel(_ body: (Int, Int, Pixel) -> Void) {
            for y in 0..<height {
                for x in 0..<width {
                    body(x, y, self[x, y])
                }
            }
        }

        public func pngData() -> Data? {
            guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                                             bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                             isPlanar: false, colorSpaceName: .deviceRGB,
                                             bytesPerRow: width * 4, bitsPerPixel: 32)
            else { return nil }
            rgba.withUnsafeBufferPointer { src in
                if let dst = rep.bitmapData, let base = src.baseAddress {
                    dst.update(from: base, count: src.count)
                }
            }
            return rep.representation(using: .png, properties: [:])
        }
    }

    /// Draw `view` at `size` points, at `scale`x, on an opaque `background`.
    ///
    /// The background is opaque on purpose: a mark is designed against the app's chrome, and judging
    /// a white-inked logo on a transparent checkerboard is judging something the player never sees.
    @MainActor
    public static func render<V: View>(_ view: V,
                                       size: CGSize,
                                       scale: CGFloat = 2,
                                       background: Color = Color(white: 0.13)) -> Bitmap {
        let renderer = ImageRenderer(content:
            ZStack {
                background
                view
            }
            .frame(width: size.width, height: size.height)
        )
        renderer.scale = scale
        renderer.isOpaque = true

        let pixelsWide = Int((size.width * scale).rounded())
        let pixelsHigh = Int((size.height * scale).rounded())
        var rgba = [UInt8](repeating: 0, count: pixelsWide * pixelsHigh * 4)

        // Draw straight into our own sRGB buffer, so the bytes a test reads are the bytes that were
        // rasterised — no colour-space guessing on the way out of an NSImage.
        rgba.withUnsafeMutableBytes { raw in
            guard let space = CGColorSpace(name: CGColorSpace.sRGB),
                  let ctx = CGContext(data: raw.baseAddress, width: pixelsWide, height: pixelsHigh,
                                      bitsPerComponent: 8, bytesPerRow: pixelsWide * 4, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return }
            renderer.render { _, draw in
                ctx.saveGState()
                ctx.scaleBy(x: scale, y: scale)
                draw(ctx)
                ctx.restoreGState()
            }
        }

        return Bitmap(width: pixelsWide, height: pixelsHigh, rgba: rgba)
    }
}
