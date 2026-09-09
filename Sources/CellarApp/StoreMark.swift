import SwiftUI
import CellarKit

/// The storefronts' own marks, drawn as vectors.
///
/// A generic game-controller glyph tells a player nothing; the Steam valve and the Battle.net orb
/// are recognised instantly, and that recognition is the whole point of separating the stores.
///
/// They are **drawn in code, not shipped as artwork**. Cellar's hard rule is that it redistributes
/// nobody's proprietary assets (`AGENTS.md`, `docs/LEGAL.md`), and a bundled PNG of Valve's or
/// Blizzard's logo would break it. Vector marks composed from primitives keep the repo asset-free,
/// stay crisp at every size, work offline, and adapt to light and dark on their own.
///
/// Use is nominative: the mark labels which store a game came from. It is not a badge of
/// endorsement, and Cellar says so in `NOTICE`.
struct StoreMark: View {
    let store: GameStore
    var size: CGFloat = 14

    var body: some View {
        switch store {
        case .steam:      SteamMark(size: size)
        case .battlenet:  BattleNetMark(size: size)
        case .standalone: StandaloneMark(size: size)
        }
    }
}

/// Valve's mark: the valve wheel, the smaller wheel, and the handle that runs out to the rim, on
/// the dark navy Steam has used since 2013.
///
/// The layout is not a matter of taste, and getting it wrong is the tell that a logo was drawn from
/// memory: the **big wheel sits upper-right**, the **small wheel lower-left**, and the handle carries
/// on up past the small wheel to the left rim. Both wheels are open **rings** — draw them as discs
/// with a pinhole and the mark reads as a dumbbell instead of a valve.
///
/// The proportions below were measured off Steam's own `Steam.icns`, in fractions of the mark's box,
/// so they hold at every size. What has to survive the smallest use (11pt in a filter chip) is the
/// big wheel's hole, which is what sets the rest.
private struct SteamMark: View {
    let size: CGFloat

    private var navy: Color { Color(.sRGB, red: 0.10, green: 0.16, blue: 0.22, opacity: 1) }

    private let bigWheel = CGPoint(x: 0.655, y: 0.355)
    private let smallWheel = CGPoint(x: 0.330, y: 0.672)
    /// Where the handle runs out to — the left rim, level with the centre. The disc clips it there,
    /// which is what gives the end the flat cut Valve's has.
    private let handleEnd = CGPoint(x: 0.02, y: 0.500)

    var body: some View {
        ZStack {
            Circle().fill(
                LinearGradient(colors: [Color(.sRGB, red: 0.16, green: 0.24, blue: 0.33, opacity: 1), navy],
                               startPoint: .topLeading, endPoint: .bottomTrailing))

            // One white silhouette, built by overlapping opaque pieces — the two wheels' holes are
            // then punched back out in navy on top.
            ZStack {
                MarkLine(from: bigWheel, to: smallWheel)
                    .stroke(.white, style: StrokeStyle(lineWidth: size * 0.155, lineCap: .round))
                MarkLine(from: smallWheel, to: handleEnd)
                    .stroke(.white, style: StrokeStyle(lineWidth: size * 0.108, lineCap: .round))

                MarkDisc(center: bigWheel, radius: 0.208).fill(.white)
                MarkDisc(center: smallWheel, radius: 0.115).fill(.white)
                MarkDisc(center: bigWheel, radius: 0.120).fill(navy)
                MarkDisc(center: smallWheel, radius: 0.060).fill(navy)
            }
            .clipShape(Circle())
        }
        .frame(width: size, height: size)
    }
}

/// A straight segment between two points given in fractions of the mark's box.
private struct MarkLine: Shape {
    let from: CGPoint, to: CGPoint

    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + from.x * s, y: rect.minY + from.y * s))
        path.addLine(to: CGPoint(x: rect.minX + to.x * s, y: rect.minY + to.y * s))
        return path
    }
}

/// A disc whose centre and radius are fractions of the mark's box.
private struct MarkDisc: Shape {
    let center: CGPoint, radius: CGFloat

    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height)
        let r = radius * s
        return Path(ellipseIn: CGRect(x: rect.minX + center.x * s - r,
                                      y: rect.minY + center.y * s - r,
                                      width: r * 2, height: r * 2))
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
                .stroke(.white, style: StrokeStyle(lineWidth: size * 0.115, lineCap: .round))
                .frame(width: size * 0.62)
                .rotationEffect(.degrees(-90))

            // Inner sweep, wound the other way — the hook that closes the orb. Its stroke has to
            // stay well under its own radius: at the old 0.13 on a 0.28 circle the line was nearly
            // half the diameter, so the arc closed up and the centre of the orb read as a blob.
            Circle()
                .trim(from: 0.06, to: 0.72)
                .stroke(.white, style: StrokeStyle(lineWidth: size * 0.095, lineCap: .round))
                .frame(width: size * 0.34)
                .rotationEffect(.degrees(90))
        }
        .frame(width: size, height: size)
    }
}

/// No store: a plain box, so "these files are just on disk" reads as deliberately different from
/// the two branded marks rather than as a store Cellar failed to identify.
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
