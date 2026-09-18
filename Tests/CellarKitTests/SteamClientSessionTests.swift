import Foundation
import Testing
@testable import CellarKit

/// Handing the Windows Steam client in a bottle the session the player gave Cellar. Every token and
/// blob here is dummy data: nothing in this file is, or decrypts to, a real credential.
struct SteamClientSessionTests {

    // MARK: - Wine's CryptProtectData

    /// Made by real Wine (the WineForge runner, `CryptProtectData` in a bottle) as user
    /// `cellartest`, entropy `dummyaccount`, from `dummyPlain`. Pins the port to Wine, not to itself.
    static let wineBlob = """
        0100000057696e652043727970743332206f6b000100000057696e652043727970743332206f6b0000000000020000\
        00000003660000a80000001000000057696e652043727970743332206f6b000000000004800000a000000010000000\
        562316988ca613471f28b61437a729cc4000000011df93df7c680f783635f2d77546adb838e701a0ea48eaba06d458\
        f5e12d4f1a5fa7ae715fff83e4929f5d07db0804857a7bc06204c19eb649349965050370231400000066a486e83393\
        3f585a94799d46fdad2c50db8d73
        """
    static let dummyPlain = "eyJhbGciOiJFZERTQSJ9.eyJkdW1teSI6dHJ1ZX0.not-a-real-token"

    static func bytes(_ hex: String) -> Data {
        let c = Array(hex.utf8)
        return Data(stride(from: 0, to: c.count - 1, by: 2).map {
            UInt8(String(decoding: c[$0..<$0 + 2], as: UTF8.self), radix: 16)!
        })
    }

    @Test("A blob Wine made decrypts here, with the user name and entropy it was made with")
    func decryptsWhatWineMade() {
        let blob = Self.bytes(Self.wineBlob)
        let plain = WineDPAPI.unprotect(blob, user: "cellartest", entropy: Data("dummyaccount".utf8))
        #expect(plain == Data(Self.dummyPlain.utf8))
        #expect(WineDPAPI.unprotect(blob, user: "someoneelse", entropy: Data("dummyaccount".utf8)) == nil,
                "the Wine user is part of the key — a bottle run as someone else can't read it")
        #expect(WineDPAPI.unprotect(blob, user: "cellartest", entropy: Data("otheraccount".utf8)) == nil)
    }

    @Test("Given Wine's salt, the blob made here is byte-for-byte the one Wine made")
    func encryptsExactlyAsWineDoes() {
        let blob = Self.bytes(Self.wineBlob)
        // The salt is the 16 bytes after its length prefix, at offset 94: two magics with their
        // versions (44), the empty description (6), the cipher, key size, magic and flags (38),
        // the hash algorithm and size (8), and the prefix itself (4).
        let salt = blob.subdata(in: 94..<110)
        #expect(salt.count == 16)
        let made = WineDPAPI.protect(Data(Self.dummyPlain.utf8), user: "cellartest",
                                     entropy: Data("dummyaccount".utf8), salt: salt)
        #expect(made == blob)
    }

    @Test("A fresh salt every time, and still round-trips")
    func randomSalt() throws {
        let plain = Data("dummy".utf8)
        let a = try #require(WineDPAPI.protect(plain, user: "u", entropy: nil))
        let b = try #require(WineDPAPI.protect(plain, user: "u", entropy: nil))
        #expect(a != b)
        #expect(WineDPAPI.unprotect(a, user: "u", entropy: nil) == plain)
    }

    // MARK: - The token and its key

    static func jwt(sub: String = "76561197960265728", aud: [String] = ["client", "web"],
                    expires: Date = Date().addingTimeInterval(180 * 86400), per: Int? = 1) -> String {
        var payload: [String: Any] = ["iss": "steam", "sub": sub, "aud": aud, "exp": Int(expires.timeIntervalSince1970)]
        if let per { payload["per"] = per }
        func b64(_ d: Data) -> String {
            d.base64EncodedString().replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        }
        let body = try! JSONSerialization.data(withJSONObject: payload)
        return "\(b64(Data(#"{"typ":"JWT","alg":"EdDSA"}"#.utf8))).\(b64(body)).dummysignature"
    }

    @Test("Only a client token that outlives the launch is handed over")
    func tokenClaims() throws {
        let good = try #require(SteamClientSession.claims(ofToken: Self.jwt()))
        #expect(good.steamID == "76561197960265728")
        #expect(good.persistent == true)
        #expect(good.isUsable())
        #expect(!(SteamClientSession.claims(ofToken: Self.jwt(aud: ["web"]))!.isUsable()),
                "a web-only token is not one the client accepts")
        #expect(!(SteamClientSession.claims(ofToken: Self.jwt(expires: Date().addingTimeInterval(600)))!.isUsable()))
        #expect(SteamClientSession.claims(ofToken: "not.a-jwt") == nil)
        #expect(SteamClientSession.claims(ofToken: "") == nil)
    }

    @Test("The ConnectCache key is crc32 of the lowercased name in bare hex, then 1")
    func connectCacheKey() {
        // crc32("123456789") is the standard check value, 0xcbf43926.
        #expect(SteamClientSession.connectCacheKey(account: "123456789") == "cbf439261")
        #expect(SteamClientSession.connectCacheKey(account: "SomeAccount")
            == SteamClientSession.connectCacheKey(account: "someaccount"))
        // printf("%x") — no zero padding.
        let key = SteamClientSession.connectCacheKey(account: "a")
        #expect(key == String(CRC32.checksum("a"), radix: 16) + "1")
    }

    @Test("The token is read from DepotDownloader's store only for the account asked about")
    func tokenFromStore() {
        let store = SteamSignInTests.store(tokens: [("otheruser", "dummy-other"), ("SomeAccount", "dummy-mine")],
                                           guard: [("someaccount", "guard")])
        #expect(DepotAccountStore.refreshToken(for: "someaccount", inCompressed: store) == "dummy-mine")
        #expect(DepotAccountStore.refreshToken(for: "nobody", inCompressed: store) == nil)
        #expect(DepotAccountStore.refreshToken(for: "x", inCompressed: Data("garbage".utf8)) == nil)
    }

    // MARK: - Steam's files

    @Test("Text VDF round-trips exactly, escapes included")
    func vdfRoundTrip() throws {
        let text = "\"InstallConfigStore\"\n{\n\t\"Software\"\n\t{\n\t\t\"Path\"\t\t\"C:\\\\Program Files (x86)\\\\Steam\"\n\t\t\"Quote\"\t\t\"say \\\"hi\\\"\"\n\t}\n\t\"Multi\"\t\t\"line one\nline two\"\n}\n"
        let parsed = try #require(TextVDF.parse(text))
        #expect(parsed.text == text)
        #expect(parsed.block(at: ["InstallConfigStore", "software"])?.string("Path") == #"C:\Program Files (x86)\Steam"#)
        #expect(TextVDF.parse("\"a\"\n{\n\t\"b\"\t\t\"c\"\n") == nil, "an unclosed block is refused, not guessed at")
        #expect(TextVDF.parse("\"a\"\t\"b\"\n}") == nil)
    }

    @Test("local.vdf gains the encrypted token under ConnectCache, and keeps what was there")
    func connectCacheWrite() throws {
        let existing = try #require(TextVDF.parse("\"MachineUserConfigStore\"\n{\n\t\"Software\"\n\t{\n\t\t\"Valve\"\n\t\t{\n\t\t\t\"Steam\"\n\t\t\t{\n\t\t\t\t\"Other\"\t\t\"kept\"\n\t\t\t}\n\t\t}\n\t}\n}\n"))
        let file = SteamClientSession.withConnectCache(existing, account: "SomeAccount", value: "0badc0de")
        let steam = try #require(file.block(at: ["MachineUserConfigStore", "Software", "Valve", "Steam"]))
        #expect(steam.string("Other") == "kept")
        #expect(steam.block("ConnectCache")?.string(SteamClientSession.connectCacheKey(account: "someaccount")) == "0badc0de")
    }

    @Test("loginusers.vdf names the account as remembered and most recent, and demotes the others")
    func loginUsersWrite() throws {
        let existing = try #require(TextVDF.parse("\"users\"\n{\n\t\"76561197960265729\"\n\t{\n\t\t\"AccountName\"\t\t\"other\"\n\t\t\"MostRecent\"\t\t\"1\"\n\t}\n}\n"))
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let file = SteamClientSession.withLoginUser(existing, steamID: "76561197960265728", account: "SomeAccount", now: now)
        let users = try #require(file.block("users"))
        let me = try #require(users.block("76561197960265728"))
        #expect(me.string("AccountName") == "someaccount")
        #expect(me.string("RememberPassword") == "1")
        #expect(me.string("AllowAutoLogin") == "1")
        #expect(me.string("MostRecent") == "1")
        #expect(me.string("Timestamp") == "1800000000")
        #expect(users.block("76561197960265729")?.string("MostRecent") == "0")
        // SteamBottle's own reader agrees on who is signed in.
        #expect(SteamClientSession.remembers(file, account: "someaccount"))
    }

    @Test("config.vdf records the account's SteamID and turns the account picker off")
    func configWrite() {
        let file = SteamClientSession.withAccount(TextVDF(), steamID: "76561197960265728", account: "SomeAccount")
        #expect(file.block(at: ["InstallConfigStore", "Software", "Valve", "Steam", "Accounts", "someaccount"])?
            .string("SteamID") == "76561197960265728")
        #expect(file.block(at: ["InstallConfigStore", "Software", "WebStorage", "Auth"])?
            .string("AlwaysShowUserChooser") == "0")
    }

    // MARK: - The decision

    static func snapshot(account: String? = "someaccount", token: String? = jwt(),
                         local: String? = nil, users: String? = nil, config: String? = nil,
                         userFolder: Bool = true) -> SteamClientSession.Snapshot {
        .init(cellarAccount: account, token: token, localConfig: local, loginUsers: users, config: config,
              hasWineUserFolder: userFolder)
    }

    @Test("A fresh bottle with a signed-in Cellar is handed the session")
    func freshBottle() {
        #expect(SteamClientSession.readiness(Self.snapshot()) == .canHandOver)
        #expect(SteamClientSession.readiness(Self.snapshot()).signsInByItself)
    }

    @Test("Every reason not to hand it over falls back to Steam's own window")
    func unavailable() {
        #expect(SteamClientSession.readiness(Self.snapshot(account: nil)) == .unavailable(.notSignedIn))
        #expect(SteamClientSession.readiness(Self.snapshot(token: nil)) == .unavailable(.tokenNotForClient))
        #expect(SteamClientSession.readiness(Self.snapshot(token: Self.jwt(aud: ["web"])))
            == .unavailable(.tokenNotForClient))
        #expect(SteamClientSession.readiness(Self.snapshot(userFolder: false)) == .unavailable(.bottleNotReady))
        #expect(SteamClientSession.readiness(Self.snapshot(config: "\"broken\"\n{\n"))
            == .unavailable(.unreadableFiles), "a file Cellar can't read is a file it won't rewrite")
        #expect(!SteamClientSession.Readiness.unavailable(.notSignedIn).signsInByItself)
    }

    @Test("A client signed in to another account by hand is left alone")
    func otherAccount() {
        let users = "\"users\"\n{\n\t\"76561197960265729\"\n\t{\n\t\t\"AccountName\"\t\t\"somebodyelse\"\n\t}\n}\n"
        #expect(SteamClientSession.readiness(Self.snapshot(users: users)) == .unavailable(.otherAccount))
    }

    @Test("A bottle whose client already remembers this account needs nothing, even without a token")
    func remembered() {
        let key = SteamClientSession.connectCacheKey(account: "someaccount")
        let local = "\"MachineUserConfigStore\"\n{\n\t\"Software\"\n\t{\n\t\t\"Valve\"\n\t\t{\n\t\t\t\"Steam\"\n\t\t\t{\n\t\t\t\t\"ConnectCache\"\n\t\t\t\t{\n\t\t\t\t\t\"\(key)\"\t\t\"00\"\n\t\t\t\t}\n\t\t\t}\n\t\t}\n\t}\n}\n"
        let users = "\"users\"\n{\n\t\"76561197960265728\"\n\t{\n\t\t\"AccountName\"\t\t\"SomeAccount\"\n\t}\n}\n"
        #expect(SteamClientSession.readiness(Self.snapshot(token: nil, local: local, users: users)) == .remembered)
        // The shared install knows the account, but this bottle's own local.vdf doesn't: a second
        // Steam game's bottle still needs the session handed over.
        #expect(SteamClientSession.readiness(Self.snapshot(users: users)) == .canHandOver)
    }

    @Test("Steam's verdict is read from connection_log.txt, the last logon winning")
    func logonResult() {
        let ok = """
            [2026-09-17 19:39:27] [Logging On, 4, 7] [U:1:1] Using JWT 1, persistence: 1, steamid: [U:1:1]
            [2026-09-17 19:39:27] [Logging On, 4, 7] [U:1:1] RecvMsgClientLogOnResponse() : [U:1:1] 'OK'
            [2026-09-17 19:39:27] [Logged On, 4, 7] [U:1:1] RecvMsgClientLogOnResponse() : processing complete
            """
        #expect(SteamClientSession.logonResult(inConnectionLog: ok) == .loggedOn)
        let refused = ok + "\n[2026-09-17 19:50:00] [Logging On, 4, 7] [U:1:1] RecvMsgClientLogOnResponse() : [U:1:1] 'AccessDenied'\n"
        #expect(SteamClientSession.logonResult(inConnectionLog: refused) == .refused("AccessDenied"))
        #expect(SteamClientSession.logonResult(inConnectionLog: "[2026-09-17] Connectivity test: OK!") == nil)
    }
}
