import Foundation
import CellarUI

/// Measurements taken off a rendered mark.
///
/// The point of measuring rather than comparing to a stored image: a golden PNG tells you *that*
/// something changed, this tells you *what is wrong*. "The big wheel is in the lower-left quadrant"
/// is a sentence someone can act on; "42 pixels differ" is not.
///
/// Everything is in fractions of the mark's box, so the same numbers hold at 11pt and at 64pt.
struct MarkGeometry {
    let bitmap: Snapshot.Bitmap
    /// Which way round the mark is drawn. Most are white ink on a saturated disc; GOG's is the
    /// opposite — dark letters on a white tile — and every measurement here needs to know which,
    /// or "the ink" comes out meaning "the background".
    var ink: Ink = .light

    enum Ink { case light, dark }

    static let lightInkThreshold = 0.72
    static let darkInkThreshold = 0.38

    private func isInk(_ p: Snapshot.Bitmap.Pixel) -> Bool {
        switch ink {
        case .light: p.luminance >= Self.lightInkThreshold
        case .dark:  p.luminance <= Self.darkInkThreshold
        }
    }

    /// Fraction of the box covered by ink. Catches a mark that vanished, and a mark that filled in.
    var inkCoverage: Double {
        var n = 0
        bitmap.forEachPixel { _, _, p in if isInk(p) { n += 1 } }
        return Double(n) / Double(bitmap.width * bitmap.height)
    }

    /// Centre of mass of the ink, in fractions of the box: (0,0) top-left, (1,1) bottom-right.
    var inkCentroid: (x: Double, y: Double) {
        var sx = 0.0, sy = 0.0, n = 0.0
        bitmap.forEachPixel { x, y, p in
            if isInk(p) { sx += Double(x); sy += Double(y); n += 1 }
        }
        guard n > 0 else { return (0.5, 0.5) }
        return (sx / n / Double(bitmap.width), sy / n / Double(bitmap.height))
    }

    /// Ink coverage inside one quadrant, as a fraction of that quadrant's area. This is what tells
    /// the big valve wheel from the small one without knowing anything about how it was drawn.
    func inkCoverage(quadrant: Quadrant) -> Double {
        let halfW = bitmap.width / 2, halfH = bitmap.height / 2
        let xs = quadrant.isRight ? halfW..<bitmap.width : 0..<halfW
        let ys = quadrant.isBottom ? halfH..<bitmap.height : 0..<halfH
        var n = 0
        for y in ys { for x in xs where isInk(bitmap[x, y]) { n += 1 } }
        return Double(n) / Double(xs.count * ys.count)
    }

    enum Quadrant: String, CaseIterable {
        case topLeft, topRight, bottomLeft, bottomRight
        var isRight: Bool { self == .topRight || self == .bottomRight }
        var isBottom: Bool { self == .bottomLeft || self == .bottomRight }
    }

    /// Is there a hole at this point — ink around it, but not on it?
    ///
    /// This is the assertion that separates a valve wheel from a dumbbell. A ring has a dark centre
    /// with ink on every side of it; a pinholed disc does not, and that is exactly the mistake that
    /// made the Steam mark read as a keyhole.
    ///
    /// `at` and `probe` are fractions of the box.
    func hasHole(at point: (x: Double, y: Double), probe: Double) -> Bool {
        let cx = Int(point.x * Double(bitmap.width))
        let cy = Int(point.y * Double(bitmap.height))
        let r = Int(probe * Double(min(bitmap.width, bitmap.height)))
        guard cx >= 0, cy >= 0, cx < bitmap.width, cy < bitmap.height else { return false }
        guard !isInk(bitmap[cx, cy]) else { return false }        // the centre must be dark

        // …and ink must be found in all four directions within the probe radius.
        let directions = [(1, 0), (-1, 0), (0, 1), (0, -1)]
        return directions.allSatisfy { dx, dy in
            (1...max(r, 1)).contains { step in
                let x = cx + dx * step, y = cy + dy * step
                guard x >= 0, y >= 0, x < bitmap.width, y < bitmap.height else { return false }
                return isInk(bitmap[x, y])
            }
        }
    }

    /// How wide the opening at this point is, as a fraction of the box — measured by walking out
    /// from the centre until ink is hit, in all four directions, and averaging.
    ///
    /// This is what tells Steam's two wheels apart. Quadrant ink coverage cannot: the handle runs
    /// out to the left rim, so it loads the lower-left quadrant with ink that belongs to no wheel at
    /// all, and the two halves come out within a percentage point of each other whichever way round
    /// the mark is drawn. The *holes* are unambiguous — the big wheel's is roughly twice the small
    /// one's, and mirroring the mark swaps them.
    ///
    /// Returns 0 when there is no opening at that point.
    func holeWidth(at point: (x: Double, y: Double)) -> Double {
        let cx = Int(point.x * Double(bitmap.width))
        let cy = Int(point.y * Double(bitmap.height))
        guard cx >= 0, cy >= 0, cx < bitmap.width, cy < bitmap.height else { return 0 }
        guard !isInk(bitmap[cx, cy]) else { return 0 }

        let span = min(bitmap.width, bitmap.height)
        var total = 0.0
        for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
            var step = 1
            while step < span {
                let x = cx + dx * step, y = cy + dy * step
                guard x >= 0, y >= 0, x < bitmap.width, y < bitmap.height else { return 0 }  // ran off, not a hole
                if isInk(bitmap[x, y]) { break }
                step += 1
            }
            total += Double(step)
        }
        return total / 4 / Double(span)
    }

    /// Fraction of the box that is not the background it was drawn on.
    ///
    /// `inkCoverage` only sees near-white pixels, which is right for a mark's white ink but blind to
    /// a tinted capsule or a coloured label. For "did anything more get drawn here", this is the
    /// measure that counts all of it.
    func coverage(differingFrom background: Snapshot.Bitmap.Pixel, tolerance: Double = 0.06) -> Double {
        var n = 0
        bitmap.forEachPixel { _, _, p in
            let d = max(abs(p.r - background.r), abs(p.g - background.g), abs(p.b - background.b))
            if d > tolerance { n += 1 }
        }
        return Double(n) / Double(bitmap.width * bitmap.height)
    }

    /// How many separate ink blobs there are, 4-connected. A mark drawn as one silhouette is one
    /// blob; a mark whose pieces drifted apart is several.
    var inkBlobCount: Int {
        var seen = [Bool](repeating: false, count: bitmap.width * bitmap.height)
        var blobs = 0
        for startY in 0..<bitmap.height {
            for startX in 0..<bitmap.width {
                let start = startY * bitmap.width + startX
                guard !seen[start], isInk(bitmap[startX, startY]) else { continue }
                blobs += 1
                var stack = [(startX, startY)]
                seen[start] = true
                while let (x, y) = stack.popLast() {
                    for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                        let nx = x + dx, ny = y + dy
                        guard nx >= 0, ny >= 0, nx < bitmap.width, ny < bitmap.height else { continue }
                        let i = ny * bitmap.width + nx
                        guard !seen[i], isInk(bitmap[nx, ny]) else { continue }
                        seen[i] = true
                        stack.append((nx, ny))
                    }
                }
            }
        }
        return blobs
    }

    /// Ink coverage inside one 120° wedge measured from the middle, as a fraction of that wedge.
    ///
    /// This is what tells a three-armed orb from a spiral. Both have an open centre and both look
    /// deliberate; only the orb comes out the same in all three wedges however it is turned.
    /// `turn` is in degrees, clockwise from straight up.
    func inkCoverage(wedge turn: Double, width: Double = 120) -> Double {
        let cx = Double(bitmap.width) / 2, cy = Double(bitmap.height) / 2
        let radius = min(cx, cy)
        var inked = 0, total = 0
        bitmap.forEachPixel { x, y, p in
            let dx = Double(x) - cx, dy = Double(y) - cy
            guard dx * dx + dy * dy <= radius * radius else { return }
            // Angle clockwise from straight up, 0…360.
            var angle = atan2(dx, -dy) * 180 / .pi
            if angle < 0 { angle += 360 }
            var delta = abs(angle - turn)
            if delta > 180 { delta = 360 - delta }
            guard delta <= width / 2 else { return }
            total += 1
            if isInk(p) { inked += 1 }
        }
        return total > 0 ? Double(inked) / Double(total) : 0
    }

    /// The ink in each row of the mark, as a fraction of the row's width — the profile that shows a
    /// two-line wordmark has actually got two lines, with a clear band between them.
    ///
    /// `inset` trims that fraction off each edge first. GOG's mark is a rounded tile on a dark
    /// background, so its own corners are "dark ink" to this measure; anything counting *bands* has
    /// to look inside the tile rather than at the box.
    func inkByRow(inset: Double = 0) -> [Double] {
        let trimX = Int(Double(bitmap.width) * inset), trimY = Int(Double(bitmap.height) * inset)
        let xs = trimX..<(bitmap.width - trimX)
        guard !xs.isEmpty else { return [] }
        return (trimY..<(bitmap.height - trimY)).map { y in
            var n = 0
            for x in xs where isInk(bitmap[x, y]) { n += 1 }
            return Double(n) / Double(xs.count)
        }
    }

    var inkByRow: [Double] { inkByRow() }

    /// How many separate horizontal bands of ink there are — one per line of a wordmark.
    var inkBandCount: Int {
        var bands = 0, inBand = false
        for row in inkByRow(inset: 0.12) {
            if row > 0.05, !inBand { bands += 1; inBand = true }
            else if row < 0.02 { inBand = false }
        }
        return bands
    }

    /// The fraction of the mark that renders as **neither its ink nor its field** — mush.
    ///
    /// This is the measure that catches detail too fine for the screen it is drawn on, and it only
    /// means anything on a bitmap rendered at the *real* device scale. A stroke narrower than a pixel
    /// cannot be drawn as a stroke: it is averaged into the background as mid-grey, and enough of that
    /// is what a player calls "a smudge". Judged against the mark's **own** two tones rather than
    /// absolute luminance, so a mid-blue disc is a field, not mush.
    ///
    /// Measured inside the mark, away from its own antialiased rim.
    var mushFraction: Double {
        let cx = Double(bitmap.width) / 2, cy = Double(bitmap.height) / 2
        let radius = min(cx, cy) * 0.86
        var inside: [Double] = []
        for y in 0..<bitmap.height {
            for x in 0..<bitmap.width {
                let dx = Double(x) - cx, dy = Double(y) - cy
                if dx * dx + dy * dy <= radius * radius { inside.append(bitmap[x, y].luminance) }
            }
        }
        guard inside.count > 20 else { return 0 }

        // The mark's two tones, taken as percentiles so one stray pixel cannot define either.
        let sorted = inside.sorted()
        func percentile(_ p: Double) -> Double { sorted[min(sorted.count - 1, Int(Double(sorted.count) * p))] }
        let inkTone = ink == .light ? percentile(0.98) : percentile(0.02)
        let fieldTone = ink == .light ? percentile(0.10) : percentile(0.90)

        let gap = abs(inkTone - fieldTone)
        guard gap > 0.05 else { return 0 }      // a mark with only one tone has nothing to blur
        let ambiguous = inside.filter { min(abs($0 - inkTone), abs($0 - fieldTone)) > 0.30 * gap }
        return Double(ambiguous.count) / Double(inside.count)
    }

    /// Average colour of the disc behind the mark, sampled just inside the rim at the four
    /// diagonals — away from the ink, and away from the antialiased edge.
    var discColour: (r: Double, g: Double, b: Double) {
        let w = Double(bitmap.width), h = Double(bitmap.height)
        let offsets = [(0.20, 0.20), (0.80, 0.20), (0.20, 0.80), (0.80, 0.80),
                       (0.50, 0.06), (0.50, 0.94), (0.06, 0.50), (0.94, 0.50)]
        var r = 0.0, g = 0.0, b = 0.0, n = 0.0
        for (fx, fy) in offsets {
            let p = bitmap[min(Int(fx * w), bitmap.width - 1), min(Int(fy * h), bitmap.height - 1)]
            guard !isInk(p) else { continue }
            r += p.r; g += p.g; b += p.b; n += 1
        }
        guard n > 0 else { return (0, 0, 0) }
        return (r / n, g / n, b / n)
    }
}
