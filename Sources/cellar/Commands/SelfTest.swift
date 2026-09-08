import ArgumentParser
import CellarKit
import Foundation

/// Hidden self-checks for the byte-exact / round-trip logic (binary VDF, CRC32, shortcut writing).
/// Run: `cellar selftest`. Kept out of the normal help listing.
struct SelfTest: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "selftest", shouldDisplay: false)

    struct Failure: Error, CustomStringConvertible {
        let message: String
        var description: String { message }
    }

    func check(_ condition: Bool, _ label: String) throws {
        if condition {
            print("  \(Term.green("✓")) \(label)")
        } else {
            print("  \(Term.red("✗")) \(label)")
            throw Failure(message: "FAILED: \(label)")
        }
    }

    func run() throws {
        print(Term.bold("Cellar selftest"))

        // 1. CRC32 against a known value: crc32("test") == 0xD87F7E0C
        try check(CRC32.checksum("test") == 0xD87F_7E0C, "CRC32(\"test\") == 0xD87F7E0C")

        // 2. binary-VDF round-trip: serialize -> parse -> re-serialize is byte-identical
        let sample: VDFValue = .map([
            ("shortcuts", .map([
                ("0", .map([
                    ("appid", .uint32(0x8000_0001)),
                    ("appname", .string("Planet Coaster 2")),
                    ("exe", .string("\"/Users/x/Applications/PC2.app/Contents/MacOS/launcher\"")),
                    ("tags", .map([])),
                ])),
            ])),
        ])
        let data1 = BinaryVDF.serialize(sample)
        let parsed = try BinaryVDF.parse(data1)
        let data2 = BinaryVDF.serialize(parsed)
        try check(data1 == data2, "binary-VDF round-trip is byte-identical (\(data1.count) bytes)")
        try check(data1.suffix(2) == Data([0x08, 0x08]), "file ends with 0x08 0x08")

        // 3. shortcuts.vdf append into a temp dir: two entries, both parse back
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("cellar-selftest-\(ProcessInfo.processInfo.processIdentifier)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let launcher = URL(fileURLWithPath: "/Users/x/Applications/PC2.app/Contents/MacOS/launcher")
        let id1 = try SteamShortcuts.add(SteamShortcutEntry(appName: "Game One", launcherBinary: launcher), to: tmp)
        let id2 = try SteamShortcuts.add(SteamShortcutEntry(appName: "Game Two", launcherBinary: launcher), to: tmp)
        try check(id1 != id2, "two shortcuts get distinct appids (\(id1), \(id2))")

        let reread = try BinaryVDF.parse(Data(contentsOf: tmp.appendingPathComponent("shortcuts.vdf")))
        var count = 0
        if case .map(let root) = reread,
           let node = root.first(where: { $0.0 == "shortcuts" }),
           case .map(let entries) = node.1 {
            count = entries.count
        }
        try check(count == 2, "shortcuts.vdf re-parses with 2 entries")

        // 4. appid high bit is set (Steam non-Steam-shortcut convention)
        try check((id1 & 0x8000_0000) != 0, "shortcut appid has the high bit set")

        // 5. Steam's QR sign-in: DepotDownloader only *draws* the challenge, so Cellar reads the
        // drawing back into modules (see SteamQRCode.swift). Round-trip a synthetic code through
        // exactly the layout DepotDownloader emits — two characters per module, a four-module quiet
        // zone, whitespace-only rows above and below. Verified against DepotDownloader 3.4.0 output,
        // which is a 29x29 matrix; this uses 21x21 (QR version 1) so the fixture stays readable.
        let size = 21
        var matrix = (0..<size).map { row in
            (0..<size).map { column in (row * 7 + column * 3) % 5 == 0 }
        }
        // Finder patterns in three corners: the outermost modules must be dark, or the trim step
        // has nothing to anchor the bounding box to.
        for corner in [(0, 0), (0, size - 7), (size - 7, 0)] {
            for dr in 0..<7 {
                for dc in 0..<7 {
                    let ring = dr == 0 || dr == 6 || dc == 0 || dc == 6
                    let core = (2...4).contains(dr) && (2...4).contains(dc)
                    matrix[corner.0 + dr][corner.1 + dc] = ring || core
                }
            }
        }

        let quiet = String(repeating: "  ", count: 4)
        var drawn = [String(repeating: " ", count: size * 2 + 16)]   // top quiet zone
        drawn += matrix.map { row in quiet + row.map { $0 ? "██" : "  " }.joined() + quiet }
        drawn.append(String(repeating: " ", count: size * 2 + 16))   // bottom quiet zone

        var reader = SteamQRCodeReader()
        var decoded: [[Bool]]?
        for line in drawn {
            if let emitted = reader.consume(line) { decoded = emitted }
        }
        try check(decoded?.count == size, "ASCII QR round-trip: \(size) module rows recovered")
        try check(decoded?.first?.count == size, "ASCII QR round-trip: \(size) module columns recovered")
        try check(decoded == matrix, "ASCII QR round-trip is module-exact")

        // 5. The library gate. This decides whether somebody sees a game at all, and it is the one
        // rule in Cellar where a bug is a *claim about the player* — "these are your games" — so it
        // is checked against fabricated statuses rather than whatever this Mac happens to hold.
        func status(_ store: GameStore, connected: Bool, owned: [String]? = nil, complete: Bool = true) -> StoreStatus {
            StoreStatus(store: store, isConnected: connected, accountName: nil,
                        library: owned.map {
                            OwnedLibrary(keys: Set($0), totalCount: $0.count, refreshedAt: Date(),
                                         source: "a test", isComplete: complete)
                        })
        }
        let nothing = LibraryAccess(statuses: [:])
        try check(nothing.hasNoConnection, "no credentials means no connected stores")
        try check(!nothing.isVisible(store: .steam, key: "1"),
                  "a game is hidden until its store is connected")

        let complete = LibraryAccess(statuses: [
            .steam: status(.steam, connected: true, owned: ["1"]),
            .gog: status(.gog, connected: true, owned: []),
            .battlenet: status(.battlenet, connected: true),
        ])
        try check(complete.isVisible(store: .steam, key: "1"), "a game Steam confirms you own is shown")
        try check(!complete.isVisible(store: .steam, key: "2"), "a game Steam says you don't own is hidden")
        try check(!complete.isVisible(store: .gog, key: "7"),
                  "GOG's answer is exact, so an unowned GOG game is hidden")
        try check(complete.isVisible(store: .battlenet, key: "Fen"),
                  "Battle.net can never report ownership, so its games show once connected")

        // A `standalone` profile that names a Steam AppID is fetched from the player's Steam
        // account, so Steam gates it — getting this wrong would show somebody a game they don't own.
        try check(GameStore.gate(for: .standalone, hasSteamAppID: true) == .steam,
                  "a standalone profile with a Steam AppID is gated on Steam")
        try check(GameStore.gate(for: .standalone, hasSteamAppID: false) == .standalone,
                  "a standalone profile with no AppID is gated on nothing")
        try check(GameStore.gate(for: .gog, hasSteamAppID: true) == .gog,
                  "a real store always gates its own games")

        let partial = LibraryAccess(statuses: [
            .steam: status(.steam, connected: true, owned: ["1"], complete: false),
        ])
        try check(partial.isVisible(store: .steam, key: "1"),
                  "a partial Steam answer still confirms what it lists")
        try check(!partial.isVisible(store: .steam, key: "2"),
                  "a game missing from a partial answer is unchecked, not owned — so it stays hidden")
        try check(partial.status(.steam).ownership(of: "2") == .unverifiable,
                  "and it is reported as unverifiable, never as unowned")
        try check(partial.status(.steam).libraryNote != nil,
                  "a partial answer always carries the sentence explaining it")

        print(Term.green("All selftests passed."))
    }
}
