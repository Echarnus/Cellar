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

        // 4b. removing a shortcut by name leaves the others intact and renumbered — Steam reads the
        // keys as a contiguous list and silently drops everything after a gap.
        try check(SteamShortcuts.contains(appName: "Game One", in: tmp), "the shortcut Cellar added is found by name")
        try check(try SteamShortcuts.remove(appName: "Game One", from: tmp) == 1, "removing it takes exactly one entry")
        try check(!SteamShortcuts.contains(appName: "Game One", in: tmp), "it is gone afterwards")
        try check(SteamShortcuts.contains(appName: "Game Two", in: tmp), "the other shortcut survived")
        if case .map(let root) = try BinaryVDF.parse(Data(contentsOf: tmp.appendingPathComponent("shortcuts.vdf"))),
           case .map(let entries)? = root.first(where: { $0.0 == "shortcuts" })?.1 {
            try check(entries.map(\.0) == ["0"], "the remaining entry is renumbered to \"0\"")
        } else {
            try check(false, "shortcuts.vdf re-parses after a removal")
        }

        // 4c. A shortcut is only Cellar's if it points at the launcher Cellar generated. A player's
        // own hand-added shortcut can share the game's name, and it is not ours to delete.
        let mine = URL(fileURLWithPath: "\(NSHomeDirectory())/Applications/Game Three.app/Contents/MacOS/launcher")
        let theirs = URL(fileURLWithPath: "/Applications/Game Three.app/Contents/MacOS/Game Three")
        try SteamShortcuts.add(SteamShortcutEntry(appName: "Game Three", launcherBinary: theirs), to: tmp)
        try check(!SteamShortcuts.contains(appName: "Game Three", launcherPath: mine.path, in: tmp),
                  "a same-named shortcut pointing elsewhere is not recognised as Cellar's")
        try check(try SteamShortcuts.remove(appName: "Game Three", launcherPath: mine.path, from: tmp) == 0,
                  "…and removing Cellar's leaves it alone")
        try SteamShortcuts.add(SteamShortcutEntry(appName: "Game Three", launcherBinary: mine), to: tmp)
        try check(try SteamShortcuts.remove(appName: "Game Three", launcherPath: mine.path, from: tmp) == 1,
                  "Cellar's own shortcut is removed, and only that one")
        try check(SteamShortcuts.contains(appName: "Game Three", in: tmp),
                  "the player's shortcut of the same name survived")

        // 5. Removal safety: the paths Cellar must never delete, whatever a profile says. The shared
        // Steam install holds the sign-in and every other Steam game, so a bug here is not a bug,
        // it is somebody's weekend.
        let steamapps = Paths.sharedSteam.appendingPathComponent("steamapps")
        let mustRefuse: [URL] = [
            URL(fileURLWithPath: "/"),
            FileManager.default.homeDirectoryForCurrentUser,
            AppBundle.applicationsDirectory,
            URL(fileURLWithPath: "/Applications/Safari.app"),
            Paths.appSupport, Paths.prefixes, Paths.runners, Paths.cache, Paths.shared,
            Paths.sharedSteam, steamapps,
            steamapps.appendingPathComponent("common"),
            Paths.prefixes.appendingPathComponent("pc2/drive_c"),
            Paths.prefixes.appendingPathComponent("pc2/drive_c/Program Files (x86)"),
        ]
        for url in mustRefuse {
            try check(!Uninstall.isDeletable(url), "refuses to delete \(url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent)")
        }

        let mustAllow: [URL] = [
            steamapps.appendingPathComponent("common/Planet Coaster 2"),
            steamapps.appendingPathComponent("appmanifest_2688950.acf"),
            Paths.prefixes.appendingPathComponent("pc2"),
            Paths.prefixes.appendingPathComponent("pc2/drive_c/Games/witcher-3"),
            Paths.cache.appendingPathComponent("icons/pc2.icns"),
            AppBundle.applicationsDirectory.appendingPathComponent("Planet Coaster 2.app"),
        ]
        for url in mustAllow {
            try check(Uninstall.isDeletable(url), "allows deleting \(url.lastPathComponent)")
        }

        // 6. Steam's QR sign-in: DepotDownloader only *draws* the challenge, so Cellar reads the
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

        print(Term.green("All selftests passed."))
    }
}
