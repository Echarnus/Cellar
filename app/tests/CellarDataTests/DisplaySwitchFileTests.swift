import Foundation
import Testing
import CellarDomain
@testable import CellarData

/// GTA's full screen or window choice (#308): written into the game's own `commandline.txt`, because
/// the Rockstar launcher drops whatever is on the stub's command line.
@Suite(.serialized)
struct DisplaySwitchFileTests {

    static let rage: Set<String> = ["-fullscreen", "-windowed"]

    // MARK: - The file's text

    @Test("A choice with no file yet writes just that switch")
    func newFile() {
        #expect(DisplaySwitchFile.rewrite(nil, owned: Self.rage, chosen: ["-windowed"]) == "-windowed\r\n")
    }

    @Test("Game's Choice with no file creates nothing")
    func nothingToWrite() {
        #expect(DisplaySwitchFile.rewrite(nil, owned: Self.rage, chosen: []) == nil)
    }

    @Test("The player's own switches stay; only the display switch is replaced")
    func keepsOtherLines() {
        let existing = "-noBlockOnLostFocus\r\n-fullscreen\r\n-width 1920\r\n"
        #expect(DisplaySwitchFile.rewrite(existing, owned: Self.rage, chosen: ["-windowed"])
                == "-noBlockOnLostFocus\r\n-width 1920\r\n-windowed\r\n")
    }

    @Test("Several switches on one line: only the display one is taken out, in any case")
    func sharedLine() {
        let existing = "-norestrictions -WINDOWED -nomemrestrict\n"
        #expect(DisplaySwitchFile.rewrite(existing, owned: Self.rage, chosen: [])
                == "-norestrictions -nomemrestrict\r\n")
    }

    @Test("Going back to Game's Choice takes Cellar's switch out again")
    func backToGame() {
        let written = DisplaySwitchFile.rewrite(nil, owned: Self.rage, chosen: ["-fullscreen"])
        #expect(DisplaySwitchFile.rewrite(written, owned: Self.rage, chosen: []) == "")
    }

    @Test("Writing the same choice twice changes nothing the second time")
    func idempotent() {
        let once = DisplaySwitchFile.rewrite("-noBlockOnLostFocus\n", owned: Self.rage, chosen: ["-windowed"])
        #expect(DisplaySwitchFile.rewrite(once, owned: Self.rage, chosen: ["-windowed"]) == once)
    }

    @Test("Only a plain file name is taken from a profile: nothing that leaves the game's folder",
          arguments: ["../commandline.txt", "sub/commandline.txt", #"..\x.txt"#, "..", "", "  "])
    func refusesPaths(_ value: String) {
        #expect(DisplaySwitchFile.parse(value) == nil)
    }

    // MARK: - Which games get it

    private func plan(extra: String) throws -> GamePlan {
        try TestHome.plan("""
        [game]
        name   = "GTA Fixture"
        engine = "RAGE"
        store  = "steam"

        [install]
        steam_appid        = "271590"
        exe                = "GTA5.exe"
        start_exe          = "PlayGTAV.exe"
        publisher_launcher = "rockstar"
        \(extra)

        [performance]
        display_mode = "window"
        """, slug: "gta-display")
    }

    @Test("A Rockstar-launcher game with a switch file is offered the choice, and passes nothing on the command line")
    func launcherGameWithFile() throws {
        let plan = try plan(extra: #"display_switch_file = "commandline.txt""#)
        #expect(plan.canChooseDisplayMode)
        #expect(plan.displayArguments == [], "the launcher would drop it: the file carries it instead")
    }

    @Test("The same game without one is not: there is no way to reach it")
    func launcherGameWithoutFile() throws {
        let plan = try plan(extra: "")
        #expect(!plan.canChooseDisplayMode)
    }

    @Test("Before a launch, the file beside the exe gets the choice and keeps the player's lines")
    func appliedBesideTheExe() throws {
        let plan = try plan(extra: #"display_switch_file = "commandline.txt""#)
        try TestHome.installFakeGame(into: plan, at: "GTA5.exe")
        defer { try? FileManager.default.removeItem(at: plan.prefix) }
        let url = try #require(DisplaySwitchFile.url(for: plan))
        #expect(url.deletingLastPathComponent() == plan.directLaunchExe?.deletingLastPathComponent())
        try "-noBlockOnLostFocus\r\n-fullscreen\r\n".write(to: url, atomically: true, encoding: .utf8)

        DisplaySwitchFile.apply(plan)

        #expect(try String(contentsOf: url, encoding: .utf8) == "-noBlockOnLostFocus\r\n-windowed\r\n")
    }

    /// A shipped profile, copied into the test sandbox and resolved as Cellar would.
    private func shipped(_ slug: String) throws -> GamePlan {
        TestHome.ensure()
        let file = try #require(try Repo.profileFiles().first { $0.lastPathComponent == "\(slug).toml" })
        return try Game.plan(slug: TestHome.writeProfile(try String(contentsOf: file, encoding: .utf8), slug: slug))
    }

    @Test("The shipped GTA IV and GTA V profiles name commandline.txt; the GTAs that can't take it don't",
          arguments: ["grand-theft-auto-iv", "grand-theft-auto-v", "grand-theft-auto-v-enhanced"])
    func shippedRockstarGames(_ slug: String) throws {
        let plan = try shipped(slug)
        #expect(plan.displaySwitchFile == "commandline.txt")
        #expect(plan.canChooseDisplayMode, "\(slug) should offer full screen or window")
    }

    @Test("The original trilogy and the Definitive Editions are not offered a choice they can't keep",
          arguments: ["grand-theft-auto-iii", "grand-theft-auto-vice-city", "grand-theft-auto-san-andreas",
                      "grand-theft-auto-iii-definitive-edition",
                      "grand-theft-auto-vice-city-definitive-edition",
                      "grand-theft-auto-san-andreas-definitive-edition"])
    func gtasWithoutAWay(_ slug: String) throws {
        #expect(try !shipped(slug).canChooseDisplayMode)
    }
}
