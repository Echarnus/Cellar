import Foundation
import Testing
@testable import CellarKit

/// Reading Steam's own state out of a bottle. These parsers decide whether the app shows "signed
/// in", "installed", or a step the player has already done — so a false positive here is exactly
/// the dishonesty `skills/ux.md` forbids.
@Suite(.serialized)
struct SteamBottleTests {

    /// Build a bottle skeleton with the Windows Steam layout Cellar expects.
    private func bottle(steamFiles: [String: String] = [:]) throws -> URL {
        let prefix = TestHome.scratch("bottle")
        for (relative, contents) in steamFiles {
            let url = SteamBottle.steamDirectory(in: prefix).appendingPathComponent(relative)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try contents.write(to: url, atomically: true, encoding: .utf8)
        }
        return prefix
    }

    // MARK: - Layout

    @Test("Steam lives at the 32-bit Program Files path the installer actually uses")
    func layout() {
        let prefix = URL(fileURLWithPath: "/bottles/pc2")
        #expect(SteamBottle.steamDirectory(in: prefix).path
            == "/bottles/pc2/drive_c/Program Files (x86)/Steam")
        #expect(SteamBottle.steamExecutable(in: prefix).lastPathComponent == "steam.exe")
        #expect(SteamBottle.logsDirectory(in: prefix).lastPathComponent == "logs")
    }

    @Test("An empty bottle has no client, and says so")
    func emptyBottle() throws {
        let prefix = try bottle()
        #expect(SteamBottle.isInstalled(in: prefix) == false)
        #expect(SteamBottle.isClientUpdated(in: prefix) == false)
        #expect(SteamBottle.loggedInAccount(in: prefix) == nil)
    }

    @Test("The bootstrapper alone is not a working client")
    func bootstrapperIsNotUpdated() throws {
        // The installer drops a ~9 MB steam.exe; only after its first self-update is there a
        // steamclient64.dll. Reporting "ready" in between sends the player to a client that can't
        // launch anything.
        let prefix = try bottle(steamFiles: ["steam.exe": "MZ"])
        #expect(SteamBottle.isInstalled(in: prefix))
        #expect(SteamBottle.isClientUpdated(in: prefix) == false)

        let updated = try bottle(steamFiles: ["steam.exe": "MZ", "steamclient64.dll": "MZ"])
        #expect(SteamBottle.isClientUpdated(in: updated))
    }

    // MARK: - loginusers.vdf

    @Test("The signed-in account is read out of loginusers.vdf")
    func readsAccountName() throws {
        let prefix = try bottle(steamFiles: ["config/loginusers.vdf": """
        "users"
        {
            "76561197960287930"
            {
                "AccountName"    "kenneth"
                "PersonaName"    "Kenneth"
                "RememberPassword"    "1"
                "MostRecent"    "1"
            }
        }
        """])
        #expect(SteamBottle.loggedInAccount(in: prefix) == "kenneth")
    }

    @Test("A loginusers.vdf with no account yields nil rather than a wrong name")
    func emptyLoginUsers() throws {
        let prefix = try bottle(steamFiles: ["config/loginusers.vdf": "\"users\"\n{\n}\n"])
        #expect(SteamBottle.loggedInAccount(in: prefix) == nil)
    }

    @Test("Account names with dots, dashes and digits survive the regex")
    func awkwardAccountNames() throws {
        for name in ["kenneth.de.clercq", "user-123", "A_B_C", "x"] {
            let prefix = try bottle(steamFiles: [
                "config/loginusers.vdf": "\"users\" { \"1\" { \"AccountName\" \"\(name)\" } }"])
            #expect(SteamBottle.loggedInAccount(in: prefix) == name)
        }
    }

    // MARK: - appmanifest

    @Test("The install directory is read out of the app manifest")
    func readsInstallDirectory() throws {
        let prefix = try bottle(steamFiles: ["steamapps/appmanifest_1493710.acf": """
        "AppState"
        {
            "appid"        "1493710"
            "name"         "Planet Coaster 2"
            "StateFlags"   "4"
            "installdir"   "Planet Coaster 2"
        }
        """])
        #expect(SteamBottle.installDirectory(in: prefix, appID: 1_493_710) == "Planet Coaster 2")
        #expect(SteamBottle.installDirectory(in: prefix, appID: 999) == nil)
    }

    @Test("Only StateFlags 4 counts as fully installed")
    func stateFlagsGateInstalled() throws {
        // 1026 = update required / partially downloaded. Calling that "installed" puts a Play
        // button in front of a game that will not start.
        let partial = try bottle(steamFiles: ["steamapps/appmanifest_42.acf": """
        "AppState" { "appid" "42" "StateFlags" "1026" "installdir" "Half A Game" }
        """])
        #expect(SteamBottle.isGameInstalled(in: partial, appID: 42) == false)

        let complete = try bottle(steamFiles: ["steamapps/appmanifest_42.acf": """
        "AppState" { "appid" "42" "StateFlags" "4" "installdir" "A Game" }
        """])
        #expect(SteamBottle.isGameInstalled(in: complete, appID: 42))
    }

    @Test("A missing manifest is 'not installed', not a crash")
    func missingManifest() throws {
        let prefix = try bottle()
        #expect(SteamBottle.isGameInstalled(in: prefix, appID: 1) == false)
        #expect(SteamBottle.installDirectory(in: prefix, appID: 1) == nil)
    }

    // MARK: - The shared install

    @Test("A bottle with its own Steam directory is not linked to the shared install")
    func ownInstallIsNotShared() throws {
        let prefix = try bottle(steamFiles: ["steam.exe": "MZ"])
        #expect(SteamBottle.isLinkedToSharedInstall(in: prefix) == false)
        #expect(SteamBottle.hasOwnSteamInstallForDiagnostics(in: prefix))
    }

    @Test("A symlinked bottle reads as linked, and shares the account")
    func linkedBottleSharesSignIn() throws {
        TestHome.ensure()
        let fm = FileManager.default
        let shared = Paths.sharedSteam
        try fm.createDirectory(at: shared.appendingPathComponent("config"), withIntermediateDirectories: true)
        try "\"users\" { \"1\" { \"AccountName\" \"shared-account\" } }"
            .write(to: shared.appendingPathComponent("config/loginusers.vdf"),
                   atomically: true, encoding: .utf8)
        try Data("MZ".utf8).write(to: shared.appendingPathComponent("steam.exe"))
        defer { try? fm.removeItem(at: shared) }

        let prefix = TestHome.scratch("linked")
        let bottleSteam = SteamBottle.steamDirectory(in: prefix)
        try fm.createDirectory(at: bottleSteam.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.createSymbolicLink(at: bottleSteam, withDestinationURL: shared)

        #expect(SteamBottle.isSharedInstallPresent)
        #expect(SteamBottle.isLinkedToSharedInstall(in: prefix))
        #expect(SteamBottle.hasOwnSteamInstall(in: prefix) == false,
                "a symlink is not a second copy — that is the point of signing in once")
        #expect(SteamBottle.loggedInAccount(in: prefix) == "shared-account")
        #expect(SteamBottle.sharedLoggedInAccount == "shared-account")
    }

    // MARK: - The steam_dev.cfg trick

    @Test("The platform trick targets the player's native Steam, not a bottle")
    func platformTrickPath() {
        // Read-only on purpose. Unlike everything else here, this one writes into the *native* macOS
        // Steam installation — it is not redirected by CELLAR_HOME and cannot be, since that is the
        // client it exists to modify. A test must therefore never call enable().
        let path = SteamPlatformTrick.cfgPath.path
        #expect(path.hasSuffix("Steam.AppBundle/Steam/Contents/MacOS/steam_dev.cfg"))
        #expect(path.contains(FileManager.default.homeDirectoryForCurrentUser.path))
        #expect(path.contains(Paths.appSupport.path) == false,
                "this is Steam's own file; it must not be looked for inside Cellar's home")
        #expect(SteamPlatformTrick.isEnabled == FileManager.default.fileExists(atPath: path))
    }

    // MARK: - Superseded-install naming

    @Test("A superseded Steam directory gets a name Finder can show")
    func supersededStampIsFilenameSafe() {
        // adoptSharedInstall moves an old Steam aside as `Steam.superseded-<stamp>`. A colon in
        // that stamp would show up as a slash in Finder and read as a broken path.
        let stamp = ISO8601DateFormatter.filenameSafe.string(from: Date(timeIntervalSince1970: 1_757_000_000))
        #expect(stamp.contains(":") == false)
        #expect(stamp.contains("/") == false)
        #expect(stamp.contains("-"), "the date is still readable")
    }
}
