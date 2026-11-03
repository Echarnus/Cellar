import Foundation
import Testing
import CellarDomain
@testable import CellarData

/// Full screen or a window (#306): the `display_mode` switch, the engine switches it becomes, which
/// games are offered the choice, and that the switch really reaches the game's command line.
@Suite(.serialized)
struct DisplayModeTests {

    // MARK: - The engine's own switch

    @Test("Each engine family gets its maker's documented start-up switch",
          arguments: [
            ("Unreal Engine 4", DisplayMode.fullScreen, ["-fullscreen"]),
            ("Unreal Engine 5", DisplayMode.window, ["-windowed"]),
            ("Unity", DisplayMode.fullScreen, ["-screen-fullscreen", "1"]),
            ("Unity (HDRP)", DisplayMode.window, ["-screen-fullscreen", "0"]),
            ("Source", DisplayMode.window, ["-windowed"]),
            ("Source 2", DisplayMode.fullScreen, ["-fullscreen"]),
            ("RAGE", DisplayMode.window, ["-windowed"]),
            ("RAGE", DisplayMode.fullScreen, ["-fullscreen"]),
          ])
    func engineSwitches(_ engine: String, _ mode: DisplayMode, _ expected: [String]) {
        #expect(mode.arguments(engine: engine) == expected)
    }

    @Test("Letting the game decide passes nothing, on every engine Cellar knows")
    func gameDecidesPassesNothing() {
        for engine in ["Unreal Engine 5", "Unity", "Source 2"] {
            #expect(DisplayMode.game.arguments(engine: engine) == [])
        }
    }

    @Test("An engine with no known switch is never offered the choice",
          arguments: ["COBRA", "Creation Engine", "REDengine 3", "not published", "Sourcery", ""])
    func unknownEnginesAreNotChoosable(_ engine: String) {
        #expect(!DisplayMode.isChoosable(engine: engine))
        #expect(DisplayMode.window.arguments(engine: engine) == nil)
    }

    @Test("A profile without an engine is not choosable either")
    func noEngine() {
        #expect(!DisplayMode.isChoosable(engine: nil))
    }

    // MARK: - The setting

    @Test("display_mode accepts the usual spellings and stores one canonical value",
          arguments: [("game", "game"), ("Default", "game"), ("fullscreen", "fullscreen"),
                      ("Full-Screen", "fullscreen"), ("window", "window"), ("WINDOWED", "window")])
    func normalises(_ given: String, _ stored: String) throws {
        #expect(try PerformanceSetting.displayMode.normalise(given) == stored)
    }

    @Test("display_mode refuses anything else, and says what it takes",
          arguments: ["on", "true", "borderless", ""])
    func refuses(_ given: String) {
        #expect(throws: CellarError.self) { try PerformanceSetting.displayMode.normalise(given) }
    }

    @Test("Untouched, a game decides for itself; the bottle's choice wins over the profile's")
    func layers() {
        let untouched = PerformanceSettings.resolve(profileFields: [:], profileEnv: [:], bottleFields: [:], bottleEnv: [:])
        #expect(untouched.displayMode == .game)
        let chosen = PerformanceSettings.resolve(profileFields: ["display_mode": "fullscreen"], profileEnv: [:],
                                                 bottleFields: ["display_mode": "window"], bottleEnv: [:])
        #expect(chosen.displayMode == .window)
        #expect(chosen.env["WINEDEBUG"] == "-all", "a display choice adds nothing to the environment")
        #expect(chosen.env.count == untouched.env.count)
    }

    @Test("display_mode is not one of the every-game settings: a game's own page owns it")
    func notEveryGame() {
        #expect(!CellarSettings.everyGameSettings.contains(.displayMode))
        #expect(!PerformanceSetting.displayMode.isBool)
        #expect(!PerformanceSetting.displayMode.isCrashWorkaround)
    }

    // MARK: - Which games are offered it

    private func plan(engine: String, extra: String = "", store: String = "steam") throws -> GamePlan {
        try TestHome.plan("""
        [game]
        name   = "Display Fixture"
        engine = "\(engine)"
        store  = "\(store)"
        \(extra)

        [install]
        steam_appid = "480"

        [launch]
        exe = "Fixture.exe"

        [performance]
        display_mode = "window"
        """, slug: "display-fixture")
    }

    @Test("An Unreal game on Steam is offered the choice, and its window choice becomes -windowed")
    func unrealOnSteam() throws {
        let plan = try plan(engine: "Unreal Engine 5")
        #expect(plan.canChooseDisplayMode)
        #expect(plan.displayArguments == ["-windowed"])
    }

    @Test("A game started through a publisher launcher is not: the launcher drops the arguments")
    func publisherLauncherDropsIt() throws {
        let plan = try plan(engine: "Unreal Engine 4", extra: #"publisher_launcher = "rockstar""#)
        #expect(!plan.canChooseDisplayMode)
        #expect(plan.displayArguments == [])
    }

    @Test("A game on an engine with no switch passes nothing, whatever was chosen")
    func unknownEnginePassesNothing() throws {
        let plan = try plan(engine: "COBRA")
        #expect(!plan.canChooseDisplayMode)
        #expect(plan.displayArguments == [])
    }

    // MARK: - It reaches the game

    @Test("A direct launch hands Wine the exe followed by the engine's switch")
    func directLaunchPassesTheSwitch() throws {
        let install = try FakeWine.install()
        let exeName = "CellarDisplay-\(UUID().uuidString.prefix(8)).exe"
        let plan = try TestHome.plan("""
        [game]
        name   = "Display Launch Fixture"
        store  = "steam"
        engine = "Unity"

        [compatibility]
        needs_live_session = false
        status             = "untested"

        [runner]
        id = "\(install.spec.id)"

        [install]
        steam_appid = "480"

        [launch]
        exe = "\(exeName)"

        [performance]
        display_mode = "window"
        """, slug: "display-launch")
        try TestHome.installFakeGame(into: plan, at: exeName)
        let exe = try #require(plan.directLaunchExe)
        try FakeWine.keepAlive(exe, seconds: 3)
        defer {
            ProcessWatch.kill([exeName])
            try? FileManager.default.removeItem(at: plan.prefix)
        }
        FakeWine.reset()

        _ = try Game.launch(plan, checkUpdates: false)

        let call = try #require(FakeWine.calls().last(where: { $0.tool == "wine" && $0.arguments.first == exe.path }),
                                "Wine was never asked to run the game's exe")
        #expect(Array(call.arguments.dropFirst()) == ["-screen-fullscreen", "0"],
                "the player chose a window; Unity is told so on its command line")
    }

    @Test("The route that starts a Steam game beside the client passes the switch too")
    func steamAlongsidePassesTheSwitch() throws {
        // Starting the alongside route needs a signed-in Windows Steam, which no hermetic test has;
        // what can break here is the hand-off, so that is what is checked.
        let source = try String(contentsOf: Repo.source("CellarInfrastructure/Adapters/SteamAdapter.swift"),
                                encoding: .utf8)
        let call = try #require(source.range(of: "SteamBottle.launchAlongside("), "the launch route moved")
        let arguments = source[call.lowerBound...].prefix(1200)
        #expect(arguments.contains("arguments: plan.displayArguments"),
                "a game Cellar starts beside Steam would ignore the player's full screen or window choice")
    }
}
