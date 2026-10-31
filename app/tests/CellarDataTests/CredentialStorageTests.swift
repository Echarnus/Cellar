import CellarDomain
import Foundation
import Security
import Testing
@testable import CellarData

/// Where a sign-in may and may not end up (issue #79).
///
/// Cellar holds credentials for real store accounts: GOG's OAuth tokens in the keychain, Steam's
/// refresh token in DepotDownloader's store and — DPAPI-wrapped — in each bottle's `local.vdf`.
/// These tests pin the rules from OWASP MASVS-STORAGE-1/2 as they apply here: a secret is stored
/// only where it is meant to be, readable only by the player, and it never reaches the log, the
/// diagnostics report or a backup. Each test feeds the *shape* a real leak would have — a Steam JWT,
/// a DepotDownloader command line, a DPAPI blob — rather than a string made up to suit the regex.
@Suite(.serialized)
struct CredentialStorageTests {

    // MARK: - Fixtures shaped like the real thing

    static func b64url(_ text: String) -> String {
        Data(text.utf8).base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }

    /// Steam writes its JWT header and payload with a space after the brace, so they encode as
    /// `eyAi…`, not the `eyJ…` most JWTs start with.
    static let steamToken = b64url(#"{ "typ": "JWT", "alg": "EdDSA" }"#) + "."
        + b64url(#"{ "iss": "steam", "sub": "76561197960265728", "aud": [ "client", "web" ], "exp": 1900000000 }"#)
        + ".c2lnbmF0dXJlLWJ5dGVzLWdvLWhlcmUtc2lnbmF0dXJlLWJ5dGVz"

    static let compactToken = b64url(#"{"alg":"HS256","typ":"JWT"}"#) + "."
        + b64url(#"{"user_id":"48628349957132247","exp":1900000000}"#) + ".sGnvBZ2UhxuVbqk9Z6c1q0"

    static let gogRefresh = "6fa2f2b8c9d04a31a7a0e5d0c4b1e9f2aa31bc77d0c6e4f19b8a7c6d5e4f3a2b"

    // MARK: - The keychain item

    @Test("A keychain query names the item and never carries the secret")
    func queryHasNoValue() {
        let query = Keychain.query(account: "oauth-session", service: Keychain.service(for: .gog))
        #expect(query[kSecValueData as String] == nil)
        #expect(query[kSecAttrService as String] as? String == "it.clercq.cellar.gog")
        #expect(query[kSecAttrAccount as String] as? String == "oauth-session")
        #expect(Keychain.query(account: nil, service: "x")[kSecAttrAccount as String] == nil,
                "no account means every item under the service — what removeAll deletes")
    }

    @Test("A saved token is this-device-only, readable only while unlocked, and labelled without its value")
    func itemAttributes() {
        let attributes = Keychain.attributes(value: Self.gogRefresh, label: Keychain.label(for: .gog))
        #expect(attributes[kSecAttrAccessible as String] as? String
                == kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String,
                "never synced to iCloud or restored onto another Mac")
        #expect(attributes[kSecValueData as String] as? Data == Data(Self.gogRefresh.utf8))
        for key in [kSecAttrLabel as String, kSecAttrDescription as String] {
            let text = attributes[key] as? String ?? ""
            #expect(!text.isEmpty, "a nameless item in Keychain Access is one nobody dares delete")
            #expect(!text.contains(Self.gogRefresh))
        }
        #expect(Keychain.label(for: .gog).contains("GOG"))
    }

    @Test("Each store has its own keychain service, so signing out of one never touches another")
    func servicesAreDistinct() {
        let services = GameStore.allCases.map(Keychain.service(for:))
        #expect(Set(services).count == services.count)
        #expect(services.allSatisfy { $0.hasPrefix("it.clercq.cellar.") })
    }

    // MARK: - Redaction at write time

    @Test("Credentials are taken out of a line whatever they are called", arguments: [
        "Steam token \(CredentialStorageTests.steamToken) accepted",
        "jwt=\(CredentialStorageTests.compactToken)",
        "Authorization: Bearer \(CredentialStorageTests.gogRefresh)",
        #"{"access_token": "\#(CredentialStorageTests.gogRefresh)", "expires_in": 3600}"#,
        "refresh_token=\(CredentialStorageTests.gogRefresh)&grant_type=refresh_token",
        "POST /token client_secret=\(CredentialStorageTests.gogRefresh)",
        "https://embed.gog.com/on_login_success?origin=client&code=\(CredentialStorageTests.gogRefresh)",
        "DepotDownloader -username player -password \(CredentialStorageTests.gogRefresh)",
        "steam --password=\(CredentialStorageTests.gogRefresh)",
    ])
    func credentialsRemoved(_ line: String) {
        let out = Diagnostics.redactCredentials(line)
        #expect(!out.contains(Self.gogRefresh))
        #expect(!out.contains(Self.steamToken))
        #expect(!out.contains(Self.compactToken))
        #expect(out.contains("<redacted"))
    }

    @Test("A Steam Remember-me blob from a bottle's local.vdf is taken out")
    func dpapiBlobRemoved() throws {
        let blob = try #require(SteamClientSession.protectedToken(Self.steamToken, account: "player",
                                                                  wineUser: "player"))
        let line = #""ConnectCache" { "1a2b3c4d1" "\#(blob)" }"#
        let out = Diagnostics.redactCredentials(line)
        #expect(!out.contains(blob))
        #expect(out.contains("1a2b3c4d1"), "the key is a CRC, not a secret — keep what makes the line readable")
    }

    @Test("Ordinary log lines come through write-time redaction untouched", arguments: [
        "DepotDownloader exited 3.",
        "Got manifest request code for depot 1222671 from app 1222670",
        "Steam signed in (12 days) — record: present, token store at ~/Library/Application Support/IsolatedStorage",
        "Next time you can login with -remember-password instead of -qr.",
        "sha256 9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08",
        "launch planet-coaster-2 --backend d3dmetal",
    ])
    func ordinaryLinesKept(_ line: String) {
        #expect(Diagnostics.redactCredentials(line) == line,
                "a log redacted into uselessness is a log nobody can diagnose from")
    }

    @Test("The rolling log never stores a token, even when a caller hands it one")
    func logRedactsOnWrite() throws {
        TestHome.ensure()
        let marker = "credential-test-\(UUID().uuidString)"
        CellarLog.warn(.account, "\(marker) refresh failed for token \(Self.steamToken) (Bearer \(Self.gogRefresh))")
        let history = CellarLog.history()
        // The log can be switched off for a run (`CELLAR_LOG_LEVEL=off`); then there is nothing to leak.
        guard history.contains(marker) else { return }
        #expect(!history.contains(Self.steamToken))
        #expect(!history.contains(Self.gogRefresh))
    }

    @Test("The log is the player's alone to read: 0600 files in a 0700 folder")
    func logIsPrivate() throws {
        TestHome.ensure()
        CellarLog.info(.diagnostics, "permission check")
        guard FileManager.default.fileExists(atPath: CellarLog.fileURL.path) else { return }
        #expect(PrivateFiles.mode(of: Paths.logs) == 0o700)
        for file in CellarLog.files { #expect(PrivateFiles.mode(of: file) == 0o600, "\(file.lastPathComponent)") }
    }

    // MARK: - Redaction for a report that will be posted

    @Test("The report removes the player's own account names, wherever a client log printed them")
    func identitiesRemoved() {
        let text = """
        Logged on as KennethDC (76561197960265728)
        Success! Next time you can login with -username kennethdc -remember-password instead of -qr.
        GOG user kenneth_gog owns 12 games
        """
        let out = Diagnostics.redact(text, identities: ["kennethdc", "kenneth_gog"])
        #expect(!out.lowercased().contains("kennethdc"))
        #expect(!out.contains("kenneth_gog"))
        #expect(out.contains("<account>"))
        #expect(out.contains("-remember-password"), "the flag is kept; only the value goes")
    }

    @Test("A name is removed as a word, never from inside another word")
    func identitiesMatchWholeWords() {
        let out = Diagnostics.redact("player Ann ran Anniversary Edition", identities: ["Ann"])
        #expect(out.contains("Anniversary"))
        #expect(!out.contains(" Ann "))
    }

    @Test("DepotDownloader's single-dash options lose their values in a report")
    func depotDownloaderOptions() {
        let out = Diagnostics.redact("DepotDownloader -app 480 -username someone -password hunter2",
                                     identities: [])
        #expect(!out.contains("someone"))
        #expect(!out.contains("hunter2"))
        #expect(out.contains("-app 480"))
    }

    // MARK: - Files that hold or describe a credential

    @Test("A private write is 0600 from the start, replaces atomically and leaves no staging file")
    func privateWrite() throws {
        let dir = TestHome.scratch("private")
        let file = dir.appendingPathComponent("record.json")
        try PrivateFiles.write(Data("first".utf8), to: file)
        #expect(PrivateFiles.mode(of: file) == 0o600)
        try PrivateFiles.write(Data("second".utf8), to: file)
        #expect(try String(contentsOf: file, encoding: .utf8) == "second")
        #expect(PrivateFiles.mode(of: file) == 0o600, "replacing must not reopen the file to everyone")
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        #expect(leftovers == ["record.json"])
    }

    @Test("A credential file is tightened and kept out of Time Machine")
    func protectCredential() throws {
        let dir = TestHome.scratch("token-store")
        let file = dir.appendingPathComponent("account.config")
        try Data([1, 2, 3]).write(to: file)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path)
        PrivateFiles.protectCredential(file)
        #expect(PrivateFiles.mode(of: file) == 0o600)
        #expect(PrivateFiles.isExcludedFromBackup(file))
    }

    @Test("Cellar's own folders around the Steam token are closed to other accounts")
    func restrictDirectory() {
        let dir = TestHome.scratch("depot-home")
        PrivateFiles.restrict(directory: dir)
        #expect(PrivateFiles.mode(of: dir) == 0o700)
    }

    @Test("The GOG name is cached privately, shared by app and CLI, and gone on sign-out")
    func gogNameCache() throws {
        TestHome.ensure()
        defer { GOGAuth.cacheUsername(nil) }
        GOGAuth.cacheUsername("cellar-test-player")
        #expect(GOGAuth.cachedUsername == "cellar-test-player")
        #expect(GOGAuth.usernameFile.path.hasPrefix(Paths.appSupport.path), "inside Cellar's home, not a defaults domain")
        #expect(PrivateFiles.mode(of: GOGAuth.usernameFile) == 0o600)
        GOGAuth.cacheUsername(nil)
        #expect(GOGAuth.cachedUsername == nil)
        #expect(!FileManager.default.fileExists(atPath: GOGAuth.usernameFile.path))
    }

    // MARK: - Reset and uninstall

    @Test("A relocated Cellar never plans to remove the player's real sign-ins")
    func relocatedResetKeepsRealCredentials() {
        TestHome.ensure()
        #expect(Reset.isRelocated)
        let credentials = Reset.plan(includingCellarItself: true).filter {
            if case .storeCredentials = $0.target { return true }
            return false
        }
        #expect(credentials.isEmpty,
                "the keychain and .NET isolated storage are the player's real ones, not the sandbox's")
    }

    @Test("Only token files outside Cellar's folder are named — never the shared folder they sit in")
    func strayStoresAreFiles() {
        for url in Reset.steamTokenStoresOutsideCellar {
            #expect(url.lastPathComponent == "account.config")
            #expect(!url.path.hasPrefix(DepotTool.root.path + "/"))
        }
    }
}
