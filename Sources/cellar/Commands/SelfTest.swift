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
        let steamUnchecked = StoreLibrary.verdict(store: .steam, ownership: .unknown("not checked"))
        try check(!steamUnchecked.isVisible && steamUnchecked.fix != nil,
                  "Library gate: a store that could answer but hasn't hides its games, and offers the fix")
        try check(StoreLibrary.verdict(store: .steam, ownership: .owned).isVisible,
                  "Library gate: a game Steam confirmed is shown")
        try check(!StoreLibrary.verdict(store: .steam, ownership: .notOwned).isVisible,
                  "Library gate: a game Steam refused is not shown")
        let blizzard = StoreLibrary.verdict(store: .battlenet, ownership: .unknown("no API"))
        try check(blizzard.isVisible && blizzard.note != nil,
                  "Library gate: a store that can never answer shows its games, saying so")
        try check(!GameStore.battlenet.canAnswerOwnership && GameStore.steam.canAnswerOwnership,
                  "Library gate: only the stores that publish entitlements are asked")

        // 9. The readiness ladder, against fabricated states. Cellar downloads a Steam game itself
        // now, which no longer walks the player past the in-bottle client's sign-in — so a game
        // whose DRM talks to a running client must still *ask* for it, or the app shows "Ready to
        // play" and the game dies on its licence check with nothing having warned anybody. That is
        // a claim about the player's machine, so it is pinned here rather than left to a launch.
        func summary(store: GameStore, live: Bool, client: Bool, account: String?,
                     installed: Bool) -> GameSummary {
            GameSummary(slug: "x", name: "X", store: store, appID: 1, iconPath: nil,
                        runnerInstalled: true, clientInstalled: client, account: account,
                        gameInstalled: installed, running: false, productCode: "Fen",
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
