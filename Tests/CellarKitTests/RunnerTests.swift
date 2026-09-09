import Foundation
import Testing
@testable import CellarKit

/// The runner catalog and the environment a bottle is run with. Getting either wrong is the
/// difference between D3DMetal loading and the game falling back to something unplayable — and
/// neither failure announces itself.
@Suite(.serialized)
struct RunnerTests {

    // MARK: - Catalog

    @Test("Runner ids are unique and the default is one of them")
    func catalogIsConsistent() {
        let ids = RunnerCatalog.all.map(\.id)
        #expect(Set(ids).count == ids.count)
        #expect(ids.contains(RunnerCatalog.defaultID))
        #expect(RunnerCatalog.spec(forID: RunnerCatalog.defaultID) != nil)
        #expect(RunnerCatalog.spec(forID: "not-a-runner") == nil)
    }

    @Test("Every runner is completely described", arguments: RunnerCatalog.all.map(\.id))
    func specsAreComplete(_ id: String) throws {
        let spec = try #require(RunnerCatalog.spec(forID: id))
        #expect(!spec.displayName.isEmpty)
        #expect(!spec.artifacts.isEmpty, "a runner with no artifacts can never install")
        #expect(!spec.license.isEmpty, "the licence is shown to the player — see docs/LEGAL.md")
        #expect(["wine", "wine64"].contains(spec.wineBinaryName))
        for artifact in spec.artifacts {
            #expect(artifact.url.hasPrefix("https://"), "runners are never fetched over plain HTTP")
            #expect(URL(string: artifact.url) != nil)
        }
    }

    @Test("The default runner is not deprecated, and the deprecated ones say why")
    func deprecations() {
        #expect(RunnerCatalog.spec(forID: RunnerCatalog.defaultID)?.deprecated == nil,
                "Cellar must not default to a runner it is warning people off")
        for spec in RunnerCatalog.all where spec.deprecated != nil {
            #expect(spec.deprecated?.isEmpty == false)
            #expect(spec.deprecated?.contains("prefer") == true || spec.deprecated?.contains("use") == true,
                    "a deprecation must name the replacement: \(spec.id)")
        }
    }

    @Test("D3DMetal is grafted at runtime, never bundled", arguments: RunnerCatalog.all.map(\.id))
    func d3dMetalIsNeverShipped(_ id: String) throws {
        // Hard project rule: Apple's D3DMetal may not appear in Cellar's source or release
        // artifacts. It only ever arrives by URL, from a community runner, at install time.
        let spec = try #require(RunnerCatalog.spec(forID: id))
        for artifact in spec.artifacts where artifact.kind == .d3dmetalFromTemplate {
            #expect(artifact.url.hasPrefix("https://github.com/"),
                    "D3DMetal must be fetched from the community template, not carried by Cellar")
        }
        let carriers: [RunnerArtifact.Kind] = [.d3dmetalFromTemplate, .wrapperFrameworks,
                                               .gptkApp, .wineDMG]
        let couldCarryD3DMetal = spec.artifacts.contains { carriers.contains($0.kind) }
        #expect(spec.hasD3DMetal == couldCarryD3DMetal,
                "'\(id)' claims hasD3DMetal = \(spec.hasD3DMetal) but its artifacts say otherwise")
    }

    // MARK: - Installed-runner layout

    @Test("A runner is only 'installed' once its wine binary is executable")
    func locateWineBinary() throws {
        TestHome.ensure()
        let root = TestHome.scratch("runner-layout")
        let bin = root.appendingPathComponent("wine/bin", isDirectory: true)
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        let binary = bin.appendingPathComponent("wine")

        #expect(RunnerManager.locateWineBinary(in: root, name: "wine") == nil)

        try "#!/bin/sh\n".write(to: binary, atomically: true, encoding: .utf8)
        #expect(RunnerManager.locateWineBinary(in: root, name: "wine") == nil,
                "a non-executable file is not a runnable wine")

        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binary.path)
        #expect(RunnerManager.locateWineBinary(in: root, name: "wine")?.path == binary.path)
    }

    @Test("A GPTK-style nested layout is found too")
    func locateNestedWineBinary() throws {
        TestHome.ensure()
        let root = TestHome.scratch("runner-gptk")
        let bin = root.appendingPathComponent("Game Porting Toolkit.app/Contents/Resources/wine/bin",
                                              isDirectory: true)
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        let binary = bin.appendingPathComponent("wine64")
        try "#!/bin/sh\n".write(to: binary, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binary.path)

        // Resolved on both sides: the nested layout is found by enumerating the directory, and
        // FileManager hands back /private/var where Foundation's own URL normalisation gives /var.
        #expect(RunnerManager.locateWineBinary(in: root, name: "wine64")?
            .resolvingSymlinksInPath().path == binary.resolvingSymlinksInPath().path)
    }

    @Test("An installed runner registers, and a plan resolves a WineRunner from it")
    func runnerResolvesIntoAPlan() throws {
        let install = try #require(TestHome.installStubRunner())
        #expect(install.spec.id == RunnerCatalog.defaultID)
        #expect(install.binDirectory.lastPathComponent == "bin")
        #expect(install.wineRoot.lastPathComponent == "wine")

        let plan = try TestHome.plan("[runner]\nid = \"\(RunnerCatalog.defaultID)\"", slug: "stub")
        #expect(Game.wineRunner(plan) != nil)
        #expect(Game.wineRunner(plan)?.prefix == plan.prefix)
    }

    @Test("A runner with no renderers reports no D3DMetal rather than assuming the catalog is right")
    func layoutDecidesD3DMetal() throws {
        // `RunnerSpec.hasD3DMetal` is a claim about the download; `RunnerInstall.hasD3DMetal` is a
        // fact about what landed on disk. If a graft silently failed, the second must say so — a
        // game that quietly falls back off D3DMetal is a bug report about "bad performance".
        TestHome.ensure()
        let root = TestHome.scratch("runner-empty")
        let bin = root.appendingPathComponent("wine/bin", isDirectory: true)
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        let install = RunnerInstall(spec: RunnerCatalog.wineforge, root: root,
                                    wineBinary: bin.appendingPathComponent("wine"))

        #expect(RunnerCatalog.wineforge.hasD3DMetal, "the catalog says this runner carries it…")
        #expect(install.hasD3DMetal == false, "…but nothing was grafted, and the install must admit it")
        #expect(install.isWineForgeStyle == false)
        #expect(install.frameworks == nil)
        #expect(install.renderer("d3dmetal") == nil)
    }

    @Test("A WineForge-style graft is recognised by the marker D3DMetal actually needs")
    func wineForgeLayoutDetected() throws {
        TestHome.ensure()
        let root = TestHome.scratch("runner-wineforge")
        let external = root.appendingPathComponent("wine/lib/d3dmetal/external", isDirectory: true)
        try FileManager.default.createDirectory(at: external, withIntermediateDirectories: true)
        let install = RunnerInstall(spec: RunnerCatalog.wineforge, root: root,
                                    wineBinary: root.appendingPathComponent("wine/bin/wine"))

        #expect(install.d3dmetalRuntime == nil,
                "an empty d3dmetal directory is not a runtime — the marker dylib decides")

        try Data().write(to: external.appendingPathComponent("libd3dshared.dylib"))
        #expect(install.d3dmetalRuntime != nil)
        #expect(install.isWineForgeStyle)
        #expect(install.hasD3DMetal)
    }

    @Test("An unknown runner is refused at setup with a message naming it")
    func unknownRunnerRefused() throws {
        let plan = try TestHome.plan("[runner]\nid = \"totally-made-up\"", slug: "badrunner")
        #expect(Game.wineRunner(plan) == nil)
        do {
            _ = try Game.setUp(plan) { _ in }
            Issue.record("setup must not proceed with a runner Cellar has never heard of")
        } catch let error as CellarError {
            #expect(error.description.contains("totally-made-up")
                    || error.description.contains("Apple Silicon")
                    || error.description.contains("Rosetta"))
        }
    }

    // MARK: - Wine environment

    @Test("The bottle directory is the WINEPREFIX, and the runner's libraries are on the path")
    func wineEnvironment() throws {
        let install = try #require(TestHome.installStubRunner())
        let prefix = TestHome.scratch("wine-env")
        let wine = WineRunner(install: install, prefix: prefix, backend: .d3dmetal)

        let env = wine.environment()
        #expect(env["WINEPREFIX"] == prefix.path)
        #expect(env["WINEDEBUG"] == "-all")
        #expect(env["DYLD_FALLBACK_LIBRARY_PATH"]?.contains(install.wineRoot.path) == true,
                "wineserver needs the runner's own dylibs or it will not start")
        #expect(env["PATH"]?.hasPrefix(install.binDirectory.path) == true,
                "the runner's own bin must come first, ahead of any other Wine on the machine")
    }

    @Test("A stray Wine variable in the caller's shell cannot leak into a bottle",
          arguments: ["WINEPREFIX", "WINEDLLPATH", "DYLD_FALLBACK_LIBRARY_PATH",
                      "MTL_HUD_ENABLED", "GRAPHICS_BACKEND", "D3DMETAL_RUNTIME_DIR", "GST_PLUGIN_PATH"])
    func scrubsInheritedWineVariables(_ key: String) throws {
        // Cellar inherits the caller's environment on purpose (a bare one makes Planet Coaster 2
        // exit silently), which makes scrubbing the graphics/Wine variables load-bearing: a shell
        // that once exported another runner's paths would otherwise break every bottle.
        let install = try #require(TestHome.installStubRunner())
        setenv(key, "/somewhere/from/another/runner", 1)
        defer { unsetenv(key) }

        let env = WineRunner(install: install, prefix: TestHome.scratch("wine-scrub")).environment()
        #expect(env[key] != "/somewhere/from/another/runner",
                "\(key) leaked from the caller's shell into the bottle")
    }

    @Test("Steam's overlay is always disabled — it crashes every game under Wine")
    func overlayAlwaysDisabled() throws {
        let install = try #require(TestHome.installStubRunner())
        let wine = WineRunner(install: install, prefix: TestHome.scratch("wine-overlay"))
        #expect(wine.environment()["WINEDLLOVERRIDES"]?.contains("gameoverlayrenderer64=d") == true)
    }

    @Test("A profile's WINEDLLOVERRIDES is merged with the backend's, not substituted for it")
    func dllOverridesMerge() throws {
        // A profile that needs one native DLL must not silently disable the overlay fix or the
        // backend's own override list along with it.
        let install = try #require(TestHome.installStubRunner())
        let wine = WineRunner(install: install, prefix: TestHome.scratch("wine-merge"))
        let env = wine.environment(extra: ["WINEDLLOVERRIDES": "xaudio2_7=n,b"])
        let overrides = try #require(env["WINEDLLOVERRIDES"])
        #expect(overrides.contains("xaudio2_7=n,b"), "the profile's override must be applied")
        #expect(overrides.contains("gameoverlayrenderer64=d"), "and Cellar's must survive it")
    }

    @Test("Extra environment overrides the defaults, which is how a profile's [env] reaches the game")
    func extraEnvironmentWins() throws {
        let install = try #require(TestHome.installStubRunner())
        let wine = WineRunner(install: install, prefix: TestHome.scratch("wine-env2"))
        let env = wine.environment(extra: ["MTL_HUD_ENABLED": "1", "CELLAR_TEST": "yes"])
        #expect(env["MTL_HUD_ENABLED"] == "1")
        #expect(env["CELLAR_TEST"] == "yes")
    }

    @Test("The Metal HUD is off unless it is asked for")
    func hudIsOptIn() {
        #expect(WineRunner.d3dMetalEnv(showHUD: false)["MTL_HUD_ENABLED"] == "0")
        #expect(WineRunner.d3dMetalEnv(showHUD: true)["MTL_HUD_ENABLED"] == "1")
        #expect(WineRunner.d3dMetalEnv()["ROSETTA_ADVERTISE_AVX"] == "1",
                "translated games want AVX exposed")
    }

    @Test("A profile's env is layered on top of the D3DMetal defaults, never under them")
    func profileEnvLayersOverDefaults() throws {
        // launchDirect builds `d3dMetalEnv` then applies the profile — so a profile can turn the
        // HUD on for one game without editing Cellar.
        var env = WineRunner.d3dMetalEnv(showHUD: false)
        for (key, value) in ["MTL_HUD_ENABLED": "1"] { env[key] = value }
        #expect(env["MTL_HUD_ENABLED"] == "1")
    }

    @Test("A bottle with no wineserver reports its server as down rather than crashing")
    func serverRunningOnStub() throws {
        let install = try #require(TestHome.installStubRunner())
        let wine = WineRunner(install: install, prefix: TestHome.scratch("wine-server"))
        #expect(wine.serverRunning == false)
        wine.killServer()   // must be a safe no-op
    }

    // MARK: - Fast sync and MetalFX
    //
    // Both were found the same day: the default runner ran with no fast sync because Cellar set
    // the variable a different build understands, and `metalfx_upscaling = true` sat in two
    // profiles that nothing read. So the environment is derived from what the runner ships.

    /// A runner whose `ntdll.so` is a file containing only the given variable names — enough for
    /// the probe, which scans for those strings exactly as it would in the real 5 MB binary.
    private func runner(named name: String, ntdllMentions variables: [String]?,
                        withMetalFXShim: Bool = false) throws -> RunnerInstall {
        TestHome.ensure()
        let root = TestHome.scratch("runner-\(name)")
        let wine = root.appendingPathComponent("wine", isDirectory: true)
        let unix = wine.appendingPathComponent("lib/wine/x86_64-unix", isDirectory: true)
        try FileManager.default.createDirectory(at: unix, withIntermediateDirectories: true)
        if let variables {   // nil: a runner with no ntdll.so to read at all
            try Data("padding \(variables.joined(separator: " ")) padding".utf8)
                .write(to: unix.appendingPathComponent("ntdll.so"))
        }
        let external = wine.appendingPathComponent("lib/d3dmetal/external", isDirectory: true)
        try FileManager.default.createDirectory(at: external, withIntermediateDirectories: true)
        try Data().write(to: external.appendingPathComponent("libd3dshared.dylib"))
        if withMetalFXShim {
            let pe = wine.appendingPathComponent("lib/d3dmetal/wine/x86_64-windows", isDirectory: true)
            try FileManager.default.createDirectory(at: pe, withIntermediateDirectories: true)
            for dll in ["nvngx.dll", "nvapi64.dll"] { try Data().write(to: pe.appendingPathComponent(dll)) }
        }
        return RunnerInstall(spec: RunnerCatalog.wineforge, root: root,
                             wineBinary: wine.appendingPathComponent("bin/wine"))
    }

    @Test("A WineForge build gets WINEWFUSYNC and not the msync variable it would ignore")
    func wineForgeGetsWFUSync() throws {
        let install = try runner(named: "wfusync", ntdllMentions: ["WINEWFUSYNC"])
        #expect(install.fastSync.summary == "WFUSync")
        let env = WineRunner(install: install, prefix: TestHome.scratch("wine-wfusync")).environment()
        #expect(env["WINEWFUSYNC"] == "1")
        #expect(env["WINEMSYNC"] == nil, "a variable the build does not know is noise, not a setting")
        #expect(env["WINEESYNC"] == nil)
    }

    @Test("A Sikarugir-style build gets msync + esync, the variables it actually implements")
    func sikarugirGetsMsync() throws {
        let install = try runner(named: "msync", ntdllMentions: ["WINEMSYNC", "WINEESYNC"])
        #expect(install.fastSync.summary == "msync + esync")
        let env = WineRunner(install: install, prefix: TestHome.scratch("wine-msync")).environment()
        #expect(env["WINEMSYNC"] == "1")
        #expect(env["WINEESYNC"] == "1")
        #expect(env["WINEWFUSYNC"] == nil)
    }

    @Test("A build with no fast sync at all is reported, not silently given the slow path")
    func noFastSyncIsNamed() throws {
        let install = try runner(named: "slowsync", ntdllMentions: [])
        #expect(install.fastSync == .none)
        #expect(install.fastSync.summary == "none")
    }

    @Test("With no readable ntdll.so every known variable is set — an unknown one costs nothing")
    func unreadableNtdllSetsEverything() throws {
        // Not the shared stub: on a Mac with a real runner installed the sandbox links that runner
        // in, and its genuine ntdll.so would answer instead of the "nothing to read" case.
        let install = try runner(named: "no-ntdll", ntdllMentions: nil)
        #expect(install.fastSync == .unknown)
        let env = WineRunner(install: install, prefix: TestHome.scratch("wine-unknown-sync")).environment()
        for variable in ["WINEWFUSYNC", "WINEMSYNC", "WINEESYNC"] { #expect(env[variable] == "1") }
    }

    @Test("A profile's WINEWFUSYNC=0 still wins — the profile is the escape hatch")
    func profileCanDisableFastSync() throws {
        let install = try runner(named: "wfusync-off", ntdllMentions: ["WINEWFUSYNC"])
        let env = WineRunner(install: install, prefix: TestHome.scratch("wine-wfusync-off"))
            .environment(extra: ["WINEWFUSYNC": "0"])
        #expect(env["WINEWFUSYNC"] == "0")
    }

    @Test("metalfx_upscaling presents the NVIDIA identity only when the runtime ships the shims")
    func metalFXNeedsTheShims() throws {
        let bare = try runner(named: "metalfx-bare", ntdllMentions: ["WINEWFUSYNC"])
        #expect(!bare.hasMetalFXShim)
        let wine = WineRunner(install: bare, prefix: TestHome.scratch("wine-mfx-bare"), backend: .d3dmetal, metalFX: true)
        #expect(!wine.usesMetalFX, "asking for MetalFX without nvngx.dll would be a promise the runtime cannot keep")
        let env = wine.environment()
        #expect(env["D3DMETAL_UPSCALER_PROFILE"] == "amd")
        #expect(env["D3DM_ENABLE_METALFX"] == nil)

        let shimmed = try runner(named: "metalfx", ntdllMentions: ["WINEWFUSYNC"], withMetalFXShim: true)
        #expect(shimmed.hasMetalFXShim)
        let on = WineRunner(install: shimmed, prefix: TestHome.scratch("wine-mfx"), backend: .d3dmetal, metalFX: true)
        #expect(on.usesMetalFX)
        let onEnv = on.environment()
        #expect(onEnv["D3DMETAL_UPSCALER_PROFILE"] == "nvidia")
        #expect(onEnv["D3DM_ENABLE_METALFX"] == "1")
        #expect(onEnv["D3DM_VENDOR_ID"] == "4318")
        #expect(onEnv["WINEDLLOVERRIDES"]?.contains("nvngx=b") == true)
        #expect(onEnv["WINEDLLOVERRIDES"]?.contains("gameoverlayrenderer64=d") == true,
                "the overlay fix survives the identity switch")

        let off = WineRunner(install: shimmed, prefix: TestHome.scratch("wine-mfx-off"), backend: .d3dmetal, metalFX: false)
        #expect(!off.usesMetalFX, "a profile that did not ask keeps the AMD identity")
        #expect(off.environment()["D3DMETAL_UPSCALER_PROFILE"] == "amd")
    }

    @Test("metalfx_upscaling is read from the profile — the field is no longer decorative")
    func metalFXComesFromTheProfile() throws {
        let on = try TestHome.plan("[graphics]\nbackend = \"d3dmetal\"\nmetalfx_upscaling = true", slug: "mfx-on")
        #expect(on.metalFXUpscaling)
        let off = try TestHome.plan("[graphics]\nbackend = \"d3dmetal\"", slug: "mfx-off")
        #expect(!off.metalFXUpscaling)
    }
}
