import Foundation

/// Turns DepotDownloader's terminal QR code into a bit matrix a GUI can draw.
///
/// Steam's device-authorization flow is the nicest way to sign in — nothing typed, approved in the
/// mobile app — but DepotDownloader only ever *draws* the challenge, as a block of `█` characters
/// sized for a terminal. It prints no URL (verified against DepotDownloader 3.4.0), so there is
/// nothing for a GUI to re-encode. What there is, though, is the finished QR matrix: so rather than
/// trying to recover the payload and rebuild the code, this reads the drawing back into modules and
/// lets the app render it at a scannable size.
///
/// The format, measured rather than assumed: one text line per module row, **exactly two characters
/// per module** (`██` dark, two spaces light, always pair-aligned), a four-module quiet zone, and
/// whitespace-only rows for the quiet zone above and below. Steam rotates the challenge every few
/// seconds and DepotDownloader redraws it under "The QR code has changed:", so this emits a fresh
/// matrix each time and the caller simply replaces what it is showing.
public struct SteamQRCodeReader {
    /// Module rows gathered so far for the block being read.
    private var rows: [[Bool]] = []

    public init() {}

    /// Feed one line of output. Returns a complete matrix on the line that finishes a QR block,
    /// and nil otherwise.
    public mutating func consume(_ line: String) -> [[Bool]]? {
        guard line.contains("█") else {
            // Any non-QR line ends the block — a rotation notice, or progress output.
            return rows.isEmpty ? nil : finish()
        }
        rows.append(Self.modules(in: line))
        // A QR is square, and row 0 already spans the full width (the two top finder patterns sit at
        // both edges), so the block is complete the moment the row count reaches that width. Waiting
        // for a following line instead would leave the code undrawn until Steam rotated it.
        if let width = Self.darkSpan(rows), rows.count >= width { return finish() }
        return nil
    }

    /// Anything gathered but not yet emitted — for a caller that has stopped reading.
    public mutating func flush() -> [[Bool]]? { rows.isEmpty ? nil : finish() }

    private mutating func finish() -> [[Bool]]? {
        defer { rows = [] }
        return Self.trimmed(rows)
    }

    /// Split a line into modules: two characters each, dark when the pair starts with `█`.
    static func modules(in line: String) -> [Bool] {
        let characters = Array(line)
        var result: [Bool] = []
        var index = 0
        while index + 1 < characters.count {
            result.append(characters[index] == "█")
            index += 2
        }
        return result
    }

    /// Width of the bounding box of dark modules — the QR's real size, without the quiet zone.
    static func darkSpan(_ rows: [[Bool]]) -> Int? {
        var first: Int?
        var last: Int?
        for row in rows {
            for (column, dark) in row.enumerated() where dark {
                if first == nil || column < first! { first = column }
                if last == nil || column > last! { last = column }
            }
        }
        guard let first, let last else { return nil }
        return last - first + 1
    }

    /// Crop to the dark bounding box. The three finder patterns sit in the outer corners, so that
    /// box is exactly the QR matrix — and cropping means the renderer controls the quiet zone
    /// instead of depending on whatever padding survived the pipe.
    static func trimmed(_ rows: [[Bool]]) -> [[Bool]]? {
        var top: Int?
        var bottom: Int?
        var left: Int?
        var right: Int?
        for (index, row) in rows.enumerated() {
            for (column, dark) in row.enumerated() where dark {
                if top == nil { top = index }
                bottom = index
                if left == nil || column < left! { left = column }
                if right == nil || column > right! { right = column }
            }
        }
        guard let top, let bottom, let left, let right, right >= left, bottom >= top else { return nil }
        return rows[top...bottom].map { row in
            (left...right).map { $0 < row.count ? row[$0] : false }
        }
    }
}
