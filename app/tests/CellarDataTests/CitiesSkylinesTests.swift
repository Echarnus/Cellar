import CellarDomain
import Foundation
import Testing
@testable import CellarData

/// The shipped Cities: Skylines II profile, pinned in detail.
///
/// A Steamworks game, so it needs a running Steam client — but Steam's Play button starts the
/// Paradox Launcher, not the game, and Wine players report that launcher failing to reopen. So the
/// profile names the game binary itself, and a copy Cellar downloaded is started as that binary
/// beside a quiet Steam. What it must not do is claim a result nobody has seen: it is untested.
@Suite(.serialized)
struct CitiesSkylinesTests {

    static let slug = "cities-skylines-2"

    /// Staged once, by the database lint, so two suites never delete each other's copies mid-run.
    static let staged: Bool = { _ = ProfileDatabaseTests.slugs; return true }()

    static func plan() throws -> GamePlan {
        _ = staged
        return try Game.plan(slug: slug)
    }

    @Test("Ships as a Steam game with the right AppID, install folder and exe")
    func identity() throws {
        let plan = try Self.plan()
        #expect(plan.name == "Cities: Skylines II")
        #expect(plan.store == .steam)
        #expect(plan.appID == 949230, "the AppID is what Steam is told to start; a wrong one starts someone else's game")
        #expect(plan.installDir == "Cities Skylines II", "Steam's folder name has no colon in it")
        #expect(plan.launchExe == "Cities2.exe")
        #expect(plan.installMethod == "windows-steam-in-bottle")
    }

    @Test("The exe is the game itself, never the Paradox Launcher")
    func notTheLauncher() throws {
        let plan = try Self.plan()
        let exe = try #require(plan.launchExe).lowercased()
        #expect(!exe.contains("dowser") && !exe.contains("launcher"),
                "the launcher is what fails to reopen under Wine; Cellar starts the game past it")
    }

    @Test("Steamworks DRM means it needs a running Steam client")
    func needsSteam() throws {
        let plan = try Self.plan()
        #expect(plan.needsLiveSession, "a Steamworks game started with no client exits straight back to nothing")
        #expect(plan.launchContext.throughClient)
    }

    @Test("D3DMetal first, as every public Mac report ran it, with DXVK to fall back on")
    func backends() throws {
        let plan = try Self.plan()
        #expect(plan.backend == GraphicsBackend.d3dmetal.rawValue)
        #expect(plan.profileBackend == GraphicsBackend.d3dmetal.rawValue)
        #expect(plan.fallbackBackend == GraphicsBackend.dxvk.rawValue)
        #expect(plan.runnerID == "wineforge")
    }

    @Test("Claims no more than has been run, and says what players hit under Wine")
    func honest() throws {
        let facts = try Self.plan().facts
        #expect(facts.status == "untested")
        let notes = try #require(facts.notes)
        #expect(notes.contains("Not yet launched under Cellar"))
        #expect(notes.contains("full screen"), "the borderless slow-motion report is the one setting a player can act on")
        #expect(facts.anticheat == "none")
        // A Paradox account is optional; the profile must not tell a player they need one to play.
        let account = try #require(facts.requiresAccount)
        #expect(account.hasPrefix("Steam"))
        #expect(account.contains("optional"))
        #expect(facts.wheel == nil, "a city builder gets no racing-wheel row")
    }

    @Test("The game's own process is what Cellar watches, never Steam's")
    func needles() throws {
        let needles = try Self.plan().gameProcessNeedles
        #expect(needles.contains("Cities2.exe"))
        #expect(needles.contains("\\Cities Skylines II\\"))
        for needle in needles { #expect(!needle.lowercased().contains("steam")) }
    }

    @Test("A copy Cellar downloaded is started as Cities2.exe beside Steam, past the launcher")
    func downloadedCopyStartsTheGameDirectly() throws {
        let plan = try Self.plan()
        let fm = FileManager.default
        #expect(plan.directLaunchExe == nil)

        let exe = plan.depotGameDir.appendingPathComponent("Cities2.exe")
        try fm.createDirectory(at: plan.depotGameDir, withIntermediateDirectories: true)
        try Data("MZ".utf8).write(to: exe)
        defer { try? fm.removeItem(at: plan.prefix) }

        // No appmanifest for this copy, so the Steam adapter takes the launch-alongside route with
        // this exe, instead of `steam://rungameid` (which would run the Paradox Launcher).
        #expect(!SteamBottle.isGameInstalled(in: plan.prefix, appID: 949230))
        #expect(plan.directLaunchExe?.path == exe.path)
        #expect(!plan.canLaunchStoreFree, "the files being there does not make Steamworks DRM go away")
    }

    @Test("A copy Steam's client installed is found too")
    func findsClientInstalledCopy() throws {
        let plan = try Self.plan()
        let fm = FileManager.default
        let root = plan.prefix.appendingPathComponent(
            "drive_c/Program Files (x86)/Steam/steamapps/common/Cities Skylines II", isDirectory: true)
        let exe = root.appendingPathComponent("Cities2.exe")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("MZ".utf8).write(to: exe)
        defer { try? fm.removeItem(at: plan.prefix) }

        #expect(plan.directLaunchExe?.path == exe.path)
    }

    @Test("Gets real cover art from its Steam AppID")
    func coverArt() throws {
        _ = Self.staged
        let summary = try #require(Game.summaries().first { $0.slug == Self.slug })
        #expect(summary.artworkAppID == 949230)
    }
}
