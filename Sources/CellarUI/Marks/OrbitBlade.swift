import CellarDomain
import SwiftUI
import AppKit
import CellarKit

/// One of the orb's three orbits: an arc of a flattened ellipse, drawn as a filled outline so it
/// can taper — a stroked path cannot change width along its length.
///
/// The arc is sampled rather than fitted to Béziers on purpose: the taper is the whole character of
/// the mark, and a sampled centreline with an offset normal is the one construction where the
/// profile stays exactly what the numbers say at every size.
nonisolated struct OrbitBlade: Shape {
    /// Semi-axes of the orbit, in fractions of the box. Flattened hard — `b` is what sets how close
    /// the arc passes to the middle, and so how large the triangle in the centre comes out.
    var a: CGFloat = 0.415
    var b: CGFloat = 0.200
    /// Where the arc starts and ends on that ellipse, in degrees. Just over half a turn, so each
    /// blade wraps one end of its orbit and crosses both of its neighbours.
    var start: CGFloat = 128
    var end: CGFloat = 384
    /// Half the blade at its widest, in fractions of the box.
    var halfWidth: CGFloat = 0.046
    /// Where along the arc that widest point falls (0 = head, 1 = tail), and how fast it falls away.
    var headFullness: CGFloat = 0.55
    var tailFullness: CGFloat = 1.5
    /// The head is cut blunt rather than run out to a point — Blizzard's does the same, and a
    /// second whisker at both ends would disappear at 11pt.
    var headWidth: CGFloat = 0.30

    private static let samples = 160

    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height)
        let cx = rect.minX + s / 2, cy = rect.minY + s / 2
        let peak = pow(headFullness, headFullness) * pow(tailFullness, tailFullness)
            / pow(headFullness + tailFullness, headFullness + tailFullness)

        // Centreline point and unit normal at fraction `u` along the arc.
        func frame(_ u: CGFloat) -> (point: CGPoint, normal: CGPoint) {
            let t = (start + (end - start) * u) * .pi / 180
            let p = CGPoint(x: cx + a * s * cos(t), y: cy + b * s * sin(t))
            // Perpendicular to the tangent (-a sin t, b cos t).
            var n = CGPoint(x: b * cos(t), y: a * sin(t))
            let len = sqrt(n.x * n.x + n.y * n.y)
            if len > 0 { n = CGPoint(x: n.x / len, y: n.y / len) }
            return (p, n)
        }

        /// Half-width at `u`: a skewed bell, fat near the head, run out to nothing at the tail.
        func width(_ u: CGFloat) -> CGFloat {
            let bell = pow(max(u, 0), headFullness) * pow(max(1 - u, 0), tailFullness) / peak
            let blunt = headWidth * max(0, 1 - u / 0.22)      // keeps the head from coming to a point
            return halfWidth * s * max(bell, blunt)
        }

        var path = Path()
        for i in 0...Self.samples {
            let u = CGFloat(i) / CGFloat(Self.samples)
            let f = frame(u), w = width(u)
            let p = CGPoint(x: f.point.x + f.normal.x * w, y: f.point.y + f.normal.y * w)
            if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
        }
        for i in stride(from: Self.samples, through: 0, by: -1) {
            let u = CGFloat(i) / CGFloat(Self.samples)
            let f = frame(u), w = width(u)
            path.addLine(to: CGPoint(x: f.point.x - f.normal.x * w, y: f.point.y - f.normal.y * w))
        }
        path.closeSubpath()
        return path
    }
}
