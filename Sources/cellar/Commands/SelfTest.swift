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

        // 5. The launch markers the app follows a launch by. If these stop round-tripping, the
        // launch window silently goes back to being a spinner — so they are worth a check.
        for stage in LaunchStage.allCases {
            let line = LaunchMarker.line(stage)
            try check(LaunchMarker.stage(in: line) == stage && LaunchMarker.isMarker(line),
                      "launch marker round-trips: \(stage.rawValue)")
        }
        try check(LaunchMarker.stage(in: "  Launching Diablo IV via Battle.net…") == nil,
                  "ordinary output is not mistaken for a marker")
        // A marker that came back through something that rewrote line endings still parses.
        try check(LaunchMarker.stage(in: LaunchMarker.line(.client) + "\r") == .client,
                  "a marker survives a CRLF line ending")

        // A game that runs bare must never be shown a step about opening a store client.
        let bare = LaunchContext(game: "The Witcher 3", store: .gog, throughClient: false)
        let viaClient = LaunchContext(game: "Diablo IV", store: .battlenet, throughClient: true)
        try check(!LaunchStage.sequence(bare).contains(.client),
                  "a store-free launch shows no client step")
        try check(LaunchStage.sequence(viaClient).contains(.client),
                  "a launch through a client shows the client step")
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
        // 6. The single Steam sign-in learns the account name from DepotDownloader's own success
        // line — and that capture is what makes every later run silent, because a stored token can
        // only be looked up by the username it was stored under. Parsed, never guessed, so it is
        // worth pinning against the exact sentence the tool prints (verified against 3.4.0).
        let success = "Success! Next time you can login with -username kennethdc -remember-password instead of -qr."
        try check(SteamAccount.accountName(inSuccessLine: success) == "kennethdc",
                  "Steam sign-in: the account name is read out of DepotDownloader's success line")
        try check(SteamAccount.accountName(inSuccessLine: "Logging in with QR code...") == nil,
                  "Steam sign-in: an ordinary line yields no account name")

        // 7. Expiry is not something Cellar can read off a token it never holds — it is learned the
        // moment Steam refuses one. Keep Steam's own word for the reason.
        try check(SteamAccount.rejection(in: "Access token was rejected (Expired).") == "expired",
                  "Steam session: a rejection is recognised, with Steam's own reason")
        try check(SteamAccount.rejection(in: "Downloading depot 2688950") == nil,
                  "Steam session: normal output is never read as a rejection")

        // 8. The library gate, against fabricated store states rather than whatever this Mac
        // happens to hold. This is the one place a bug is a *claim about the player* — that these
        // are their games — so it is not left to chance.
        let steamUnchecked = StoreLibrary.verdict(store: .steam, ownership: .unknown("not checked"),
                                                  isConnected: true)
        try check(!steamUnchecked.isVisible && steamUnchecked.fix != nil,
                  "Library gate: a store that could answer but hasn't hides its games, and offers the fix")
        try check(StoreLibrary.verdict(store: .steam, ownership: .owned, isConnected: true).isVisible,
                  "Library gate: a game Steam confirmed is shown")
        try check(!StoreLibrary.verdict(store: .steam, ownership: .notOwned, isConnected: true).isVisible,
                  "Library gate: a game Steam refused is not shown")
        // Connection comes first, and Battle.net is where that matters: it can never answer the
        // ownership question, so without this its games were listed for a player who had never
        // opened Battle.net. Both directions are pinned — hidden until added, shown after.
        let blizzardUnadded = StoreLibrary.verdict(store: .battlenet, ownership: .unknown("no API"),
                                                   isConnected: false)
        try check(!blizzardUnadded.isVisible && blizzardUnadded.fix != nil,
                  "Library gate: a store nobody has connected hides its games, and offers the fix")
        try check(!StoreLibrary.verdict(store: .steam, ownership: .owned, isConnected: false).isVisible,
                  "Library gate: not even an owned game is shown for a store nobody signed in to")
        let blizzard = StoreLibrary.verdict(store: .battlenet, ownership: .unknown("no API"),
                                            isConnected: true)
        try check(blizzard.isVisible && blizzard.note != nil,
                  "Library gate: once added, a store that can never answer shows its games, saying so")
        try check(!GameStore.battlenet.canAnswerOwnership && GameStore.steam.canAnswerOwnership,
                  "Library gate: only the stores that publish entitlements are asked")
        try check(StoreLibrary.isConnected(.standalone),
                  "Library gate: a game with no storefront is never withheld for want of one")

        // 9. The readiness ladder, against fabricated states. Cellar downloads a Steam game itself
        // now, which no longer walks the player past the in-bottle client's sign-in — so a game
        // whose DRM talks to a running client must still *ask* for it, or the app shows "Ready to
        // play" and the game dies on its licence check with nothing having warned anybody. That is
        // a claim about the player's machine, so it is pinned here rather than left to a launch.
        func summary(store: GameStore, live: Bool, client: Bool, account: String?,
                     installed: Bool) -> GameSummary {
            GameSummary(slug: "x", name: "X", store: store, appID: 1, iconPath: nil,
                        runnerInstalled: true, clientInstalled: client, account: account,
                        gameInstalled: installed, bottleExists: true, running: false, productCode: "Fen",
                        ownership: .owned, needsLiveSession: live, artworkAppID: nil,
                        artPortraitURL: nil, artHeroURL: nil, needsClientAtRuntime: live,
                        facts: GameFacts(developer: nil, released: nil, engine: nil, graphicsAPI: nil,
                                         anticheat: nil, drm: nil, online: nil, requiresAccount: nil,
                                         status: nil, notes: nil),
                        runnerID: "wineforge", backend: "d3dmetal", bottleName: "x")
        }
        try check(summary(store: .steam, live: true, client: true, account: nil, installed: true)
                    .nextStep == .signIn,
                  "Readiness: a downloaded DRM game whose in-bottle Steam has no sign-in asks for one")
        try check(summary(store: .steam, live: true, client: true, account: "kennethdc", installed: true)
                    .nextStep == .play,
                  "Readiness: with that client signed in, the same game is ready")
        try check(summary(store: .steam, live: false, client: false, account: nil, installed: true)
                    .nextStep == .play,
                  "Readiness: a game that needs no live session never waits on a client it won't use")
        try check(summary(store: .steam, live: false, client: false, account: nil, installed: false)
                    .nextStep == .install,
                  "Readiness: and it goes straight to installing, with no 1.4 GB client first")
        // Blizzard publishes no sign-in state, so Cellar must never put a ✗ or a sign-in step there.
        try check(summary(store: .battlenet, live: true, client: true, account: nil, installed: true)
                    .nextStep == .play,
                  "Readiness: Battle.net is never asked for a sign-in Cellar cannot check")

        print(Term.green("All selftests passed."))
    }
}
