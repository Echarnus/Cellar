import CellarDomain
import ArgumentParser
import CellarData
import Foundation

struct ControllersCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "controllers",
        abstract: "List connected controllers and racing wheels, and what to set up outside Cellar.",
        discussion: """
        Shows the pads and wheels macOS sees right now, whether macOS lets Wine read them (Input
        Monitoring), and — for a wheel — the steps its maker requires that happen outside Cellar,
        such as the wheel base's PC mode and firmware updates.

          cellar controllers
          cellar controllers strength 75
        """,
        subcommands: [List.self, Strength.self],
        defaultSubcommand: List.self
    )
}

extension ControllersCommand {
    struct List: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "List connected controllers and racing wheels (the default).")

        func run() throws {
            let pads = Controllers.connected(settle: 0.5)
            let wheels = Wheels.connected()

            print(Term.bold("Controllers"))
            if pads.isEmpty {
                print(Term.dim("  None connected. Pair a pad in System Settings → Bluetooth, or plug it in over USB."))
            }
            for pad in pads {
                print("  • \(pad.name)" + Term.dim("  \(pad.kind.displayName)"))
            }
            print("")

            print(Term.bold("Racing wheels"))
            if wheels.isEmpty {
                print(Term.dim("  None connected."))
            }
            for vendor in Wheels.Vendor.allCases {
                let devices = wheels.filter { $0.vendor == vendor }
                guard !devices.isEmpty else { continue }
                for device in devices {
                    print("  • \(device.name)" + Term.dim("  \(vendor.displayName) \(device.kind.displayName)"))
                }
                print(Term.dim("    Before you play:"))
                for step in vendor.setup { print(Term.dim("    – \(step)")) }
            }
            if !wheels.isEmpty {
                print(Term.dim("  " + Wheels.forceFeedbackNote(for: wheels, cellarSDL: CellarSDL.libraryDirectory != nil)))
                print(Term.dim("  Strength: " + CellarSDL.strengthDescription(CellarSettings.forceFeedbackStrength)
                    + ". Change it with: cellar controllers strength <percent>"))
            }
            print("")

            let who = Bundle.main.bundleIdentifier == "it.clercq.cellar.app" ? "Cellar" : "this terminal"
            let access = Controllers.inputMonitoringCheck(Controllers.inputMonitoring(), who: who)
            print("\(Term.symbol(for: access.status)) \(access.name): \(access.detail)")
            if let hint = access.hint { print("    " + Term.dim("→ \(hint)")) }
        }
    }

    struct Strength: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Show or set how hard a wheel Cellar drives may push, from the next launch.",
            discussion: """
            A percentage of the wheel's maximum, for every wheel Cellar drives force feedback for.
            "default" goes back to Cellar's own: Fanatec bases at half strength, Logitech and
            Thrustmaster wheels at full. A direct-drive base is strong: raise it a step at a time.

              cellar controllers strength
              cellar controllers strength 75
              cellar controllers strength default
            """)

        @Argument(help: "A percentage from 1 to 100, or \"default\".")
        var percent: String?

        func run() throws {
            guard let percent else {
                print(CellarSDL.strengthDescription(CellarSettings.forceFeedbackStrength))
                return
            }
            if percent.lowercased() == "default" {
                try CellarSettings.setForceFeedbackStrength(nil)
            } else {
                let digits = percent.hasSuffix("%") ? String(percent.dropLast()) : percent
                guard let value = Int(digits), (1...100).contains(value) else {
                    throw ValidationError("Give a percentage from 1 to 100, or \"default\" — not \"\(percent)\".")
                }
                try CellarSettings.setForceFeedbackStrength(value)
            }
            print(Term.green("From the next launch: ") + CellarSDL.strengthDescription(CellarSettings.forceFeedbackStrength))
        }
    }
}
