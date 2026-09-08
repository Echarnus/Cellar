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

/// Valve's mark: the large valve wheel, the connecting rod, and the smaller wheel above it, on the
/// dark navy Steam has used since 2013.
private struct SteamMark: View {
    let size: CGFloat

    private var navy: Color { Color(.sRGB, red: 0.10, green: 0.16, blue: 0.22, opacity: 1) }

    var body: some View {
        ZStack {
            Circle().fill(
                LinearGradient(colors: [Color(.sRGB, red: 0.16, green: 0.24, blue: 0.33, opacity: 1), navy],
                               startPoint: .topLeading, endPoint: .bottomTrailing))

            // The rod, drawn first so both wheels sit on top of its ends.
            Capsule()
                .fill(.white)
                .frame(width: size * 0.46, height: size * 0.10)
                .rotationEffect(.degrees(-45))

            // Lower-left valve wheel — the big one. Its hole has to stay open at 12pt, which is
            // what sets every other proportion here.
            ZStack {
                Circle().fill(.white).frame(width: size * 0.52)
                Circle().fill(navy).frame(width: size * 0.20)
            }
            .offset(x: -size * 0.15, y: size * 0.15)

            // Upper-right wheel, roughly half the size — the proportion that makes it read as Steam
            // rather than as a dumbbell.
            ZStack {
                Circle().fill(.white).frame(width: size * 0.28)
                Circle().fill(navy).frame(width: size * 0.10)
            }
            .offset(x: size * 0.19, y: -size * 0.19)
        }
        .frame(width: size, height: size)
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
                .stroke(.white, style: StrokeStyle(lineWidth: size * 0.13, lineCap: .round))
                .frame(width: size * 0.60)
                .rotationEffect(.degrees(-90))

            // Inner sweep, wound the other way — the hook that closes the orb.
            Circle()
                .trim(from: 0.06, to: 0.72)
                .stroke(.white, style: StrokeStyle(lineWidth: size * 0.13, lineCap: .round))
                .frame(width: size * 0.28)
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
