import Foundation
import Testing
@testable import CellarKit

/// Tier A: the SDL Cellar actually ships. `Scripts/build-sdl.sh` builds it into `.build/sdl` (CI does
/// that before the tests); this loads that real library the way winebus does — `dlopen`, then the
/// SDL 2 entry points by name — and starts the joystick and haptic subsystems in it.
@Suite(.serialized)
struct CellarSDLIntegrationTests {
    typealias Init = @convention(c) (UInt32) -> Int32
    typealias GetVersion = @convention(c) (UnsafeMutablePointer<UInt8>) -> Void
    typealias NumHaptics = @convention(c) () -> Int32
    typealias Quit = @convention(c) () -> Void

    var built: URL { IT.repositoryRoot.appendingPathComponent(".build/sdl", isDirectory: true) }

    /// CI always builds it first, so there a missing build is a failure; on a checkout it is a skip
    /// that says so.
    func requireBuilt() -> Bool {
        if CellarSDL.isComplete(built) { return true }
        if ProcessInfo.processInfo.environment["CI"] == "true" {
            Issue.record("Cellar's SDL was not built before the tests: run Scripts/build-sdl.sh")
        } else {
            IT.log("Cellar's SDL not built (sh Scripts/build-sdl.sh) — skipping the load test")
        }
        return false
    }

    @Test("The shipped SDL loads by path, starts joystick + haptic, and is sdl2-compat over SDL 3")
    func loadsLikeWinebus() throws {
        guard requireBuilt() else { return }
        let library = built.appendingPathComponent("libSDL2-2.0.0.dylib").path
        let handle = try #require(dlopen(library, RTLD_NOW | RTLD_LOCAL), "dlopen: \(String(cString: dlerror()))")
        defer { dlclose(handle) }
        func symbol<T>(_ name: String, as: T.Type) throws -> T {
            unsafeBitCast(try #require(dlsym(handle, name), "\(name) missing"), to: T.self)
        }
        let initialise = try symbol("SDL_Init", as: Init.self)
        let version = try symbol("SDL_GetVersion", as: GetVersion.self)
        let haptics = try symbol("SDL_NumHaptics", as: NumHaptics.self)
        let quit = try symbol("SDL_Quit", as: Quit.self)

        // SDL_INIT_JOYSTICK | SDL_INIT_HAPTIC — what winebus starts.
        #expect(initialise(0x0000_0200 | 0x0000_1000) == 0, "SDL_Init failed: sdl2-compat did not find its SDL 3")
        var bytes = [UInt8](repeating: 0, count: 3)
        version(&bytes)
        #expect(bytes[0] == 2 && bytes[1] >= 32, "expected sdl2-compat 2.32+, got \(bytes)")
        #expect(haptics() >= 0)
        quit()
    }

    @Test("Cellar finds that build from a repo checkout, and the runner switch turns it off")
    func foundFromCheckout() {
        guard requireBuilt() else { return }
        let found = CellarSDL.libraryDirectory(environment: [:], resources: nil, executable: nil,
                                               workingDirectory: IT.repositoryRoot.path, appSupport: IT.scratch("as"))
        #expect(found?.standardizedFileURL == built.standardizedFileURL)
        #expect(CellarSDL.libraryDirectory(environment: ["CELLAR_RUNNER_SDL": "1"], resources: nil, executable: nil,
                                           workingDirectory: IT.repositoryRoot.path, appSupport: IT.scratch("as")) == nil)
    }
}
