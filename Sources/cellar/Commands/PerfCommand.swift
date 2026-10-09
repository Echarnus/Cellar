import ArgumentParser
import CellarKit
import Foundation

struct PerfCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "perf",
        abstract: "Show or change a game's performance switches (Wine logging, Metal validation, MetalFX, HUD).",
        discussion: """
        Your choices are kept in the game's bottle (bottle.toml) and win over the game's profile, so a
        profile update never undoes them. They apply from the next launch.

          cellar perf planet-coaster-2                          what is on, and where it comes from
          cellar perf set planet-coaster-2 wine_debug off       stop Wine's debug logging
          cellar perf set planet-coaster-2 metal_validation off try without the validation layer
          cellar perf reset planet-coaster-2 metal_validation   back to the profile's choice
        """,
        subcommands: [Show.self, Set.self, Reset.self],
        defaultSubcommand: Show.self
    )

    static var keyList: String { PerformanceSetting.allCases.map(\.key).joined(separator: ", ") }

    static func setting(_ key: String) throws -> PerformanceSetting {
        guard let setting = PerformanceSetting.named(key) else {
            throw CellarError.invalidArgument("No switch called '\(key)'. Try one of: \(keyList)")
        }
        return setting
    }

    /// The bottle a game's choices go into — and the other games that will see them too.
    static func bottle(for plan: GamePlan) -> (url: URL, sharedWith: [String]) {
        (BottleConfig.url(forBottle: plan.bottleName),
         Game.slugs(sharingBottle: plan.bottleName).filter { $0 != plan.slug })
    }

    struct Show: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Show a game's performance switches.")

        @Argument(help: "Profile slug, e.g. 'planet-coaster-2'.")
        var slug: String

        func run() throws {
            let plan = try Game.plan(slug: slug)
            print(Term.bold(plan.name) + Term.dim("  performance switches"))
            for entry in plan.performance.entries {
                let key = entry.setting.key.padding(toLength: 18, withPad: " ", startingAt: 0)
                // Pad, never truncate: a Wine channel list is longer than the column.
                let value = entry.value + String(repeating: " ", count: max(1, 8 - entry.value.count))
                let from: String
                switch entry.source {
                case .cellarDefault: from = "Cellar's default"
                case .profile:       from = "the game's profile"
                case .bottle:        from = "your choice"
                }
                print("  \(key) \(Term.bold(value))\(Term.dim(from))")
                print("    " + Term.dim(entry.setting.summary))
            }
            if plan.performance.metalFXUpscaling, let wine = Game.wineRunner(plan), !wine.usesMetalFX {
                print(Term.yellow("MetalFX is on, but this runner has no MetalFX support, so it does nothing."))
            }
            if ProcessInfo.processInfo.isLowPowerModeEnabled {
                print(Term.yellow("Low Power Mode is on.") + " macOS slows the CPU and GPU — turn it off in "
                    + "System Settings → Battery for the best frame rate.")
            }
            print(Term.dim("Change one: cellar perf set \(slug) <switch> <value>"))
        }
    }

    struct Set: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Change a switch for this game, from its next launch.")

        @Argument(help: "Profile slug, e.g. 'planet-coaster-2'.")
        var slug: String

        @Argument(help: "Switch: wine_debug, metal_validation, metalfx_upscaling, metal_hud.")
        var key: String

        @Argument(help: "on/off, or for wine_debug: off or Wine channels such as err+all.")
        var value: String

        func run() throws {
            let plan = try Game.plan(slug: slug)
            let setting = try PerfCommand.setting(key)
            let (url, sharedWith) = PerfCommand.bottle(for: plan)
            try BottleConfig.set(setting, to: value, in: url)
            let saved = try setting.normalise(value)
            print(Term.green("\(setting.key) = \(saved)") + " for \(plan.name), from the next launch.")
            if !sharedWith.isEmpty {
                print(Term.dim("Shared bottle: \(sharedWith.joined(separator: ", ")) get this too."))
            }
        }
    }

    struct Reset: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Drop your choice and go back to the game's profile.")

        @Argument(help: "Profile slug, e.g. 'planet-coaster-2'.")
        var slug: String

        @Argument(help: "Switch to reset, or 'all'.")
        var key: String

        func run() throws {
            let plan = try Game.plan(slug: slug)
            let settings = key == "all" ? PerformanceSetting.allCases : [try PerfCommand.setting(key)]
            let (url, _) = PerfCommand.bottle(for: plan)
            for setting in settings { try BottleConfig.unset(setting, in: url) }
            for entry in try Game.plan(slug: slug).performance.entries where settings.contains(entry.setting) {
                let from = entry.source == .profile ? "the game's profile" : "Cellar's default"
                print("\(entry.setting.key) = \(entry.value)" + Term.dim("  (\(from))"))
            }
        }
    }
}
