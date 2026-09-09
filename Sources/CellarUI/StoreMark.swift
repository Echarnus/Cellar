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
public struct StoreMark: View {
    let store: GameStore
    var size: CGFloat

    public init(store: GameStore, size: CGFloat = 14) {
        self.store = store
        self.size = size
    }

    public var body: some View {
        switch store {
        case .steam:      SteamMark(size: size)
        case .battlenet:  BattleNetMark(size: size)
        case .gog:        GOGMark(size: size)
        case .standalone: StandaloneMark(size: size)
        }
    }

    /// The mark's own silhouette, for anything that has to ring or clip it.
    ///
    /// Not every mark is a disc: GOG's is a rounded tile, and a badge ring that assumed a circle
    /// would cut its corners off. Anything drawing *around* a mark asks here rather than guessing.
    public static func outline(of store: GameStore, size: CGFloat) -> AnyInsettableShape {
        switch store {
        case .gog:  AnyInsettableShape(RoundedRectangle(cornerRadius: size * GOGMark.corner, style: .continuous))
        default:    AnyInsettableShape(Circle())
        }
    }
}

/// A type-erased `InsettableShape`, so `outline(of:size:)` can hand back either a circle or a tile
/// and callers can still `strokeBorder` it. SwiftUI's own `AnyShape` loses insettability.
public struct AnyInsettableShape: InsettableShape {
    private let makePath: @Sendable (CGRect) -> Path
    private let makeInset: @Sendable (CGFloat) -> AnyInsettableShape

    public init<S: InsettableShape & Sendable>(_ shape: S) {
        makePath = { shape.path(in: $0) }
        makeInset = { AnyInsettableShape(shape.inset(by: $0)) }
    }

    public func path(in rect: CGRect) -> Path { makePath(rect) }
    public func inset(by amount: CGFloat) -> AnyInsettableShape { makeInset(amount) }
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

/// Blizzard's mark: the Battle.net orb — three tapered orbits crossing around an open centre, on
/// its flat blue.
///
/// The orb is not a spiral, which is the shape it is most often mistaken for (and the shape Cellar
/// drew until it was held next to the real thing). It is three **orbit arcs** at 120° to each other,
/// each a slice of the same flattened ellipse, each swelling from a whisker-thin tail to a blunt
/// head. What makes it read as Battle.net rather than as an atom is that they cross, and that the
/// three inner edges leave a curved triangle open in the middle.
///
/// The disc is flat `#008DE3` — sampled off Blizzard's own mark, which carries no gradient.
private struct BattleNetMark: View {
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle().fill(Color(.sRGB, red: 0.0, green: 0.553, blue: 0.890, opacity: 1))

            ForEach([0.0, 120.0, 240.0], id: \.self) { turn in
                OrbitBlade()
                    .fill(.white)
                    .rotationEffect(.degrees(turn))
            }
        }
        .frame(width: size, height: size)
    }
}

/// One of the orb's three orbits: an arc of a flattened ellipse, drawn as a filled outline so it
/// can taper — a stroked path cannot change width along its length.
///
/// The arc is sampled rather than fitted to Béziers on purpose: the taper is the whole character of
/// the mark, and a sampled centreline with an offset normal is the one construction where the
/// profile stays exactly what the numbers say at every size.
private struct OrbitBlade: Shape {
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
private struct GOGMark: View {
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

/// Two lines of blocky lowercase, drawn as rectangles on a pixel grid.
///
/// GOG's logotype is a stencil face: square counters, one uniform stroke, no curves anywhere. That
/// is a shape a grid reproduces honestly and a font does not — and at the sizes this mark is used,
/// a real typeface would hint itself into a smudge while square strokes stay square.
///
/// The grid below is **traced off the mark**, not sketched from memory: each glyph is two units of
/// stroke around a four-unit counter, and the two details that make the word read as *gog* rather
/// than as *909* are both in here — the `g`'s crossbar stops one unit short of the right stem, and
/// the `g` carries a real descender that drops below the `o`'s baseline.
private struct BlockWord: Shape {
    let lines: [String]

    /// The glyphs, drawn as they are: `#` is ink, `.` is paper. Rows are the grid's rows, so a
    /// glyph with more rows (the `g`) hangs below the others' baseline.
    private static let glyphs: [Character: [String]] = [
        "g": ["########",
              "########",
              "##....##",
              "##....##",
              "##....##",
              "##....##",
              "#####.##",
              "#####.##",
              "......##",
              "########",
              "########"],
        "o": ["########",
              "########",
              "##....##",
              "##....##",
              "##....##",
              "##....##",
              "########",
              "########"],
        "c": ["#######",
              "#######",
              "##.....",
              "##.....",
              "##.....",
              "##.....",
              "#######",
              "#######"],
        "m": ["########",
              "########",
              "##.##.##",
              "##.##.##",
              "##.##.##",
              "##.##.##",
              "##.##.##",
              "##.##.##"],
    ]

    /// Units between two letters, and between the two lines.
    private static let letterGap = 1, lineGap = 2

    private static func width(of line: String) -> Int {
        let glyphs = line.compactMap { Self.glyphs[$0] }
        guard !glyphs.isEmpty else { return 1 }
        return glyphs.reduce(0) { $0 + ($1.first?.count ?? 0) } + (glyphs.count - 1) * letterGap
    }

    private static func height(of line: String) -> Int {
        line.compactMap { Self.glyphs[$0]?.count }.max() ?? 1
    }

    func path(in rect: CGRect) -> Path {
        let columns = lines.map(Self.width(of:)).max() ?? 1
        let rows = lines.map(Self.height(of:)).reduce(0, +) + (lines.count - 1) * Self.lineGap
        // One square cell, so the strokes stay square whatever box the mark is given.
        let cell = min(rect.width / CGFloat(columns), rect.height / CGFloat(rows))
        let originX = rect.midX - cell * CGFloat(columns) / 2
        let originY = rect.midY - cell * CGFloat(rows) / 2

        var path = Path()
        var top = 0
        for line in lines {
            // Centre a narrower line against the widest one.
            var left = CGFloat(columns - Self.width(of: line)) / 2

            for character in line {
                guard let glyph = Self.glyphs[character] else { continue }
                for (row, pattern) in glyph.enumerated() {
                    for (column, cellInk) in pattern.enumerated() where cellInk == "#" {
                        path.addRect(CGRect(x: originX + (left + CGFloat(column)) * cell,
                                            y: originY + (CGFloat(top) + CGFloat(row)) * cell,
                                            width: cell, height: cell))
                    }
                }
                left += CGFloat((glyph.first?.count ?? 0) + Self.letterGap)
            }
            top += Self.height(of: line) + Self.lineGap
        }
        return path
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
