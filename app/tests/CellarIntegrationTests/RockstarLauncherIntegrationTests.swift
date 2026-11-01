import CellarDomain
import Foundation
import Testing
@testable import CellarData

/// Tier A: the shipped Rockstar profiles, end to end on real files — discovered, planned and read
/// into the library the way the app reads them, as their bottle gains the Rockstar Games Launcher.
///
/// The unit suite proves each piece (the field, the installer, the copy). This proves they hold
/// together for the profiles that actually ship: a Red Dead Redemption 2 the player hasn't
/// installed yet says the launcher's installer will open a window, and once `Launcher.exe` is in the
/// bottle the library stops asking for it. No Wine: whether Rockstar's installer and its sign-in
/// window run under a real runner is tier B and up, on a Mac (`docs/TESTING.md`).
@Suite(.serialized)
struct RockstarLauncherIntegrationTests {

    static let rockstarGames = ["red-dead-redemption", "red-dead-redemption-2", "grand-theft-auto-v"]

    @Test("Every shipped Rockstar game plans through Steam with the Rockstar launcher, and is listed",
          arguments: RockstarLauncherIntegrationTests.rockstarGames)
    func shippedProfilesNameTheLauncher(_ slug: String) throws {
        #expect(IT.shippedProfilesStaged)
        let plan = try Game.plan(slug: slug)
        #expect(plan.store == .steam)
        #expect(plan.publisherLauncher == .rockstar)
        #expect(plan.startExe != nil && plan.startExe != plan.launchExe)
        #expect(Game.summaries().contains { $0.slug == slug && $0.publisherLauncher == .rockstar })
    }

    @Test("Red Dead Redemption 2's page asks for the launcher until it is in the bottle, then stops")
    func libraryFollowsTheBottle() throws {
        #expect(IT.shippedProfilesStaged)
        let plan = try Game.plan(slug: "red-dead-redemption-2")
        let launcher = RockstarLauncher.executable(in: plan.prefix)
        defer { try? FileManager.default.removeItem(at: plan.prefix) }
        try? FileManager.default.removeItem(at: plan.prefix)

        let before = try #require(Game.summaries().first { $0.slug == plan.slug })
        #expect(before.launcherSetupPending)
        #expect(before.nextStep == .install, "one button installs everything, the launcher included")
        #expect(before.actionHint.contains("Rockstar Games Launcher"))
        #expect(before.actionHint.contains("opens a window"))

        try FileManager.default.createDirectory(at: launcher.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data([0x4D, 0x5A]).write(to: launcher)
        #expect(PublisherLauncher.rockstar.isInstalled(in: plan.prefix))

        let after = try #require(Game.summaries().first { $0.slug == plan.slug })
        #expect(after.publisherLauncherInstalled)
        #expect(!after.launcherSetupPending)
        #expect(!after.actionHint.contains("opens a window"), "nothing left to install, so no installer window is promised")
    }
}
