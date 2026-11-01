import CellarDomain
import Foundation
import Testing
@testable import CellarData

/// The running game should be called by its own name, not "wine". The shim does the renaming inside
/// the process; what can be checked here is that Cellar asks it to rename the right process, and
/// only that one.
@Suite(.serialized)
struct DockShimTests {
    let library = URL(fileURLWithPath: "/tmp/cellar-dock-shim.dylib")

    @Test("The game is named after its profile, and only its own exe is renamed")
    func namesTheGamesExe() {
        let env = DockShim.environment(naming: "Planet Coaster 2", executables: ["PlanetCoaster2.exe"],
                                       library: library)
        #expect(env["DYLD_INSERT_LIBRARIES"] == library.path)
        #expect(env["CELLAR_APP_NAME"] == "Planet Coaster 2")
        #expect(env["CELLAR_APP_EXE"] == "PlanetCoaster2.exe")
        #expect(env["CELLAR_APP_SKIP"] == nil)
    }

    @Test("Without a known exe, every store client is kept from wearing the game's name")
    func skipsStoreClientsWhenExeUnknown() throws {
        let env = DockShim.environment(naming: "Grand Theft Auto V", executables: [], library: library)
        #expect(env["CELLAR_APP_EXE"] == nil)
        let skipped = Set(try #require(env["CELLAR_APP_SKIP"]).split(separator: ",").map(String.init))
        for store in GameStore.allCases {
            for client in store.descriptor.clientProcessNames {
                #expect(skipped.contains(client), "\(client) could be labelled as the game")
            }
        }
    }

    @Test("No shim, no name: the launch goes ahead exactly as before")
    func nothingWithoutTheShim() {
        #expect(DockShim.environment(naming: "Planet Coaster 2", executables: ["PlanetCoaster2.exe"],
                                     library: nil).isEmpty)
        #expect(DockShim.environment(naming: "", executables: [], library: library).isEmpty)
    }

    @Test("A launch carries the game's name and exe; the profile's own variables still win")
    func launchEnvNamesTheGame() throws {
        let shim = TestHome.scratch("dock-shim").appendingPathComponent("cellar-dock-shim.dylib")
        try Data().write(to: shim)
        setenv("CELLAR_DOCK_SHIM", shim.path, 1)
        defer { unsetenv("CELLAR_DOCK_SHIM") }

        let plan = try TestHome.plan("""
        [game]
        name  = "Planet Coaster 2"
        store = "steam"

        [install]
        steam_appid = "2688950"

        [launch]
        exe = "bin/PlanetCoaster2.exe"

        [env]
        MTL_HUD_ENABLED = "1"
        """, slug: "named")

        let env = plan.launchEnv
        #expect(env["CELLAR_APP_NAME"] == "Planet Coaster 2")
        #expect(env["CELLAR_APP_EXE"] == "PlanetCoaster2.exe", "matched by file name, as Wine's argv carries it")
        #expect(env["DYLD_INSERT_LIBRARIES"] == shim.path)
        for (key, value) in plan.env { #expect(env[key] == value) }
        // Opening the client on its own is not this game, so the plain environment stays unnamed.
        #expect(plan.env["CELLAR_APP_NAME"] == nil)
    }

    @Test("Steam started so a game can run beside it stays out of the Dock")
    func clientStartedForAGameIsHidden() throws {
        let shim = TestHome.scratch("dock-shim-client").appendingPathComponent("cellar-dock-shim.dylib")
        try Data().write(to: shim)
        setenv("CELLAR_DOCK_SHIM", shim.path, 1)
        defer { unsetenv("CELLAR_DOCK_SHIM") }

        let game = SteamBottle.gameClientStart
        #expect(game.dock == .hidden, "a client started for a game must not take a Dock icon")
        #expect(game.extraArgs == ["-silent"], "and must not open its window either")

        let runner = WineRunner(binary: URL(fileURLWithPath: "/nonexistent/wine"),
                                prefix: TestHome.scratch("dock-shim-bottle"))
        let start = SteamBottle.clientStart(runner: runner, extraArgs: game.extraArgs, showHUD: false,
                                            gameEnv: ["CELLAR_APP_NAME": "Planet Coaster 2"], dock: game.dock)
        #expect(start.arguments.last == "-silent")
        #expect(start.environment["DYLD_INSERT_LIBRARIES"] == shim.path)
        let hidden = Set((start.environment["CELLAR_DOCK_HIDE"] ?? "").split(separator: ",").map(String.init))
        for client in GameStore.steam.descriptor.clientProcessNames {
            #expect(hidden.contains(client), "\(client) would take a Dock icon while the game plays")
        }
        #expect(start.environment["CELLAR_APP_NAME"] == "Planet Coaster 2",
                "the game's name still travels with the client, for the game it starts")

        // Opening Steam on its own, to sign in, is the one time it belongs in the Dock.
        let opened = SteamBottle.clientStart(runner: runner, extraArgs: [], showHUD: false, gameEnv: [:],
                                             dock: .visible)
        #expect(opened.environment["CELLAR_DOCK_HIDE"] == nil)
    }
}
