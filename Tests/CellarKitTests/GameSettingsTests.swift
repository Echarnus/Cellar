import CellarDomain
import Foundation
import Testing
@testable import CellarKit

/// The game page's display switches are the same settings `cellar perf` writes, and its log panel
/// carries nothing a player would not want to paste in public.
@Suite(.serialized)
struct GameSettingsTests {

    @Test("Retina is a switch like the others: the profile states it, the bottle overrides it")
    func retinaLayers() {
        let fromProfile = PerformanceSettings.resolve(profileFields: ["retina": "false"], profileEnv: [:],
                                                      bottleFields: [:], bottleEnv: [:])
        let retina = fromProfile.entries.first { $0.setting == .retina }
        #expect(retina?.value == "false")
        #expect(retina?.source == .profile)
        #expect(fromProfile.env["MTL_HUD_ENABLED"] == nil, "retina adds no environment variable")

        let chosen = PerformanceSettings.resolve(profileFields: ["retina": "false"], profileEnv: [:],
                                                 bottleFields: ["retina": "on"], bottleEnv: [:])
        #expect(chosen.value(.retina) == "true")

        let unstated = PerformanceSettings.resolve(profileFields: [:], profileEnv: [:], bottleFields: [:], bottleEnv: [:])
        #expect(unstated.entries.first { $0.setting == .retina }?.source == .cellarDefault,
                "a game nobody said anything about keeps Wine's default and pays for no registry write")
    }

    @Test("The log panel is redacted like the diagnostics report")
    func sessionLogIsRedacted() throws {
        TestHome.ensure()
        let slug = "log-\(UUID().uuidString.prefix(8))".lowercased()
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        try FileManager.default.createDirectory(at: Paths.logs, withIntermediateDirectories: true)
        try "err:module:load_dll \(home)/Games/x.dll not found\naccess_token=abc123\n"
            .write(to: Paths.logs.appendingPathComponent("game-\(slug).log"), atomically: true, encoding: .utf8)
        let text = Diagnostics.sessionLog(slug: slug)
        #expect(text.contains("load_dll"))
        #expect(!text.contains(home))
        #expect(!text.contains("abc123"))
    }
}
