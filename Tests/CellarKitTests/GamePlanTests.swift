import Foundation
import Testing
@testable import CellarKit

/// `GamePlan` is the resolved answer to "what do we actually run, and where does it live?".
/// Everything downstream — setup, install, launch, the supervised retry, shutdown — reads it.
@Suite(.serialized)
struct GamePlanTests {

    // MARK: - Field resolution

    @Test("A full profile resolves into the plan the launcher acts on")
    func resolvesFullProfile() throws {
        let plan = try TestHome.plan("""
        [game]
        name          = "Age of Empires II: DE"
        store         = "steam"
        developer     = "Forgotten Empires"
        released      = "2019-11-14"
        engine        = "Genie"
        graphics_api  = "DirectX 11"

        [compatibility]
        anticheat = "none"
        drm       = "Steam"
        online    = "multiplayer"
        status    = "playable"
        notes     = "Tested on an M5."

        [runner]
        id = "sikarugir"

        [graphics]
        backend = "dxvk"

        [install]
        steam_appid = "813780"
        install_dir = "AoE2DE"

        [launch]
        exe = "AoE2DE_s.exe"

        [env]
        MTL_HUD_ENABLED = "1"
        """, slug: "aoe2")

        #expect(plan.name == "Age of Empires II: DE")
        #expect(plan.store == .steam)
        #expect(plan.appID == 813_780)
        #expect(plan.runnerID == "sikarugir")
        #expect(plan.backend == "dxvk")
        #expect(plan.graphicsBackend == .dxvk)
        #expect(plan.launchExe == "AoE2DE_s.exe")
        #expect(plan.installDir == "AoE2DE")
        #expect(plan.env == ["MTL_HUD_ENABLED": "1"])
        #expect(plan.facts.status == "playable")
        #expect(plan.facts.engine == "Genie")
        #expect(plan.facts.notes == "Tested on an M5.")
    }

    @Test("Omitted fields fall back to documented defaults")
    func defaults() throws {
        let slug = TestHome.writeProfile("[game]\nstore = \"steam\"", slug: "bare")
        let plan = try Game.plan(slug: slug)
        #expect(plan.name == slug, "a profile with no name is shown by its slug, never blank")
        #expect(plan.bottleName == slug, "one bottle per game unless a profile opts into sharing")
        #expect(plan.runnerID == RunnerCatalog.defaultID)
        #expect(plan.backend == "d3dmetal")
        #expect(plan.appID == nil)
        #expect(plan.launchExe == nil)
    }

    @Test("An unknown backend falls back to D3DMetal rather than failing to launch")
    func unknownBackendFallsBack() throws {
        let plan = try TestHome.plan("""
        [graphics]
        backend = "not-a-backend"
        """)
        #expect(plan.backend == "not-a-backend", "the profile's word is preserved for display")
        #expect(plan.graphicsBackend == .d3dmetal, "but the runner gets a backend that exists")
    }

    @Test("Several games can share one bottle")
    func sharedBottle() throws {
        let plan = try TestHome.plan("""
        [game]
        bottle = "shared-steam"
        """)
        #expect(plan.bottleName == "shared-steam")
        #expect(plan.prefix.lastPathComponent == "shared-steam")
    }

    // MARK: - needs_live_session

    @Test("A game needs its store at runtime unless the profile explicitly says otherwise")
    func liveSessionDefaultsToTrue() throws {
        let plan = try TestHome.plan("[game]\nstore = \"steam\"")
        #expect(plan.needsLiveSession, "defaulting to 'needs the client' is the DRM-safe direction")
    }

    @Test("needs_live_session = false opts a DRM-free game out of the client",
          arguments: ["needs_live_session", "needs_live_steam"])
    func liveSessionOptOut(_ key: String) throws {
        let plan = try TestHome.plan("""
        [compatibility]
        \(key) = false
        """)
        #expect(plan.needsLiveSession == false, "\(key) must be honoured — it is the original spelling")
    }

    @Test("Anything that is not literally false still needs the store", arguments: ["true", "yes", "maybe", "0"])
    func liveSessionIsConservative(_ value: String) throws {
        let plan = try TestHome.plan("""
        [compatibility]
        needs_live_session = \(value)
        """)
        #expect(plan.needsLiveSession, "an ambiguous value must not silently drop the DRM client")
    }

    // MARK: - Install roots and the direct-launch exe

    @Test("Install roots are searched depot-first, then the store's own locations")
    func installRootOrder() throws {
        let plan = try TestHome.plan("""
        [install]
        install_dir = "Diablo IV"
        """, slug: "d4")

        let roots = plan.installRoots.map(\.path)
        #expect(roots.first == plan.depotGameDir.path,
                "files Cellar downloaded itself are the most trustworthy answer")
        #expect(roots.contains { $0.hasSuffix("drive_c/Program Files (x86)/Diablo IV") })
        #expect(roots.contains { $0.hasSuffix("drive_c/Program Files/Diablo IV") })
        #expect(roots.contains { $0.hasSuffix("drive_c/Games/Diablo IV") })
        #expect(roots.last!.hasSuffix("drive_c/Program Files (x86)/Steam/steamapps/common"))
    }

    @Test("With no install_dir only the depot dir and the Steam library are searched")
    func installRootsWithoutInstallDir() throws {
        let plan = try TestHome.plan("[game]\nname = \"X\"", slug: "noinstalldir")
        #expect(plan.installRoots.count == 2)
    }

    @Test("directLaunchExe is nil until the file is actually on disk")
    func directLaunchExeRequiresTheFile() throws {
        let plan = try TestHome.plan("""
        [compatibility]
        needs_live_session = false
        [launch]
        exe = "Game.exe"
        """, slug: "direct")

        #expect(plan.directLaunchExe == nil)
        #expect(plan.canLaunchStoreFree == false, "never promise a store-free launch we can't perform")

        try TestHome.installFakeGame(into: plan, at: "Game.exe")
        #expect(plan.directLaunchExe?.lastPathComponent == "Game.exe")
        #expect(plan.canLaunchStoreFree)
    }

    @Test("A nested exe path resolves under the install root")
    func nestedExePath() throws {
        let plan = try TestHome.plan("""
        [compatibility]
        needs_live_session = false
        [launch]
        exe = "bin/x64/witcher3.exe"
        """, slug: "nested")
        try TestHome.installFakeGame(into: plan, at: "bin/x64/witcher3.exe")
        #expect(plan.directLaunchExe?.path.hasSuffix("bin/x64/witcher3.exe") == true)
    }

    @Test("A live-session game never takes the store-free shortcut, even with its exe present")
    func drmGameKeepsTheClient() throws {
        let plan = try TestHome.plan("""
        [compatibility]
        needs_live_session = true
        [launch]
        exe = "Game.exe"
        """, slug: "drm")
        try TestHome.installFakeGame(into: plan, at: "Game.exe")

        #expect(plan.directLaunchExe != nil, "the file is there…")
        #expect(plan.canLaunchStoreFree == false, "…but Denuvo/Steamworks still needs the client up")
    }

    @Test("An exe with no needs_live_session opt-out defaults to needing the client")
    func exeAloneIsNotEnough() throws {
        let plan = try TestHome.plan("[launch]\nexe = \"Game.exe\"", slug: "exeonly")
        try TestHome.installFakeGame(into: plan, at: "Game.exe")
        #expect(plan.canLaunchStoreFree == false)
    }

    // MARK: - Process needles

    @Test("Needles identify the game, not the store client that spawned it")
    func processNeedles() throws {
        let plan = try TestHome.plan("""
        [install]
        install_dir = "Diablo IV"
        [launch]
        exe = "Diablo IV Launcher.exe"
        """, slug: "needles")

        let needles = plan.gameProcessNeedles
        #expect(needles.contains("Diablo IV Launcher.exe"))
        #expect(needles.contains(#"\Diablo IV\"#), "Wine reports Windows command lines…")
        #expect(needles.contains("/Diablo IV/"), "…but the POSIX form shows up too")
        #expect(needles.allSatisfy { !$0.lowercased().contains("battle.net") })
    }

    @Test("A nested exe contributes only its last path component as a needle")
    func needleUsesExeBasename() throws {
        let plan = try TestHome.plan("[launch]\nexe = \"bin/x64/witcher3.exe\"", slug: "needlebase")
        #expect(plan.gameProcessNeedles.contains("witcher3.exe"))
        #expect(plan.gameProcessNeedles.contains { $0.contains("bin/x64") } == false)
    }

    @Test("A profile with neither exe nor install_dir yields no needles at all")
    func noNeedles() throws {
        let plan = try TestHome.plan("[game]\nname = \"X\"", slug: "noneedles")
        #expect(plan.gameProcessNeedles.isEmpty,
                "Game.launch checks for this and refuses rather than watching the wrong process")
    }

    // MARK: - Paths

    @Test("A bottle and its depot directory hang off the sandboxed Cellar home")
    func pathsAreSandboxed() throws {
        let plan = try TestHome.plan("[game]\nname = \"X\"", slug: "paths")
        #expect(plan.prefix.path.hasPrefix(Paths.prefixes.path))
        #expect(plan.depotGameDir.path.hasSuffix("drive_c/Games/\(plan.slug)"))
        #expect(Paths.appSupport.path.hasPrefix(TestHome.root.path),
                "the whole point of CELLAR_HOME: a test must never write to the player's library")
    }
}
