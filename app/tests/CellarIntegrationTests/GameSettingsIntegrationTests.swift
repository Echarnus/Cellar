import CellarDomain
import Foundation
import Testing
@testable import CellarData

/// The game page's Retina switch, from the bottle it is saved in to the registry Wine reads it from.
@Suite(.serialized)
struct GameSettingsIntegrationTests {

    // MARK: - Tier A: the choice is kept in a real bottle and reaches the launch plan

    @Test("Retina chosen for one game is saved in its bottle, reaches its plan, and resets")
    func retinaChoiceRoundTrip() throws {
        IT.ensure()
        let slug = IT.writeProfile("""
        [game]
        name = "Sharp Game"
        store = "gog"
        [performance]
        retina = "false"
        """, slug: "it-retina")
        let plan = try Game.plan(slug: slug)
        let bottle = try PrefixManager.create(name: plan.bottleName, backend: .d3dmetal, runner: "wineforge")
        defer { try? PrefixManager.remove(name: bottle.name) }
        let config = BottleConfig.url(forBottle: plan.bottleName)

        #expect(try Game.plan(slug: slug).performance.value(.retina) == "false", "the profile's word first")

        try BottleConfig.set(.retina, to: "true", in: config)
        let chosen = try Game.plan(slug: slug).performance.entries.first { $0.setting == .retina }
        #expect(chosen?.value == "true")
        #expect(chosen?.source == .bottle, "the player's choice wins, and says it is the player's")
        #expect(FileManager.default.fileExists(atPath: bottle.url.appendingPathComponent("bottle.toml").path),
                "saving a setting must not damage the bottle's own configuration")

        try BottleConfig.unset(.retina, in: config)
        #expect(try Game.plan(slug: slug).performance.value(.retina) == "false", "reset goes back to the profile")
    }

    // MARK: - Tier B: the registry value Wine's Mac driver actually reads

    @Test("Retina mode is written where Wine's Mac driver reads it",
          .enabled(if: IT.wineTierEnabled, "set CELLAR_IT=1 to run the Wine tiers"))
    func retinaReachesTheRegistry() throws {
        try #require(IT.machineCanRunWine)
        let runner = try IT.resolveRunner()
        let name = "it-retina-\(UUID().uuidString.prefix(6))"
        let info = try PrefixManager.create(name: name, backend: .d3dmetal, runner: runner.spec.id)
        let wine = WineRunner(install: runner, prefix: info.url)
        defer { wine.killServer(); try? PrefixManager.remove(name: name) }
        try wine.initializePrefix()

        wine.setRetinaMode(true)
        let on = wine.run(["reg", "query", #"HKCU\Software\Wine\Mac Driver"#, "/v", "RetinaMode"])
        #expect(on.stdout.contains("RetinaMode") && on.stdout.contains("y"))

        wine.setRetinaMode(false)
        let off = wine.run(["reg", "query", #"HKCU\Software\Wine\Mac Driver"#, "/v", "RetinaMode"])
        #expect(off.stdout.contains("RetinaMode") && off.stdout.range(of: #"REG_SZ\s+n"#, options: .regularExpression) != nil)
    }
}
