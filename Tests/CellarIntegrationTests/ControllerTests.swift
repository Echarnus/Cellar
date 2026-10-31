import CellarDomain
import Foundation
import Testing
@testable import CellarKit

/// Tier A: what Cellar says about game controllers, through the same paths `cellar doctor` and the
/// library use — real GameController discovery, a real profile on disk, the real summaries.
@Suite(.serialized)
struct ControllerTests {

    @Test("`cellar doctor` reports controllers as information, and agrees with discovery")
    func doctorReportsControllers() {
        let pads = Controllers.connected(settle: 0.5)
        let check = SystemEnvironment.diagnostics().first { $0.name == "Controllers" }
        #expect(check != nil, "doctor must always say something about controllers")
        #expect(check?.status == .info, "a pad macOS sees is not proof a game takes it — never a ✓")
        if pads.isEmpty {
            // CI runners have no pads: the honest answer is "none", with no hint promising more.
            #expect(check?.detail == "none connected")
            #expect(check?.hint == nil)
        } else {
            for pad in pads { #expect(check?.detail.contains(pad.name) == true) }
        }
    }

    @Test("A profile's controller answer reaches the library, and no answer shows nothing")
    func controllerFactReachesTheLibrary() throws {
        IT.ensure()
        let recorded = IT.writeProfile("""
        [game]
        name = "Pad Game"
        store = "gog"
        [compatibility]
        controller = "partial"
        """, slug: "it-pad")
        let silent = IT.writeProfile("""
        [game]
        name = "Quiet Game"
        store = "gog"
        """, slug: "it-nopad")

        let summaries = Game.summaries()
        let withPad = try #require(summaries.first { $0.slug == recorded })
        #expect(withPad.facts.compatibility.contains {
            $0.label == "Controller" && $0.value.hasPrefix("Partial")
        })
        let without = try #require(summaries.first { $0.slug == silent })
        #expect(without.facts.compatibility.contains { $0.label == "Controller" } == false,
                "an unrecorded answer is not a guess")
    }

    @Test("The shipped race sims reach the library with their wheel answer and set-up steps")
    func raceSimsReachTheLibrary() throws {
        #expect(IT.shippedProfilesStaged)
        let summaries = Game.summaries()
        for slug in ["assetto-corsa", "assetto-corsa-competizione"] {
            let summary = try #require(summaries.first { $0.slug == slug },
                                       "'\(slug)' is in profiles/ but not among the games Cellar knows")
            #expect(summary.store == .steam)
            #expect(summary.facts.compatibility.contains {
                $0.label == "Racing wheel" && $0.value.hasPrefix("Made for a wheel")
            })
            #expect(summary.facts.wheelSetup?.contains("Controls") == true)
            // The plan the launch would use agrees with what the library shows.
            let plan = try Game.plan(slug: slug)
            #expect(plan.needsLiveSession)
            #expect(GraphicsBackend(rawValue: plan.backend) != nil)
            #expect(plan.fallbackBackend.flatMap(GraphicsBackend.init(rawValue:)) != nil)
        }
    }

    @Test("`cellar doctor` always says where Input Monitoring stands, and lists only real wheels")
    func doctorReportsInputAccessAndWheels() {
        let checks = SystemEnvironment.diagnostics()
        let access = checks.first { $0.name == "Input Monitoring" }
        #expect(access != nil, "without Input Monitoring a pad never reaches the game, so doctor must say")
        #expect(access?.status != .fail, "Input Monitoring is never a blocker: macOS asks when a game needs it")

        // Real HID enumeration, on whatever this Mac has plugged in.
        let wheels = Wheels.connected()
        for wheel in wheels {
            #expect(Wheels.classify(vendorID: wheel.vendor.vendorID, productID: wheel.productID,
                                    product: wheel.name) == wheel)
        }
        let row = checks.first { $0.name == "Racing wheels" }
        #expect((row != nil) == !wheels.isEmpty, "a wheel row appears exactly when a wheel is connected")
        #expect(row == nil || row?.status == .info)
    }

    @Test("A wrapper-style runner's SDL is found in its Frameworks, as Wine's library path has it")
    func wrapperRunnerSDL() throws {
        IT.ensure()
        let root = IT.scratch("runner-sdl")
        let fm = FileManager.default
        let bin = root.appendingPathComponent("wine/bin", isDirectory: true)
        let frameworks = root.appendingPathComponent("Frameworks", isDirectory: true)
        try fm.createDirectory(at: bin, withIntermediateDirectories: true)
        try fm.createDirectory(at: frameworks, withIntermediateDirectories: true)
        let install = RunnerInstall(spec: RunnerCatalog.wineforge, root: root,
                                    wineBinary: bin.appendingPathComponent("wine"))
        #expect(!install.isWineForgeStyle)
        #expect(Controllers.sdlLibrary(in: Controllers.libraryDirectories(of: install)) == nil)

        try Data().write(to: frameworks.appendingPathComponent("libSDL2-2.0.0.dylib"))
        let found = Controllers.sdlLibrary(in: Controllers.libraryDirectories(of: install))
        #expect(found?.deletingLastPathComponent().standardizedFileURL == frameworks.standardizedFileURL)

        // And the Wine environment for this runner really does put that directory on the library path.
        let env = WineRunner(install: install, prefix: IT.scratch("prefix-sdl")).environment()
        #expect(env["DYLD_FALLBACK_LIBRARY_PATH"]?.split(separator: ":").map(String.init).contains(frameworks.path) == true)
    }
}
