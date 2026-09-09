import Testing
import SwiftUI
import CellarKit
import CellarUI

/// What a store mark has to look like, checked by rendering it and measuring the pixels.
///
/// Cellar's rule is that a GUI change is verified by looking at it, not by reading the diff — and
/// the store marks are the part of the app that rule exists for. They are hand-drawn vectors of
/// somebody else's logo, and the failure mode is not a crash or a build error: it is a mark that
/// still renders, still looks deliberate, and is simply *wrong* — the Steam valve mirrored, its
/// wheels solid instead of open, Blizzard's orb closed into a blob. Nothing catches that except
/// looking, so these tests look.
///
/// They assert the *identifying* properties, the ones that make a mark recognisable, rather than
/// exact pixels. That is deliberate: a test that broke on every nudge to a gradient would be
/// deleted within a week, and one that passes a mirrored logo is worthless.
@MainActor
@Suite("Store marks")
struct StoreMarkTests {

    /// The sizes the marks are actually used at: a filter chip, a library row, a section header,
    /// and the Accounts screen. Every claim below has to hold at all of them — a mark that only
    /// works large is a mark the player mostly sees broken.
    static let sizes: [CGFloat] = [11, 14, 22, 32]

    static func render(_ store: GameStore, size: CGFloat) -> Snapshot.Bitmap {
        Snapshot.render(StoreMark(store: store, size: size, artwork: false),
                        size: CGSize(width: size, height: size), scale: 8)
    }

    static func geometry(_ store: GameStore, size: CGFloat) -> MarkGeometry {
        // GOG's mark is the odd one out: dark letters on a white tile, where the others are white
        // ink on a saturated disc. Measure each the way it is actually drawn.
        MarkGeometry(bitmap: render(store, size: size), ink: store == .gog ? .dark : .light)
    }

    // MARK: - Every mark

    @Test("every store's mark actually draws something",
          arguments: GameStore.allCases, sizes)
    func markIsNotBlank(store: GameStore, size: CGFloat) {
        let g = Self.geometry(store, size: size)
        #expect(g.inkCoverage > 0.02,
                "\(store.rawValue) at \(Int(size))pt covers only \(pct(g.inkCoverage)) in ink — it is effectively blank")
        #expect(g.inkCoverage < 0.60,
                "\(store.rawValue) at \(Int(size))pt is \(pct(g.inkCoverage)) ink — it has filled in and lost its shape")
    }

    /// **The mark has to survive the screen it is drawn on.**
    ///
    /// Every other test here renders at 8×, which is generous on purpose — it measures the *design*.
    /// This one renders at **2×, the scale a real Retina Mac uses**, and asks whether the drawing is
    /// still made of ink and field rather than grey. Detail finer than a device pixel cannot be drawn
    /// as detail; it averages into mush, and the player sees a smudge.
    ///
    /// This is the test that was missing when a GOG mark whose wordmark needed 26 grid cells shipped
    /// into a 12pt filter chip — 24 device pixels — and every assertion in this file passed while the
    /// app on screen showed static. A coverage ratio cannot see that; only rendering at the real scale
    /// can. The sizes below are the ones the app actually asks for, `ContentView`'s 12 and 13
    /// included — not a tidy series.
    @Test("every mark survives the screen it is drawn on",
          arguments: GameStore.allCases, [CGFloat(11), 12, 13, 14, 16, 22, 30])
    func markSurvivesAtDeviceScale(store: GameStore, size: CGFloat) {
        let bitmap = Snapshot.render(StoreMark(store: store, size: size, artwork: false),
                                     size: CGSize(width: size, height: size), scale: 2)
        let mush = MarkGeometry(bitmap: bitmap, ink: store == .gog ? .dark : .light).mushFraction
        #expect(mush < 0.18,
                """
                \(store.rawValue) at \(Int(size))pt: \(pct(mush)) of the mark renders as neither ink \
                nor field on a 2× screen — its detail is finer than a pixel, so a player sees a smudge
                """)
    }

    /// A mark is a disc with ink on it, so the ink has to be near the middle. A centroid that has
    /// drifted to an edge means something is clipped or offset out of the circle.
    @Test("the mark sits in its disc", arguments: GameStore.allCases, sizes)
    func markIsCentred(store: GameStore, size: CGFloat) {
        let c = Self.geometry(store, size: size).inkCentroid
        #expect(abs(c.x - 0.5) < 0.22, "\(store.rawValue) at \(Int(size))pt: ink centroid x = \(round2(c.x))")
        #expect(abs(c.y - 0.5) < 0.22, "\(store.rawValue) at \(Int(size))pt: ink centroid y = \(round2(c.y))")
    }

    /// Each mark's disc carries its store's accent, and CellarKit's descriptor is where that colour
    /// is defined. If a mark's own gradient drifts away from the descriptor, the app and the CLI
    /// start describing the same store differently.
    ///
    /// GOG is not in the list: its mark is a white tile, by GOG's own design, and the purple that
    /// stands for GOG in Cellar lives in the lockup around it rather than in the mark.
    @Test("each disc is recognisably its store's colour",
          arguments: [GameStore.steam, .battlenet])
    func discMatchesDescriptorHue(store: GameStore) {
        let drawn = Self.geometry(store, size: 32).discColour
        let declared = store.descriptor.accentColorComponents
        #expect(hue(drawn.r, drawn.g, drawn.b).isClose(to: hue(declared.red, declared.green, declared.blue),
                                                       within: 0.10),
                """
                \(store.rawValue): the drawn disc and descriptor accent \(store.descriptor.accentHex) \
                are different hues — the app and the CLI would disagree about this store's colour
                """)
    }

    // MARK: - Steam

    /// The layout of Valve's mark is not a matter of taste, and getting it wrong is the tell that a
    /// logo was drawn from memory rather than looked at: the **big wheel is upper-right** and the
    /// **small wheel lower-left**, with the handle running on out to the rim.
    ///
    /// This is the exact regression that shipped — the wheels were the other way round — so it is
    /// the exact thing asserted here.
    @Test("Steam's big wheel is upper-right, not lower-left", arguments: sizes)
    func steamWheelsAreTheRightWayRound(size: CGFloat) {
        let g = Self.geometry(.steam, size: size)
        let upperRight = g.holeWidth(at: (x: 0.655, y: 0.355))
        let lowerLeft = g.holeWidth(at: (x: 0.330, y: 0.672))
        #expect(upperRight > 0, "Steam at \(Int(size))pt has no wheel opening upper-right at all")
        #expect(upperRight > lowerLeft,
                """
                Steam at \(Int(size))pt: the lower-left wheel's opening (\(round2(lowerLeft))) is \
                as wide as the upper-right one's (\(round2(upperRight))) — the valve is mirrored
                """)
    }

    /// Both wheels are open **rings**. Drawn as discs with a pinhole, the mark reads as a dumbbell
    /// or a keyhole instead of a valve — which is what a player actually notices.
    @Test("Steam's big wheel is an open ring, not a pinholed disc", arguments: sizes)
    func steamBigWheelIsARing(size: CGFloat) {
        let g = Self.geometry(.steam, size: size)
        #expect(g.hasHole(at: (x: 0.655, y: 0.355), probe: 0.22),
                "Steam at \(Int(size))pt: the big wheel has no open centre — it reads as a dumbbell")
    }

    @Test("Steam's small wheel is an open ring too", arguments: [CGFloat(22), 32])
    func steamSmallWheelIsARing(size: CGFloat) {
        let g = Self.geometry(.steam, size: size)
        #expect(g.hasHole(at: (x: 0.330, y: 0.672), probe: 0.16),
                "Steam at \(Int(size))pt: the small wheel has no open centre")
    }

    /// The handle joins the two wheels; the mark is one silhouette, not loose parts. (The two holes
    /// are dark, so the ink itself stays a single connected blob.)
    @Test("Steam's mark is one connected silhouette", arguments: sizes)
    func steamIsConnected(size: CGFloat) {
        #expect(Self.geometry(.steam, size: size).inkBlobCount == 1,
                "Steam at \(Int(size))pt broke into pieces — the handle no longer reaches both wheels")
    }

    // MARK: - Battle.net

    /// The orb is three orbits crossing around an open centre. Fill that centre in and it is a
    /// blob; the "portal" is the part a player recognises.
    @Test("Blizzard's orb has an open centre", arguments: sizes)
    func battleNetIsNotABlob(size: CGFloat) {
        let g = Self.geometry(.battlenet, size: size)
        let opening = g.holeWidth(at: (x: 0.5, y: 0.5))
        // Merely *having* a gap is not enough — a version shipped with one and still read as a
        // blob. 0.10 of the box is the width at which the portal is still visible in a 14pt row.
        #expect(opening > 0.10,
                """
                Battle.net at \(Int(size))pt: the orb's centre is only \(round2(opening)) of the box \
                across — the blades have thickened until the portal closed into a blob
                """)
    }

    /// Three arms, at 120° to each other. This is the assertion that separates the real orb from
    /// the spiral Cellar drew before it was held next to Blizzard's: a spiral also has an open
    /// centre and also looks deliberate, but it is not the same shape turned a third of the way
    /// round. Measured in wedges, because that is a property of the *shape*, not of how it was
    /// built — it would still hold if the blades were redrawn as Béziers tomorrow.
    @Test("Blizzard's orb has three arms, not one spiral", arguments: [CGFloat(22), 32])
    func battleNetIsThreeFold(size: CGFloat) {
        let g = Self.geometry(.battlenet, size: size)
        let wedges = [0.0, 120.0, 240.0].map { g.inkCoverage(wedge: $0) }
        let spread = (wedges.max() ?? 0) - (wedges.min() ?? 0)
        #expect(wedges.allSatisfy { $0 > 0.10 },
                "Battle.net at \(Int(size))pt: a third of the orb is empty — \(wedges.map(round2))")
        #expect(spread < 0.06,
                """
                Battle.net at \(Int(size))pt: the three thirds of the orb carry \(wedges.map(round2)) \
                of ink — that is not a mark with three-fold symmetry
                """)
    }

    // MARK: - GOG

    /// GOG's mark is the white tile with `gog` over `com` — the mark GOG actually uses. Cellar drew
    /// a purple disc with a "G" on it for a while, which GOG has never used: an invented logo is
    /// worse than a clumsy one, because the player learns something that matches nothing.
    @Test("GOG's mark is a light tile with dark letters, not a coloured disc", arguments: sizes)
    func gogIsTheWordmarkTile(size: CGFloat) {
        let bitmap = Self.render(.gog, size: size)
        let tile = MarkGeometry(bitmap: bitmap, ink: .light).inkCoverage      // the white field
        let letters = MarkGeometry(bitmap: bitmap, ink: .dark).inkCoverage    // the dark wordmark

        #expect(tile > 0.55,
                """
                GOG at \(Int(size))pt: only \(pct(tile)) of the mark is light — GOG's is a white \
                tile, and a dark or tinted one is a different logo
                """)
        #expect(letters > 0.08 && letters < 0.40,
                """
                GOG at \(Int(size))pt: the dark letters cover \(pct(letters)) of the tile — the \
                wordmark has either vanished or flooded it
                """)
    }

    /// Below 20pt the tile carries a single `g`, because the whole wordmark is 26 grid cells across
    /// and a 12pt chip is 24 device pixels — every stroke would land on less than one pixel. The app
    /// draws marks at 12pt (filter chips) and 13pt (section headings), so this *is* the common case.
    @Test("GOG's tile drops to one glyph at the sizes the app actually uses",
          arguments: [CGFloat(11), 12, 13, 14, 16])
    func gogIsOneGlyphWhenSmall(size: CGFloat) {
        let bands = Self.geometry(.gog, size: size).inkBandCount
        #expect(bands == 1,
                """
                GOG at \(Int(size))pt drew \(bands) lines of wordmark. Below 20pt it has to be the \
                single `g`: six glyphs in this many pixels render as static, not as a word
                """)
    }

    /// Two lines, not one, where there is room for two. The tile says `gog` over `com`, and a band of
    /// clear tile separates them.
    @Test("GOG's wordmark is set on two lines once there is room", arguments: [CGFloat(22), 32])
    func gogHasTwoLines(size: CGFloat) {
        let rows = Self.geometry(.gog, size: size).inkByRow
        let inked = rows.enumerated().filter { $0.element > 0.05 }.map(\.offset)
        guard let first = inked.first, let last = inked.last else {
            Issue.record("GOG at \(Int(size))pt drew no letters at all")
            return
        }
        // Somewhere between the first and last inked row there has to be a clear gap — the leading.
        let gap = (first...last).contains { rows[$0] < 0.02 }
        #expect(gap,
                "GOG at \(Int(size))pt: no clear band between the two lines — `gog` and `com` have run together")
    }

    @Test("the three branded marks are told apart by more than colour")
    func marksDifferInShape() {
        // Same size, same background: if two marks had the same silhouette they would only be
        // distinguishable by hue, which skills/ux.md forbids as a sole signal.
        let coverage = [GameStore.steam, .battlenet, .gog].map {
            (store: $0, ink: Self.geometry($0, size: 32).inkCoverage)
        }
        for a in coverage {
            for b in coverage where a.store != b.store {
                #expect(abs(a.ink - b.ink) > 0.01,
                        """
                        \(a.store.rawValue) and \(b.store.rawValue) cover almost the same area \
                        (\(pct(a.ink)) vs \(pct(b.ink))) — colour may be all that separates them
                        """)
            }
        }
    }

    // MARK: - The lockup and the generated cover

    /// Position + mark + word travel together. The lockup is where the mark and the word are
    /// paired, so it must be wider than the mark alone — a lockup that lost its label is a puzzle.
    @Test("the store lockup pairs a mark with a word", arguments: GameStore.allCases)
    func lockupCarriesAWord(store: GameStore) {
        let box = CGSize(width: 160, height: 30)
        let background = Color(white: 0.13)
        let withWord = Snapshot.render(StoreLockup(store: store), size: box, scale: 4, background: background)
        let markOnly = Snapshot.render(StoreMark(store: store, size: 14, artwork: false),
                                       size: box, scale: 4, background: background)

        // The label and the capsule behind it are tinted, not white, so they are invisible to the
        // ink threshold — this has to measure everything that is not the background.
        let base = markOnly[0, 0]
        let lockupArea = MarkGeometry(bitmap: withWord).coverage(differingFrom: base)
        let markArea = MarkGeometry(bitmap: markOnly).coverage(differingFrom: base)

        #expect(lockupArea > markArea * 1.5,
                """
                \(store.rawValue)'s lockup covers \(pct(lockupArea)) against the bare mark's \
                \(pct(markArea)) — the store's name is not being drawn beside the mark
                """)
    }

    /// The generated cover has to be *deterministic*: a cover that changed hue between launches
    /// would read as a bug. Swift's `hashValue` is seeded per process, which is the trap.
    @Test("a generated cover is the same every time it is drawn")
    func generatedCoverIsStable() {
        let once = Snapshot.render(GeneratedCover(title: "Planet Coaster 2", store: .steam, width: 92),
                                   size: CGSize(width: 92, height: 138), scale: 2)
        let twice = Snapshot.render(GeneratedCover(title: "Planet Coaster 2", store: .steam, width: 92),
                                    size: CGSize(width: 92, height: 138), scale: 2)
        #expect(once.rgba == twice.rgba, "the same game drew two different covers")
    }

    @Test("two different games get two different covers")
    func generatedCoversDiffer() {
        let a = Snapshot.render(GeneratedCover(title: "Planet Coaster 2", store: .steam, width: 92),
                                size: CGSize(width: 92, height: 138), scale: 2)
        let b = Snapshot.render(GeneratedCover(title: "Diablo IV", store: .battlenet, width: 92),
                                size: CGSize(width: 92, height: 138), scale: 2)
        #expect(a.rgba != b.rgba, "two different games drew identical covers")
    }
}

// MARK: - Small helpers, so a failure message reads like a sentence

private func pct(_ v: Double) -> String { String(format: "%.1f%%", v * 100) }
private func round2(_ v: Double) -> String { String(format: "%.2f", v) }

/// Hue in turns, 0…1. Comparing hue rather than RGB lets a gradient be lighter or darker than the
/// flat accent without failing, while still catching purple drifting to blue.
private func hue(_ r: Double, _ g: Double, _ b: Double) -> Double {
    let maxV = max(r, g, b), minV = min(r, g, b)
    let delta = maxV - minV
    guard delta > 0.0001 else { return 0 }
    let h: Double
    switch maxV {
    case r: h = ((g - b) / delta).truncatingRemainder(dividingBy: 6)
    case g: h = (b - r) / delta + 2
    default: h = (r - g) / delta + 4
    }
    let turns = h / 6
    return turns < 0 ? turns + 1 : turns
}

private extension Double {
    /// Circular comparison — hue wraps, so 0.98 and 0.02 are close.
    func isClose(to other: Double, within tolerance: Double) -> Bool {
        let d = abs(self - other)
        return min(d, 1 - d) <= tolerance
    }
}
