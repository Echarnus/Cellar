import Foundation
import Testing
@testable import CellarKit

/// The byte-exact formats Cellar has to speak: Valve's binary VDF, the CRC32 that derives a
/// shortcut's appid, and the ASCII QR code DepotDownloader draws instead of publishing.
///
/// `cellar selftest` already covered a happy path for each of these. These add the cases that
/// actually break parsers: empty input, truncation, nesting, non-ASCII, and boundary values.
@Suite(.serialized)
struct CodecTests {

    // MARK: - CRC32

    @Test("CRC32 matches published vectors")
    func crc32Vectors() {
        #expect(CRC32.checksum("") == 0)
        #expect(CRC32.checksum("test") == 0xD87F_7E0C)
        #expect(CRC32.checksum("a") == 0xE8B7_BE43)
        #expect(CRC32.checksum("abc") == 0x3524_41C2)
        #expect(CRC32.checksum("123456789") == 0xCBF4_3926)
    }

    @Test("CRC32 over bytes and over the same UTF-8 string agree")
    func crc32BytesAndString() {
        let text = "Planet Coaster 2"
        #expect(CRC32.checksum(text) == CRC32.checksum([UInt8](text.utf8)))
    }

    @Test("CRC32 handles non-ASCII game names")
    func crc32Unicode() {
        // Game names carry accents and CJK; a byte-wise CRC must not care.
        let a = CRC32.checksum("Café Noël")
        let b = CRC32.checksum("Café Noël")
        #expect(a == b)
        #expect(CRC32.checksum("東方") != 0)
    }

    // MARK: - Binary VDF

    @Test("An empty map is one terminator, and reads back as an empty map")
    func emptyVDF() throws {
        let data = BinaryVDF.serialize(.map([]))
        #expect([UInt8](data) == [0x08], "the root map's close, and nothing else")
        guard case .map(let entries) = try BinaryVDF.parse(data) else {
            Issue.record("empty VDF did not parse back as a map"); return
        }
        #expect(entries.isEmpty)
    }

    @Test("Zero bytes are an empty map rather than an error")
    func zeroBytesIsEmptyMap() throws {
        // A never-written shortcuts.vdf reads as "no shortcuts yet", which is what SteamShortcuts
        // relies on to create the file on first use.
        guard case .map(let entries) = try BinaryVDF.parse(Data()) else {
            Issue.record("empty data did not parse as a map"); return
        }
        #expect(entries.isEmpty)
    }

    @Test("Strings, uint32s and nested maps all survive a round trip")
    func vdfRoundTrip() throws {
        let original: VDFValue = .map([
            ("shortcuts", .map([
                ("0", .map([
                    ("appid", .uint32(0x8000_0001)),
                    ("appname", .string("Planet Coaster 2")),
                    ("exe", .string("\"/Applications/PC2.app/Contents/MacOS/launcher\"")),
                    ("IsHidden", .uint32(0)),
                    ("tags", .map([])),
                ])),
                ("1", .map([
                    ("appid", .uint32(0xFFFF_FFFF)),
                    ("appname", .string("Café Noël — 東方")),
                    ("tags", .map([("0", .string("cellar"))])),
                ])),
            ])),
        ])

        let encoded = BinaryVDF.serialize(original)
        let decoded = try BinaryVDF.parse(encoded)
        #expect(BinaryVDF.serialize(decoded) == encoded, "re-serialising must be byte-identical")

        guard case .map(let root) = decoded,
              case .map(let shortcuts)? = root.first(where: { $0.0 == "shortcuts" })?.1,
              case .map(let second)? = shortcuts.first(where: { $0.0 == "1" })?.1 else {
            Issue.record("nested structure was lost"); return
        }
        #expect(second.contains { $0.0 == "appname" })
        if case .string(let name)? = second.first(where: { $0.0 == "appname" })?.1 {
            #expect(name == "Café Noël — 東方", "UTF-8 must survive the C-string encoding")
        } else {
            Issue.record("appname did not decode as a string")
        }
        if case .uint32(let id)? = second.first(where: { $0.0 == "appid" })?.1 {
            #expect(id == 0xFFFF_FFFF, "the top of the uint32 range must not wrap")
        }
    }

    @Test("Key order is preserved — Steam reads shortcuts by ordinal")
    func vdfPreservesOrder() throws {
        let value: VDFValue = .map((0..<10).map { ("\($0)", .string("entry \($0)")) })
        guard case .map(let entries) = try BinaryVDF.parse(BinaryVDF.serialize(value)) else {
            Issue.record("did not parse as a map"); return
        }
        #expect(entries.map { $0.0 } == (0..<10).map(String.init))
    }

    @Test("Truncated or corrupt data throws instead of returning nonsense", arguments: [
        Data([0x00]),                       // a map header with no key
        Data([0x01, 0x61, 0x00]),           // a string key with no value
        Data([0x02, 0x61, 0x00, 0x01]),     // a uint32 with only one of its four bytes
        Data([0x7F, 0x61, 0x00, 0x08]),     // an unknown type tag
    ])
    func vdfRejectsGarbage(_ data: Data) {
        #expect(throws: (any Error).self) { try BinaryVDF.parse(data) }
    }

    @Test("A shortcuts.vdf Steam wrote is readable, terminator and all")
    func vdfFileShape() throws {
        let data = BinaryVDF.serialize(.map([("shortcuts", .map([("0", .map([]))]))]))
        #expect(data.suffix(2) == Data([0x08, 0x08]), "Steam expects the doubled terminator")
        #expect(data.first == 0x00, "the outer value is a map")
    }

    // MARK: - Steam shortcut appids

    @Test("A shortcut appid is deterministic and marked as non-Steam")
    func shortcutAppID() {
        let exe = "\"/Users/x/Applications/Game.app/Contents/MacOS/launcher\""
        let id = SteamShortcuts.appID(exe: exe, appName: "Game")

        #expect(id == SteamShortcuts.appID(exe: exe, appName: "Game"), "must be stable across runs")
        #expect(id & 0x8000_0000 != 0, "Steam distinguishes shortcuts by the high bit")
        #expect(id != SteamShortcuts.appID(exe: exe, appName: "Other Game"))
        #expect(id != SteamShortcuts.appID(exe: exe + "2", appName: "Game"))
    }

    @Test("Two different games practically never collide")
    func shortcutAppIDsSpread() {
        let ids = (0..<200).map {
            SteamShortcuts.appID(exe: "\"/Applications/G\($0).app/launcher\"", appName: "Game \($0)")
        }
        #expect(Set(ids).count == ids.count)
    }

    // MARK: - The ASCII QR code Steam's downloader draws

    /// A plausible QR matrix: a deterministic pattern plus the three finder squares, which are what
    /// make row 0 span the full width and give the trim step something to anchor on.
    static func fixtureMatrix(size: Int) -> [[Bool]] {
        var matrix = (0..<size).map { row in
            (0..<size).map { column in (row * 5 + column * 3) % 4 == 0 }
        }
        for corner in [(0, 0), (0, size - 7), (size - 7, 0)] {
            for dr in 0..<7 {
                for dc in 0..<7 {
                    let ring = dr == 0 || dr == 6 || dc == 0 || dc == 6
                    let core = (2...4).contains(dr) && (2...4).contains(dc)
                    matrix[corner.0 + dr][corner.1 + dc] = ring || core
                }
            }
        }
        return matrix
    }

    @Test("A drawn QR matrix is recovered module-exactly")
    func qrRoundTrip() {
        let matrix = Self.fixtureMatrix(size: 25)
        var reader = SteamQRCodeReader()
        var decoded: [[Bool]]?
        for line in draw(matrix, quietModules: 4) {
            if let emitted = reader.consume(line) { decoded = emitted }
        }
        #expect(decoded == matrix)
    }

    @Test("Ordinary console output never looks like a QR code")
    func qrIgnoresNoise() {
        var reader = SteamQRCodeReader()
        let noise = ["Connecting to Steam...",
                     "Use the Steam Mobile App to sign in via QR code:",
                     "",
                     "   Logging in...",
                     "Got session token"]
        for line in noise {
            #expect(reader.consume(line) == nil, "\"\(line)\" was mistaken for QR output")
        }
    }

    @Test("The code is emitted as soon as it is square, not on the line after")
    func qrEmitsWhenSquare() {
        // Steam rotates the challenge every few seconds; waiting for a following line would leave
        // the app showing nothing until the code had already changed.
        let matrix = Self.fixtureMatrix(size: 21)
        var reader = SteamQRCodeReader()
        let lines = draw(matrix, quietModules: 4)
        let qrLines = lines.filter { $0.contains("█") }

        for line in qrLines.dropLast() {
            #expect(reader.consume(line) == nil, "emitted before the matrix was square")
        }
        #expect(reader.consume(qrLines.last!) != nil, "the final module row must complete the code")
        #expect(reader.consume(lines.last!) == nil, "the trailing quiet row has nothing left to emit")
    }

    @Test("A code split across pipe reads is still recovered, at any boundary")
    func qrSurvivesChunkBoundaries() {
        // The app reads the CLI through a pipe, and a pipe breaks wherever it likes. Feeding the
        // reader whatever each read happened to contain meant a module row arriving as two
        // fragments was counted as two short rows, so the matrix never squared up and the player
        // watched a spinner instead of a QR. The runner now assembles whole lines before the
        // observer sees them; this is that guarantee, checked at every possible split point.
        let matrix = Self.fixtureMatrix(size: 29)
        let text = draw(matrix, quietModules: 4).joined(separator: "\n") + "\n"
        let characters = Array(text)

        for boundary in 1..<characters.count {
            let chunks = [String(characters[..<boundary]), String(characters[boundary...])]
            var reader = SteamQRCodeReader()
            var pending = ""
            var decoded: [[Bool]]?
            for chunk in chunks {                       // exactly what CellarRunner.absorb does
                pending += chunk
                while let newline = pending.firstIndex(of: "\n") {
                    let line = String(pending[pending.startIndex..<newline])
                    pending = String(pending[pending.index(after: newline)...])
                    if let emitted = reader.consume(line) { decoded = emitted }
                }
            }
            #expect(decoded == matrix, "lost the code when the pipe broke at \(boundary)")
        }
    }

    /// Render a module matrix the way DepotDownloader does: two characters per module, a quiet
    /// zone either side, and a whitespace-only line above and below.
    private func draw(_ matrix: [[Bool]], quietModules: Int) -> [String] {
        let quiet = String(repeating: "  ", count: quietModules)
        let width = matrix[0].count * 2 + quietModules * 4
        var lines = [String(repeating: " ", count: width)]
        lines += matrix.map { row in quiet + row.map { $0 ? "██" : "  " }.joined() + quiet }
        lines.append(String(repeating: " ", count: width))
        return lines
    }
}
