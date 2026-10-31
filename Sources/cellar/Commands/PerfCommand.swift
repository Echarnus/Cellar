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
          cellar perf measure planet-coaster-2                  frame rate of the last minute, and what limits it
        """,
        subcommands: [Show.self, Set.self, Reset.self, Measure.self],
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
        switch ProcessInfo.processInfo.thermalState {
        case .serious, .critical:
            print(Term.yellow("Your Mac is running hot.") + " macOS is slowing the CPU and GPU to cool it down, "
                + "so the frame rate will drop until it does.")
        default:
            break
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

        @Argument(help: "Switch: wine_debug, metal_validation, metalfx_upscaling, metal_hud, retina.")
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

    struct Measure: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Measure a game's frame rate from the last minute of play, and say what limits it.",
            discussion: """
            Reads the Metal performance HUD's own numbers, so the HUD has to be on while you play:

              cellar perf set planet-coaster-2 metal_hud on    (or: cellar launch planet-coaster-2 --hud)
              … play the scene you care about for a minute …
              cellar perf measure planet-coaster-2

            Run it while the game is still open, or right after. Keep the HUD visible: hidden with
            Shift-F9 it stops updating the frame times.
            """)

        @Argument(help: "Profile slug, e.g. 'planet-coaster-2'.")
        var slug: String

        @Option(help: "How many seconds of play to measure, counting back from now.")
        var seconds: Int = 60

        @Option(help: "Read the HUD's lines from this file instead (a saved log).")
        var from: String?

        func run() throws {
            let plan = try Game.plan(slug: slug)
            guard seconds > 0 else { throw CellarError.invalidArgument("--seconds has to be more than 0.") }
            let measured: FrameStats?
            if let from {
                let text = try String(contentsOf: URL(fileURLWithPath: (from as NSString).expandingTildeInPath),
                                      encoding: .utf8)
                measured = FrameStats.measure(text)
            } else {
                measured = FrameStats.measure(FrameStats.Source.unifiedLog(seconds: seconds))
                    ?? FrameStats.measure(FrameStats.Source.launchLogs(bottle: plan.bottleName, slug: slug,
                                                                       seconds: seconds))
            }
            guard let stats = measured else {
                let window = from == nil ? " from the last \(seconds) seconds" : ""
                print(Term.yellow("No frame timing found\(window)."))
                print("Measuring reads the Metal performance HUD, so it needs the HUD on while you play:")
                print("  cellar perf set \(slug) metal_hud on")
                print("then start \(plan.name), play for a minute, and run this again.")
                print(Term.dim("If Steam was already open without the HUD, quit it first: the game takes its settings from Steam."))
                throw ExitCode.failure
            }
            print(Term.bold(plan.name) + Term.dim("  \(stats.frames) frames measured"))
            print("  Frame rate      " + Term.bold(String(format: "%.0f FPS", stats.averageFPS))
                + Term.dim(String(format: "  (%.1f ms a frame)", stats.averageFrameMs)))
            print("  Slowest 1%      " + Term.bold(String(format: "%.0f FPS", stats.onePercentLowFPS)))
            print("  GPU busy        " + Term.bold(String(format: "%.1f ms", stats.averageGPUMs))
                + Term.dim(String(format: "  (%.0f%% of each frame)", stats.gpuShare * 100)))
            print("")
            for line in Measure.advice(stats, plan: plan) { print(line) }
            PerfCommand.printCaveats(plan)
        }

        /// What the numbers mean for this game, and the one thing worth trying next.
        static func advice(_ stats: FrameStats, plan: GamePlan) -> [String] {
            switch stats.limit {
            case .gpu:
                var lines = [Term.bold("The graphics card is the limit.") + " It is busy for the whole frame."]
                if plan.graphicsBackend == .d3dmetal && !plan.performance.metalFXUpscaling {
                    lines.append("Try MetalFX upscaling: cellar perf set \(plan.slug) metalfx_upscaling on, "
                        + "then choose DLSS in the game's graphics settings.")
                } else {
                    lines.append("Lower the resolution or the heaviest graphics settings in the game.")
                }
                return lines
            case .cpu:
                var lines = [Term.bold("The processor is the limit.")
                    + String(format: " The graphics card waits about %.0f ms of every frame for it.",
                             stats.averageFrameMs - stats.averageGPUMs),
                    "Graphics settings will barely change this; less going on in the scene will."]
                if plan.performance.value(.metalValidation) == "true" {
                    lines.append(Term.dim("Metal validation is on for this game (a crash workaround) and adds to the "
                        + "processor's work. See: cellar perf \(plan.slug)"))
                }
                return lines
            case .capped:
                return [Term.bold("The frame rate is capped") + " at your display's refresh rate, by vsync or the game's "
                    + "frame limit — the Mac has power to spare.",
                        "Turn vsync or the frame limit off in the game to see how fast it can go."]
            case .balanced:
                return ["Neither the processor nor the graphics card clearly limits the frame rate, so lower graphics "
                    + "settings and a quieter scene will each help a little."]
            }
        }
    }
}
