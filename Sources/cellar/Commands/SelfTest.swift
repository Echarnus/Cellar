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

        // 6. The rolling log's line format. Every entry is written and read back through these
        // two, so a message carrying newlines or a double space must survive the round-trip —
        // otherwise a crash report loses the very line that explains the crash.
        let written = LogEntry(date: Date(timeIntervalSince1970: 1_757_000_000), level: .warn,
                               source: "cli", category: .session, subject: "planet-coaster-2",
                               message: "exited after 12s\nerr:module:import_dll  missing")
        guard let read = LogEntry.parse(written.line) else {
            throw Failure(message: "FAILED: a written log line did not parse back")
        }
        try check(read.level == .warn && read.category == .session, "log line keeps its level and category")
        try check(read.subject == "planet-coaster-2", "log line keeps its subject")
        try check(read.date == written.date, "log line keeps its timestamp to the second")
        try check(!read.message.contains("\n") && read.message.contains("err:module:import_dll"),
                  "log message survives newlines and double spaces")
        try check(LogEntry.parse("not a log line at all") == nil, "a junk line is skipped, not shown")

        // 7. Redaction. The diagnostics report is meant to be posted in public, so these are the
        // three shapes that must never come out the other side.
        let secrets = Diagnostics.redact(
            "refresh_token=abc123 --password hunter2 " + FileManager.default.homeDirectoryForCurrentUser.path + "/Games")
        try check(!secrets.contains("abc123"), "redaction removes a token value")
        try check(!secrets.contains("hunter2"), "redaction removes a --password value")
        try check(secrets.contains("~/Games"), "redaction replaces the home path with ~")

        // 8. The command line as the log records it. `Cellar.main` logs every invocation, and the
        // export folds the log into a file players are told to attach to a public bug report — so
        // this exercises the formatter that actually runs, in every spelling ArgumentParser accepts.
        // The first version of this only tested `redact()` against strings built from its own
        // pattern list, and duly missed `-u <steam account>` and `gog login --code <oauth code>`.
        let commandLines: [([String], String)] = [
            (["fetch-depot", "witcher-3", "-u", "SteamAccountName"], "short flag"),
            (["fetch-depot", "witcher-3", "-uSteamAccountName"], "glued short flag"),
            (["fetch-depot", "witcher-3", "--username", "SteamAccountName"], "long flag"),
            (["fetch-depot", "witcher-3", "--username=SteamAccountName"], "long flag with ="),
            (["gog", "login", "--code", "SteamAccountName"], "one-time OAuth code"),
            (["gog", "login", "--future-option", "SteamAccountName"], "an option nobody listed"),
        ]
        for (arguments, shape) in commandLines {
            let line = Diagnostics.redactCommandLine(arguments).text
            try check(!line.contains("SteamAccountName") && line.contains("<redacted>"),
                      "command line redacts a value passed by \(shape)")
        }

        // …without redacting the words that make a log line worth reading.
        let readable = Diagnostics.redactCommandLine(["launch", "witcher-3", "--level", "warn"]).text
        try check(readable.contains("launch") && readable.contains("witcher-3"),
                  "command line keeps the subcommand and the profile slug")
        try check(readable.contains("warn"), "command line keeps a known-safe option value")

        // 9. The whole logged line, built from a *real* parse failure. ArgumentParser's own error
        // text quotes the offending token back verbatim ("Unknown option '-uGluedSecret…'"), so a
        // redacted invocation is worthless if the reason beside it is not scrubbed with the same
        // secrets. Testing the formatter alone missed this; parsing for real is what catches it.
        let failing: [([String], String)] = [
            (["fetch-depot", "witcher-3", "-uGluedSecretAccount"], "a glued short flag"),
            (["fetch-depot", "witcher-3", "--username"], "a flag with its value missing"),
            (["gog", "login", "--code"], "an OAuth code flag with no value"),
            (["fetch-depot", "witcher-3", "--nonsense=SecretAccountName"], "an unknown option"),
        ]
        for (arguments, shape) in failing {
            var reason = ""
            do { _ = try Cellar.parseAsRoot(arguments) } catch { reason = Cellar.message(for: error) }
            try check(!reason.isEmpty, "\(shape) really does fail to parse")
            let line = Cellar.failureLine(Diagnostics.redactCommandLine(arguments), reason)
            try check(!line.contains("GluedSecretAccount") && !line.contains("SecretAccountName"),
                      "the logged failure keeps no secret out of \(shape)")
        }

        print(Term.green("All selftests passed."))
    }
}
