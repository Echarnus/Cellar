import Foundation
import Testing
import CellarDomain
@testable import CellarData

/// Skyrim didn't fill the screen (#310): it started in a 1518×962 window with a title bar, because
/// the preset Cellar copies as its first-run `SkyrimPrefs.ini` says windowed. The full screen or
/// window choice is now written into `[Display]` of the game's own settings file before each start.
@Suite(.serialized)
struct DisplayIniTests {

    static let screen = (width: 1512, height: 982)

    // MARK: - The values

    @Test("Full screen is a borderless window the size of the display")
    func fullScreenValues() throws {
        let values = try #require(DisplayIni.values(for: .fullScreen, screen: Self.screen))
        #expect(values.map(\.0) == ["bFull Screen", "bBorderless", "iSize W", "iSize H"])
        #expect(values.map(\.1) == ["0", "1", "1512", "982"])
    }

    @Test("Window is a bordered window at three quarters of the display, in even numbers")
    func windowValues() throws {
        let values = try #require(DisplayIni.values(for: .window, screen: Self.screen))
        #expect(values.map(\.1) == ["0", "0", "1134", "736"])
    }

    @Test("Game's Choice writes nothing")
    func gameWritesNothing() {
        #expect(DisplayIni.values(for: .game, screen: Self.screen) == nil)
    }

    // MARK: - The file

    @Test("Existing keys are replaced in place, case-insensitively, and the rest is left alone")
    func replacesInPlace() {
        let text = "[General]\r\nsLanguage=ENGLISH\r\n\r\n[Display]\r\nbfull screen=1\r\niSize W=1280\r\niSize H=720\r\nfGamma=1.0\r\n\r\n[Audio]\r\nfVolume=1\r\n"
        let out = DisplayIni.rewrite(text, section: "Display",
                                     values: [("bFull Screen", "0"), ("bBorderless", "1"), ("iSize W", "1512"), ("iSize H", "982")])
        #expect(out == "[General]\r\nsLanguage=ENGLISH\r\n\r\n[Display]\r\nbFull Screen=0\r\niSize W=1512\r\niSize H=982\r\nfGamma=1.0\r\nbBorderless=1\r\n\r\n[Audio]\r\nfVolume=1\r\n")
    }

    @Test("A file without a [Display] section gets one at the end")
    func addsTheSection() {
        let out = DisplayIni.rewrite("[General]\nsLanguage=ENGLISH\n", section: "Display", values: [("bBorderless", "1")])
        #expect(out == "[General]\nsLanguage=ENGLISH\n\n[Display]\nbBorderless=1\n")
    }

    @Test("Writing the same values twice changes nothing the second time")
    func idempotent() {
        let once = DisplayIni.rewrite("[Display]\nbFull Screen=1\n", section: "Display", values: [("bFull Screen", "0")])
        #expect(DisplayIni.rewrite(once, section: "Display", values: [("bFull Screen", "0")]) == once)
    }

    @Test("Only a path inside the Windows user folder is taken from a profile",
          arguments: ["/etc/x.ini", "../x.ini", "Documents/../../x.ini", "", "  "])
    func refusesPaths(_ value: String) {
        #expect(DisplayIni.parse(value) == nil)
    }

    // MARK: - Skyrim, end to end

    private func shippedSkyrim() throws -> GamePlan {
        TestHome.ensure()
        let file = try #require(try Repo.profileFiles().first { $0.lastPathComponent == "skyrim-special-edition.toml" })
        return try Game.plan(slug: TestHome.writeProfile(try String(contentsOf: file, encoding: .utf8), slug: "skyrim-display"))
    }

    @Test("Skyrim's profile names SkyrimPrefs.ini, starts full screen, and offers the choice")
    func skyrimProfile() throws {
        let plan = try shippedSkyrim()
        #expect(plan.displayIni == "Documents/My Games/Skyrim Special Edition/SkyrimPrefs.ini")
        #expect(plan.performance.displayMode == .fullScreen)
        #expect(plan.canChooseDisplayMode)
        #expect(plan.displayArguments == [], "the choice goes into the file, not the command line")
    }

    @Test("Before Skyrim starts, its windowed SkyrimPrefs.ini is turned into a full-screen one")
    func skyrimFileIsFixed() throws {
        let plan = try shippedSkyrim()
        defer { try? FileManager.default.removeItem(at: plan.prefix) }
        let url = FirstRunFiles.userFolder(of: plan).appendingPathComponent(try #require(plan.displayIni))
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        // What the High preset left on Kenneth's Mac: windowed, at a size of its own.
        try "[Display]\r\nbFull Screen=0\r\niSize W=1518\r\niSize H=962\r\n".write(to: url, atomically: true, encoding: .utf8)

        DisplayIni.apply(plan, screen: Self.screen)

        let text = try String(contentsOf: url, encoding: .utf8)
        #expect(text.contains("bFull Screen=0\r\n"))
        #expect(text.contains("bBorderless=1\r\n"))
        #expect(text.contains("iSize W=1512\r\n"))
        #expect(text.contains("iSize H=982\r\n"))
    }

    @Test("A settings file the game hasn't written yet is not created")
    func noFileNoWrite() throws {
        let plan = try shippedSkyrim()
        defer { try? FileManager.default.removeItem(at: plan.prefix) }
        let url = FirstRunFiles.userFolder(of: plan).appendingPathComponent(try #require(plan.displayIni))
        DisplayIni.apply(plan, screen: Self.screen)
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    // MARK: - The frame-rate overlay

    /// Skyrim showed Metal's performance overlay to the player (#310): its profile, and three
    /// others, still had `MTL_HUD_ENABLED = "1"` from testing. The overlay is the player's choice
    /// (Show frame rate), never a profile's.
    @Test("No shipped profile turns the frame-rate overlay on")
    func noProfileShowsTheOverlay() throws {
        let on = try NSRegularExpression(pattern: #"(?mi)^\s*(MTL_HUD_ENABLED\s*=\s*"?1|metal_hud\s*=\s*"?(true|on|yes|1))"#)
        for file in try Repo.profileFiles() {
            let text = try String(contentsOf: file, encoding: .utf8)
            let found = on.firstMatch(in: text, range: NSRange(text.startIndex..., in: text))
            #expect(found == nil, "\(file.lastPathComponent) turns the frame-rate overlay on for every player")
        }
    }
}
