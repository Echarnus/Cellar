import Testing
import SwiftUI
import Foundation
import CellarUI

/// What Cellar's own keg has to look like, checked the same way the store marks are: rendered and
/// measured. It is drawn white here so `MarkGeometry`'s light-ink measures apply as they do to the
/// Steam and Battle.net marks.
@MainActor
@Suite("Keg mark")
struct KegMarkTests {

    /// The sizes the app draws it at: the sidebar and welcome headers, and the empty detail pane.
    static let glyphSizes: [CGFloat] = [14, 18, 24]

    static func render(_ style: KegMark.Style, size: CGFloat, scale: CGFloat = 8) -> Snapshot.Bitmap {
        Snapshot.render(KegMark(size: size, style: style).foregroundStyle(.white),
                        size: CGSize(width: size, height: size), scale: scale)
    }

    @Test("the filled keg draws a body, not a blank or a blob", arguments: glyphSizes)
    func filledKegHasShape(size: CGFloat) {
        let g = MarkGeometry(bitmap: Self.render(.filled, size: size))
        #expect(g.inkCoverage > 0.25, "at \(Int(size))pt the keg covers only \(pct(g.inkCoverage)) — it is effectively blank")
        #expect(g.inkCoverage < 0.70, "at \(Int(size))pt the keg is \(pct(g.inkCoverage)) ink — it has filled its whole box")
    }

    /// The hoops are what make the silhouette a keg rather than a pill: two clear cuts across the
    /// body, one in the upper half and one in the lower. Measured as dips in the per-row ink profile.
    @Test("the filled keg has two hoops cut across it", arguments: glyphSizes)
    func filledKegHasTwoHoops(size: CGFloat) {
        let bitmap = Self.render(.filled, size: size)
        // Down the middle third of the columns, over the full height: every row is solid ink except
        // at the hoops and outside the rims. Count the gaps that sit between two solid stretches.
        let xs = Int(Double(bitmap.width) * 0.35)..<Int(Double(bitmap.width) * 0.65)
        let rows = (0..<bitmap.height).map { y -> Double in
            var n = 0
            for x in xs where bitmap[x, y].luminance >= MarkGeometry.lightInkThreshold { n += 1 }
            return Double(n) / Double(xs.count)
        }
        var gaps = 0, seenInk = false, inGap = false
        for row in rows {
            if row > 0.9 {
                if inGap { gaps += 1; inGap = false }
                seenInk = true
            } else if row < 0.2, seenInk {
                inGap = true
            }
        }
        // The last "gap" is the space under the keg (and around the tap), not a hoop; it is not
        // followed by solid ink so it is never counted. What is left must be exactly the two hoops.
        #expect(gaps == 2, "at \(Int(size))pt the keg shows \(gaps) hoop cut(s) across its body, not two")
    }

    @Test("the keg survives the screen it is drawn on", arguments: [CGFloat(14), 16, 18, 24])
    func kegSurvivesAtDeviceScale(size: CGFloat) {
        let mush = MarkGeometry(bitmap: Self.render(.filled, size: size, scale: 2)).mushFraction
        #expect(mush < 0.18,
                "at \(Int(size))pt \(pct(mush)) of the keg renders as neither ink nor field on a 2× screen")
    }

    @Test("the outline keg is a line drawing, not a fill")
    func outlineKegIsLines() {
        let g = MarkGeometry(bitmap: Self.render(.outline, size: 64))
        #expect(g.inkCoverage > 0.03, "the outline keg is effectively blank")
        #expect(g.inkCoverage < 0.25, "the outline keg is \(pct(g.inkCoverage)) ink — it is drawn solid")
    }
}

private func pct(_ v: Double) -> String { String(format: "%.1f%%", v * 100) }
