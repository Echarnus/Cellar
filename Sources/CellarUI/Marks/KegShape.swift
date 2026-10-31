import SwiftUI

/// The keg's parts, each as a `Shape` so SwiftUI does the scaling. Everything is in fractions of the
/// shape's box; the box is square and the keg fills its height, standing a little narrower than wide.
// Pure geometry, so it opts out of the module's main-actor default: SwiftUI asks a `Shape` for its
// path from any thread, and `Shape` requires `Sendable`.
nonisolated public enum KegShape {
    // Rim centres and radii. `ry` is the half-height of the elliptical rims — the same slight top-down
    // view as the icon, so the hoops curve the same way the lid does.
    static let left = 0.14, right = 0.86, topY = 0.12, botY = 0.80, ry = 0.055, bulge = 0.10
    static let hoopInset = 0.17, hoopHeight = 0.06
    static var mid: Double { (topY + botY) / 2 }

    static func point(_ x: Double, _ y: Double, in r: CGRect) -> CGPoint {
        CGPoint(x: r.minX + x * r.width, y: r.minY + y * r.height)
    }

    /// The body: bulged sides, the front half of the bottom rim, the back half of the top rim.
    static func silhouette(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: point(left, topY, in: r))
        p.addQuadCurve(to: point(left, botY, in: r), control: point(left - bulge, mid, in: r))
        p.addQuadCurve(to: point(right, botY, in: r), control: point(0.5, botY + 2 * ry, in: r))
        p.addQuadCurve(to: point(right, topY, in: r), control: point(right + bulge, mid, in: r))
        p.addQuadCurve(to: point(left, topY, in: r), control: point(0.5, topY - 2 * ry, in: r))
        p.closeSubpath()
        return p
    }

    /// How far the bulged side stands out from `left`/`right` at height `y`. The side is a quadratic
    /// curve whose control point sits at mid-height, so its parameter is linear in `y`.
    static func sideBulge(at y: Double) -> Double {
        let t = (y - topY) / (botY - topY)
        return 2 * (1 - t) * t * bulge
    }

    /// The front arc of a rim-parallel curve at height `y`, from one side of the body to the other.
    static func arc(at y: Double, in r: CGRect) -> Path {
        let b = sideBulge(at: y)
        var p = Path()
        p.move(to: point(left - b, y, in: r))
        p.addQuadCurve(to: point(right + b, y, in: r), control: point(0.5, y + 2 * ry, in: r))
        return p
    }

    /// A hoop as a closed band following the rim perspective, wider than the body so the caller can
    /// clip or subtract it.
    static func hoop(at y: Double, in r: CGRect) -> Path {
        let l = left - bulge - 0.05, rt = right + bulge + 0.05, h = hoopHeight
        var p = Path()
        p.move(to: point(l, y - h / 2, in: r))
        p.addQuadCurve(to: point(rt, y - h / 2, in: r), control: point(0.5, y - h / 2 + 2 * ry, in: r))
        p.addLine(to: point(rt, y + h / 2, in: r))
        p.addQuadCurve(to: point(l, y + h / 2, in: r), control: point(0.5, y + h / 2 + 2 * ry, in: r))
        p.closeSubpath()
        return p
    }

    static var hoopYs: [Double] { [topY + hoopInset, botY - hoopInset] }

    /// The solid glyph: body minus the two hoops, joined with the tap hanging below the rim. Built
    /// with CoreGraphics set operations so the result is one region and fills under any rule.
    nonisolated public struct Filled: Shape {
        public init() {}
        public func path(in r: CGRect) -> Path {
            let body = silhouette(in: r).cgPath
            let hoops = hoopYs.reduce(into: Path()) { $0.addPath(hoop(at: $1, in: r)) }.cgPath
            return Path(body.subtracting(hoops).union(Tap().path(in: r).cgPath))
        }
    }

    /// The line drawing: body, lid front edge, and both hoops as strokes.
    nonisolated public struct Outline: Shape {
        public init() {}
        public func path(in r: CGRect) -> Path {
            var p = silhouette(in: r)
            p.addPath(arc(at: topY, in: r))
            for y in hoopYs { p.addPath(arc(at: y, in: r)) }
            return p
        }
    }

    /// The tap: a short spout reaching below the bottom rim, with a handle across it. Solid in both
    /// styles — at glyph sizes it is two or three pixels, and a stroked version would be noise.
    nonisolated public struct Tap: Shape {
        public init() {}
        public func path(in r: CGRect) -> Path {
            let spoutW = 0.10, spoutTop = botY + 0.02, spoutBot = 0.97
            let handleW = 0.24, handleH = 0.05, handleY = botY + ry + 0.03
            var p = Path()
            p.addRoundedRect(in: CGRect(origin: point(0.5 - spoutW / 2, spoutTop, in: r),
                                        size: CGSize(width: spoutW * r.width, height: (spoutBot - spoutTop) * r.height)),
                             cornerSize: CGSize(width: 0.02 * r.width, height: 0.02 * r.height))
            p.addRoundedRect(in: CGRect(origin: point(0.5 - handleW / 2, handleY, in: r),
                                        size: CGSize(width: handleW * r.width, height: handleH * r.height)),
                             cornerSize: CGSize(width: handleH / 2 * r.width, height: handleH / 2 * r.height))
            return p
        }
    }
}
