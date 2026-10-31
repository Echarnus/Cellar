import CellarDomain
import Foundation
import Testing
@testable import CellarData

/// Rockstar's games on Steam — Red Dead Redemption, Red Dead Redemption 2 and GTA V — pinned in
/// detail, with the readiness copy that comes from the launcher they start through.
///
/// Each is a Steam game whose DRM wants a running Steam client, *and* whose Steam copy starts
/// through the Rockstar Games Launcher: Steam runs a stub that hands off to it. What the profiles
/// must get right is which program is started (the stub), which is watched (the game), and that
/// none of them claims a result nobody has seen.
@Suite(.serialized)
struct RedDeadTests {

    /// Staged once, by the database lint, so two suites never delete each other's copies mid-run.
    static let staged: Bool = { _ = ProfileDatabaseTests.slugs; return true }()

    static func plan(_ slug: String) throws -> GamePlan {
        _ = staged
        return try Game.plan(slug: slug)
    }

    struct Expected: Sendable, CustomTestStringConvertible {
        let slug: String
        let name: String
        let appID: Int
        let installDir: String
        let exe: String
        let startExe: String
        let backend: GraphicsBackend
        let fallback: GraphicsBackend
        var testDescription: String { slug }
    }

    static let games: [Expected] = [
        Expected(slug: "red-dead-redemption-2", name: "Red Dead Redemption 2", appID: 1174180,
                 installDir: "Red Dead Redemption 2", exe: "RDR2.exe", startExe: "PlayRDR2.exe",
                 // DirectX 12 on Metal; DXVK only for the game's own Vulkan renderer on MoltenVK.
                 backend: .d3dmetal, fallback: .dxvk),
        Expected(slug: "red-dead-redemption", name: "Red Dead Redemption", appID: 2668510,
                 installDir: "Red Dead Redemption", exe: "RDR.exe", startExe: "PlayRDR.exe",
                 backend: .d3dmetal, fallback: .dxvk),
        Expected(slug: "grand-theft-auto-v", name: "Grand Theft Auto V", appID: 271590,
                 installDir: "Grand Theft Auto V", exe: "GTA5.exe", startExe: "PlayGTAV.exe",
                 backend: .d3dmetal, fallback: .dxmt),
    ]

    @Test("Each ships as a Steam game with the right AppID, folder, game exe and Steam's stub",
          arguments: RedDeadTests.games)
    func identity(_ game: Expected) throws {
        let plan = try Self.plan(game.slug)
        #expect(plan.name == game.name)
        #expect(plan.store == .steam, "bought and downloaded through Steam: Rockstar's launcher is not a store")
        #expect(plan.appID == game.appID, "the AppID is what Steam is told about; a wrong one is someone else's game")
        #expect(plan.installMethod == "windows-steam-in-bottle")
        #expect(plan.installDir == game.installDir)
        #expect(plan.launchExe == game.exe, "the game itself is what Cellar watches and shuts the layer down behind")
        #expect(plan.startExe == game.startExe, "Steam's stub is what is started, because it hands off to Rockstar")
        #expect(plan.startExe != plan.launchExe)
        #expect(plan.gameProcessNeedles.contains(game.exe))
    }

    @Test("Each starts through the Rockstar Games Launcher and needs a running Steam",
          arguments: RedDeadTests.games)
    func needsTheLauncher(_ game: Expected) throws {
        let plan = try Self.plan(game.slug)
        #expect(plan.publisherLauncher == .rockstar)
        #expect(plan.needsLiveSession, "Steamworks: a game started with no client exits straight back to nothing")
        #expect(plan.launchContext.throughClient)
        #expect(plan.facts.requiresAccount == "Steam + Rockstar Games account",
                "the second account is shown before the player installs, not discovered at Play")
        #expect(plan.facts.drm?.contains("Rockstar Games Launcher") == true)
    }

    @Test("Each picks the backend for its DirectX version, with a fallback", arguments: RedDeadTests.games)
    func backends(_ game: Expected) throws {
        let plan = try Self.plan(game.slug)
        #expect(plan.backend == game.backend.rawValue)
        #expect(plan.fallbackBackend == game.fallback.rawValue)
        #expect(plan.runnerID == "wineforge", "the current Steam client needs a modern Wine")
    }

    @Test("None claims more than has been run: untested, and the launcher's sign-in named as the risk",
          arguments: RedDeadTests.games)
    func honest(_ game: Expected) throws {
        let facts = try Self.plan(game.slug).facts
        #expect(facts.status == "untested")
        let notes = try #require(facts.notes)
        #expect(notes.hasPrefix("Not yet launched under Cellar"))
        #expect(notes.contains("Rockstar Games Launcher"))
        #expect(notes.contains("sign-in window"))
    }

    @Test("Red Dead Redemption 2's notes carry the one workaround reports give: DirectX 12 over Vulkan")
    func rdr2Workaround() throws {
        let plan = try Self.plan("red-dead-redemption-2")
        let notes = try #require(plan.facts.notes)
        #expect(notes.contains("switch Graphics API to DirectX 12"))
        #expect(plan.facts.graphicsAPI == "Vulkan or DirectX 12")
    }

    // MARK: - Readiness, read from a real bottle

    /// A Red Dead Redemption 2 bottle with the runner and Steam in it, the game downloaded, and the
    /// Rockstar launcher present or not.
    private func readiness(launcherInstalled: Bool) throws -> GameSummary {
        let install = try FakeWine.install()
        let plan = try TestHome.plan("""
        [game]
        name  = "Red Dead Fixture"
        store = "steam"

        [runner]
        id = "\(install.spec.id)"

        [install]
        steam_appid        = "1174180"
        exe                = "RDR2.exe"
        start_exe          = "PlayRDR2.exe"
        publisher_launcher = "rockstar"
        """, slug: "red-dead-readiness")
        try TestHome.installFakeGame(into: plan, at: "RDR2.exe")
        try TestHome.installFakeGame(into: plan, at: "PlayRDR2.exe")
        let steam = SteamBottle.steamExecutable(in: plan.prefix)
        try FileManager.default.createDirectory(at: steam.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data([0x4D, 0x5A]).write(to: steam)
        if launcherInstalled {
            let launcher = RockstarLauncher.executable(in: plan.prefix)
            try FileManager.default.createDirectory(at: launcher.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data([0x4D, 0x5A]).write(to: launcher)
        }
        return LoadLibrary.summary(of: plan)
    }

    @Test("A downloaded game whose bottle lacks the launcher is sent to Set up, which says a window opens")
    func missingLauncherIsSetup() throws {
        let summary = try readiness(launcherInstalled: false)
        #expect(summary.publisherLauncher == .rockstar)
        #expect(!summary.publisherLauncherInstalled)
        #expect(summary.launcherSetupPending)
        #expect(summary.nextStep == .setup, "without the launcher, Steam's stub has nothing to hand off to")
        #expect(summary.actionHint.contains("Rockstar Games Launcher"))
        #expect(summary.actionHint.contains("opens a window"), "Rockstar's installer is not silent, and the page says so")
    }

    @Test("With the launcher in the bottle, Play says Rockstar's window asks for the sign-in — never that it is done")
    func playNamesTheRockstarSignIn() throws {
        let summary = try readiness(launcherInstalled: true)
        #expect(summary.publisherLauncherInstalled)
        #expect(!summary.launcherSetupPending)
        if summary.nextStep == .play && !summary.clientSignInPending && !summary.updatePending {
            #expect(summary.actionHint.contains("Rockstar Games Launcher opens"))
            #expect(summary.actionHint.contains("Rockstar Games account"))
        }
        #expect(!summary.actionHint.contains("signed in"), "Cellar cannot see Rockstar's sign-in, so it claims none")
    }

    @Test("A game with no publisher launcher reads exactly as before")
    func otherGamesAreUntouched() throws {
        let plan = try Self.plan("assetto-corsa")
        #expect(plan.publisherLauncher == nil)
        #expect(plan.startExe == nil)
        let summary = LoadLibrary.summary(of: plan)
        #expect(summary.publisherLauncher == nil)
        #expect(!summary.launcherSetupPending)
        #expect(!summary.actionHint.contains("Rockstar"))
    }
}
