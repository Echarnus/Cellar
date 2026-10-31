import Foundation
import Testing
@testable import CellarKit

/// Cellar's own SDL: where it is found, that Wine is pointed at it first, and that what the player is
/// told about force feedback matches the wheels it actually drives.
@Suite(.serialized)
struct CellarSDLTests {

    private func fakeSDL(_ label: String, complete: Bool = true) throws -> URL {
        let dir = TestHome.scratch(label).appendingPathComponent("sdl", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data().write(to: dir.appendingPathComponent("libSDL2-2.0.0.dylib"))
        if complete { try Data().write(to: dir.appendingPathComponent("libSDL3.dylib")) }
        return dir
    }

    @Test("Cellar's SDL goes first on Wine's library path, once, and nothing changes without it")
    func libraryPathOrder() {
        let dyld = ["/runner/wine/lib", "/usr/lib"]
        let sdl = URL(fileURLWithPath: "/Cellar.app/Contents/Resources/sdl", isDirectory: true)
        #expect(CellarSDL.libraryPath(dyld, sdl: sdl) == [sdl.path] + dyld)
        #expect(CellarSDL.libraryPath([sdl.path] + dyld, sdl: sdl) == [sdl.path] + dyld)
        #expect(CellarSDL.libraryPath(dyld, sdl: nil) == dyld)
    }

    @Test("Half an SDL is not used: sdl2-compat without SDL 3 would leave Wine with no controllers")
    func needsBothHalves() throws {
        let half = try fakeSDL("sdl-half", complete: false)
        #expect(CellarSDL.isComplete(half) == false)
        #expect(CellarSDL.libraryDirectory(environment: ["CELLAR_SDL_DIR": half.path], resources: nil, executable: nil,
                                           workingDirectory: "/nonexistent", appSupport: TestHome.scratch("as")) == nil)
        let whole = try fakeSDL("sdl-whole")
        #expect(CellarSDL.isComplete(whole))
    }

    @Test("The app bundle's SDL is found, and CELLAR_RUNNER_SDL=1 turns it off")
    func lookupOrder() throws {
        let sdl = try fakeSDL("sdl-bundle")
        let resources = sdl.deletingLastPathComponent()
        let found = CellarSDL.libraryDirectory(environment: [:], resources: resources, executable: nil,
                                               workingDirectory: "/nonexistent", appSupport: TestHome.scratch("as"))
        #expect(found?.standardizedFileURL == sdl.standardizedFileURL)
        #expect(CellarSDL.libraryDirectory(environment: ["CELLAR_RUNNER_SDL": "1"], resources: resources, executable: nil,
                                           workingDirectory: "/nonexistent", appSupport: TestHome.scratch("as")) == nil)
    }

    @Test("Force feedback is promised only for wheels Cellar's SDL drives, and only when it is installed")
    func forceFeedbackPromise() throws {
        let g29 = try #require(Wheels.classify(vendorID: 0x046D, productID: 0xC24F, product: "G29 Driving Force Racing Wheel"))
        let g920 = try #require(Wheels.classify(vendorID: 0x046D, productID: 0xC262, product: "Logitech G920 Driving Force Racing Wheel"))
        let csl = try #require(Wheels.classify(vendorID: 0x0EB7, productID: 0x0020, product: "FANATEC CSL DD"))
        let elite = try #require(Wheels.classify(vendorID: 0x0EB7, productID: 0x0E03, product: "FANATEC CSL Elite Wheel Base"))
        let unknownBase = try #require(Wheels.classify(vendorID: 0x0EB7, productID: 0x0ABC, product: "FANATEC Wheel"))
        let t300 = try #require(Wheels.classify(vendorID: 0x044F, productID: 0xB66E, product: "Thrustmaster T300RS Racing wheel"))
        let t150 = try #require(Wheels.classify(vendorID: 0x044F, productID: 0xB677, product: "Thrustmaster T150 Racing Wheel"))
        let generic = try #require(Wheels.classify(vendorID: 0x044F, productID: 0xB65D, product: "Thrustmaster FFB Wheel"))
        let pedals = try #require(Wheels.classify(vendorID: 0x0EB7, productID: 0x6204, product: "FANATEC CSL Pedals"))

        #expect(CellarSDL.drivesForceFeedback(g29))
        #expect(!CellarSDL.drivesForceFeedback(g920), "the G920 speaks HID++, which SDL 3.4's driver does not")
        #expect(CellarSDL.drivesForceFeedback(csl))
        #expect(CellarSDL.drivesForceFeedback(elite))
        #expect(!CellarSDL.drivesForceFeedback(unknownBase), "a base the driver does not know is never promised")
        #expect(CellarSDL.drivesForceFeedback(t300))
        #expect(!CellarSDL.drivesForceFeedback(t150), "the T150 speaks another protocol")
        #expect(!CellarSDL.drivesForceFeedback(generic), "a wheel in generic mode could be a T150: never promised")
        #expect(!CellarSDL.drivesForceFeedback(pedals))

        #expect(Wheels.forceFeedbackNote(for: [g29], cellarSDL: true) == Wheels.drivenForceFeedbackNote)
        #expect(Wheels.forceFeedbackNote(for: [g29, pedals], cellarSDL: true) == Wheels.drivenForceFeedbackNote)
        #expect(Wheels.forceFeedbackNote(for: [g29], cellarSDL: false) == Wheels.forceFeedbackNote)
        #expect(Wheels.forceFeedbackNote(for: [csl, pedals], cellarSDL: true)
                == Wheels.drivenForceFeedbackNote + " " + Wheels.cappedStrengthNote, "a Fanatec base says why it feels soft")
        #expect(!Wheels.forceFeedbackNote(for: [g29], cellarSDL: true).contains("half strength"))
        #expect(Wheels.forceFeedbackNote(for: [csl], cellarSDL: false) == Wheels.forceFeedbackNote)
        #expect(Wheels.forceFeedbackNote(for: [g29, t150], cellarSDL: true) == Wheels.forceFeedbackNote,
                "one undriven wheel connected: never the hopeful sentence")
        #expect(Wheels.forceFeedbackNote(for: [t300], cellarSDL: true) == Wheels.drivenForceFeedbackNote,
                "a Thrustmaster runs at the game's own strength: no half-strength sentence")
        #expect(Wheels.forceFeedbackNote(for: [generic], cellarSDL: true) == Wheels.thrustmasterGenericNote)
        #expect(Wheels.forceFeedbackNote(for: [csl, generic], cellarSDL: true)
                == [Wheels.drivenForceFeedbackNote, Wheels.cappedStrengthNote, Wheels.thrustmasterGenericNote].joined(separator: " "))
        #expect(Wheels.forceFeedbackNote(for: [generic], cellarSDL: false) == Wheels.forceFeedbackNote)
        #expect(Wheels.thrustmasterGenericNote.contains("T150"), "the models it cannot switch are named")
        #expect(Wheels.forceFeedbackNote(for: [pedals], cellarSDL: true) == Wheels.forceFeedbackNote)
    }

    @Test("Doctor names Cellar's SDL and exactly the wheels it drives")
    func doctorRow() {
        let row = Controllers.sdlCheck(runnerID: "wineforge", library: nil,
                                       cellarSDL: URL(fileURLWithPath: "/x/sdl"))
        #expect(row.status == .info)
        #expect(row.detail.contains("Cellar's SDL"))
        #expect(row.hint?.contains("Logitech G29") == true)
        #expect(row.hint?.contains("Fanatec CSL DD") == true)
        #expect(row.hint?.contains("Thrustmaster T300 RS") == true)
        #expect(row.hint?.contains("G920") == false, "HID++ wheels are not driven yet")
    }

    // MARK: - Strength

    @Test("No strength chosen leaves every driver at its own default")
    func strengthDefault() {
        #expect(CellarSDL.strengthEnvironment(nil).isEmpty)
        #expect(CellarSDL.strengthDescription(nil).contains("Fanatec bases at half strength"))
        #expect(CellarSDL.strengthDescription(nil).contains("Thrustmaster wheels at full strength"))
    }

    @Test("A chosen strength reaches both drivers, in each one's own units, clamped to 1–100")
    func strengthUnits() {
        let env = CellarSDL.strengthEnvironment(75)
        #expect(env["CELLAR_FFB_MAX_PERCENT"] == "75")
        #expect(env["SDL_HAPTIC_LG4FF_GAIN"] == "49151", "SDL's Logitech gain runs 0–65535")
        #expect(CellarSDL.strengthEnvironment(100)["SDL_HAPTIC_LG4FF_GAIN"] == "65535")
        #expect(CellarSDL.strengthEnvironment(0)["CELLAR_FFB_MAX_PERCENT"] == "1")
        #expect(CellarSDL.strengthEnvironment(250)["CELLAR_FFB_MAX_PERCENT"] == "100")
        #expect(CellarSDL.strengthChoices.allSatisfy { (1...100).contains($0) })
    }

    @Test("A strength typed on the command line wins over the one in Settings")
    func strengthCallerWins() {
        var env = ["CELLAR_FFB_MAX_PERCENT": "90"]
        CellarSDL.applyStrength(25, to: &env)
        #expect(env["CELLAR_FFB_MAX_PERCENT"] == "90")
        #expect(env["SDL_HAPTIC_LG4FF_GAIN"] == "16383", "the other driver still gets Settings' value")

        var empty: [String: String] = [:]
        CellarSDL.applyStrength(nil, to: &empty)
        #expect(empty.isEmpty)
    }
}
