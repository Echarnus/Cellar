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

    static func describe(_ source: PerformanceSettings.Source) -> String {
        switch source {
        case .cellarDefault: return "Cellar's default"
        case .profile:       return "the game's profile"
        case .bottle:        return "your choice"
        }
    }

    /// The value that will actually take effect, re-read after a change rather than echoed back.
    static func printEffective(_ settings: [PerformanceSetting], slug: String) throws {
        let plan = try Game.plan(slug: slug)
        let (url, _) = bottle(for: plan)
        for entry in plan.performance.entries where settings.contains(entry.setting) {
            print("\(entry.setting.key) = \(Term.bold(entry.value))" + Term.dim("  (\(describe(entry.source)))"))
            printEnvOverride(entry.setting, url: url)
        }
        printCaveats(plan)
    }

    /// A bottle `[env]` line spelling the same switch wins over it — say so, and where it is.
    static func printEnvOverride(_ setting: PerformanceSetting, url: URL) {
        guard let variable = setting.environmentVariable, BottleConfig.env(url)[variable] != nil else { return }
        print(Term.yellow("    \(variable) in this bottle's [env] decides this one, and wins over the switch.")
            + " Remove that line from \(url.path) to use the switch.")
    }

    /// What would make a switch do less than it says, checked rather than assumed.
    static func printCaveats(_ plan: GamePlan) {
        if plan.performance.metalFXUpscaling {
            if plan.graphicsBackend != .d3dmetal {
                print(Term.yellow("MetalFX only works on D3DMetal; this game runs on \(plan.backend), so it does nothing."))
            } else if let install = RunnerManager.find(id: plan.runnerID), !install.hasMetalFXShim {
                print(Term.yellow("MetalFX is on, but this game's runtime has no MetalFX support, so it does nothing."))
            }
        }
        if ProcessInfo.processInfo.isLowPowerModeEnabled {
            print(Term.yellow("Low Power Mode is on.") + " macOS slows the CPU and GPU — turn it off in "
                + "System Settings → Battery (Energy on a desktop Mac) for the best frame rate.")
        }
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
                print("  \(key) \(Term.bold(value))\(Term.dim(PerfCommand.describe(entry.source)))")
                print("    " + Term.dim(entry.setting.summary))
                PerfCommand.printEnvOverride(entry.setting, url: PerfCommand.bottle(for: plan).url)
            }
            PerfCommand.printCaveats(plan)
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
            // The choice lives in the bottle. Creating a bare one here would make setup think the
            // bottle already exists and skip writing its real configuration.
            guard FileManager.default.fileExists(atPath: plan.prefix.path) else {
                throw CellarError.invalidArgument(
                    "\(plan.name) has no bottle yet to keep this in. Run: cellar setup --profile \(slug)  first.")
            }
            let (url, sharedWith) = PerfCommand.bottle(for: plan)
            try BottleConfig.set(setting, to: value, in: url)
            print(Term.green("Saved for \(plan.name), from the next launch:"))
            try PerfCommand.printEffective([setting], slug: slug)
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
            try PerfCommand.printEffective(settings, slug: slug)
        }
    }
}
