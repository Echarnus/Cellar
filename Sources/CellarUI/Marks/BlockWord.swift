import CellarDomain
import SwiftUI
import AppKit
import CellarKit

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
nonisolated struct BlockWord: Shape {
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
