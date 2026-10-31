import ArgumentParser
import CellarKit
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
        """
    )

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
        }
        print("")

        let who = Bundle.main.bundleIdentifier == "it.clercq.cellar.app" ? "Cellar" : "this terminal"
        let access = Controllers.inputMonitoringCheck(Controllers.inputMonitoring(), who: who)
        print("\(Term.symbol(for: access.status)) \(access.name): \(access.detail)")
        if let hint = access.hint { print("    " + Term.dim("→ \(hint)")) }
    }
}
