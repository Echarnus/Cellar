import Foundation
import GameController
import IOKit.hid

/// Game controllers: which ones are connected, and what a game's profile says it does with one.
///
/// Wine hands a pad to a Windows game through SDL and its own winebus, which is a different path
/// from macOS's, so a pad macOS sees is not proof the game will. Cellar says what it can check —
/// what is connected — and what the profile records about the game; never "it works" on its own.
public enum Controllers {

    public enum Kind: String, Sendable, CaseIterable {
        case xbox, dualSense, dualShock, switchPro, other

        public var displayName: String {
            switch self {
            case .xbox:      return "Xbox controller"
            case .dualSense: return "DualSense"
            case .dualShock: return "DualShock 4"
            case .switchPro: return "Switch Pro Controller"
            case .other:     return "Controller"
            }
        }

        /// From `GCController.productCategory`, which names the family rather than the model.
        public init(productCategory: String) {
            let category = productCategory.lowercased()
            if category.contains("xbox") { self = .xbox }
            else if category.contains("dualsense") { self = .dualSense }
            else if category.contains("dualshock") { self = .dualShock }
            else if category.contains("switch") || category.contains("joy-con") { self = .switchPro }
            else { self = .other }
        }
    }

    public struct Pad: Sendable, Equatable {
        public let name: String
        public let kind: Kind
    }

    /// The controllers macOS sees now. A command-line process has no run loop turning while it
    /// starts, so it gives discovery a moment first; the app's has been running all along.
    public static func connected(settle: TimeInterval = 0) -> [Pad] {
        if settle > 0 { RunLoop.current.run(until: Date().addingTimeInterval(settle)) }
        return GCController.controllers().compactMap { controller in
            // Keyboards and mice can surface as GCController-adjacent devices; a pad has a gamepad profile.
            guard controller.extendedGamepad != nil || controller.microGamepad != nil else { return nil }
            let category = controller.productCategory
            return Pad(name: controller.vendorName ?? Kind(productCategory: category).displayName,
                       kind: Kind(productCategory: category))
        }
    }

    /// What a profile's `controller` field promises, in the player's words. Nil for no field: an
    /// unrecorded answer is shown as nothing rather than as a guess.
    public static func support(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespaces).lowercased(), !value.isEmpty else { return nil }
        switch value {
        case "full":    return "Full controller support"
        case "partial": return "Partial: some screens need a mouse or keyboard"
        case "none":    return "Keyboard and mouse only"
        default:        return value
        }
    }

    /// Steam Input remaps a pad before the game sees it, so a Steam game launched through the
    /// client may behave differently from the same game started directly.
    public static func steamInputNote(store: GameStore, throughClient: Bool) -> String? {
        guard store == .steam, throughClient else { return nil }
        return "Started through Steam, so Steam Input may remap your controller. Change it in Steam's controller settings for this game."
    }

    // MARK: - What macOS and the runner allow

    /// macOS's Input Monitoring answer for this process. Wine's HID layer opens every matching
    /// device, keyboards included, and macOS refuses the whole request until Input Monitoring is
    /// granted — so without it a pad macOS itself sees never reaches the game (Wine bug 50153).
    public enum InputMonitoring: Sendable, Equatable {
        case granted, denied, notAsked
    }

    /// Peeks at the answer without asking: a check must never be what puts a dialog up.
    public static func inputMonitoring() -> InputMonitoring {
        let access = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)
        if access == kIOHIDAccessTypeGranted { return .granted }
        if access == kIOHIDAccessTypeDenied { return .denied }
        return .notAsked
    }

    /// What `cellar doctor` says about Input Monitoring, for whoever `who` is ("Cellar" or "this
    /// terminal" — macOS records the answer per app). Never a ✓ for "not asked": macOS asks the
    /// first time a game opens a pad, and that is fine.
    public static func inputMonitoringCheck(_ answer: InputMonitoring, who: String) -> CheckResult {
        switch answer {
        case .granted:
            return CheckResult("Input Monitoring", .ok, "allowed for \(who)")
        case .notAsked:
            return CheckResult("Input Monitoring", .info, "not asked yet",
                hint: "The first time a game looks for a controller, macOS asks whether \(who) may "
                    + "“receive keystrokes from any application”. Allow it: that is how macOS names "
                    + "access to controllers and wheels for Wine.")
        case .denied:
            return CheckResult("Input Monitoring", .warn, "turned off for \(who)",
                hint: "Games won't see a controller or wheel. Turn \(who) on in System Settings → "
                    + "Privacy & Security → Input Monitoring, then quit and reopen the game.")
        }
    }

    /// The SDL library a runner carries, if any. Wine's input layer uses SDL when it can load it,
    /// and SDL is what presents a PlayStation or Switch pad to a game as an Xbox controller; without
    /// it Wine falls back to plain HID, where only some pads get that treatment.
    public static func sdlLibrary(in directories: [URL]) -> URL? {
        let fm = FileManager.default
        for directory in directories {
            guard let names = try? fm.contentsOfDirectory(atPath: directory.path) else { continue }
            if let name = names.sorted().first(where: { $0.hasPrefix("libSDL2") || $0.hasPrefix("libSDL3") }),
               name.hasSuffix(".dylib") {
                return directory.appendingPathComponent(name)
            }
        }
        return nil
    }

    /// Where a runner's Wine looks for libraries: the directories `Wine.environment` puts on the
    /// library path for that runner's layout, so a library found here is one Wine can load.
    public static func libraryDirectories(of runner: RunnerInstall) -> [URL] {
        let lib = runner.wineRoot.appendingPathComponent("lib", isDirectory: true)
        if runner.isWineForgeStyle { return [lib] }
        var directories = [lib, runner.wineRoot.appendingPathComponent("lib64", isDirectory: true)]
        if let frameworks = runner.frameworks { directories.append(frameworks) }
        return directories
    }

    /// What `cellar doctor` says about the runner's controller path. Information either way: a
    /// runner can carry SDL and have been built without using it, so this is a pointer, not proof.
    public static func sdlCheck(runnerID: String, library: URL?, cellarSDL: URL? = nil) -> CheckResult {
        if cellarSDL != nil {
            let wheels = Wheels.Vendor.allCases.compactMap { vendor in
                CellarSDL.forceFeedbackWheels[vendor].map { "\(vendor.displayName) \($0)" }
            }
            return CheckResult("Controller layer", .info, "Cellar's SDL, loaded ahead of the \(runnerID) runner's",
                hint: "Pads reach games as Xbox controllers. Wheel force feedback is driven over USB for: "
                    + wheels.joined(separator: "; ") + ".")
        }
        if let library {
            return CheckResult("Controller layer", .info, "SDL in the \(runnerID) runner (\(library.lastPathComponent))",
                hint: "Wine can present PlayStation and Switch pads to games as Xbox controllers.")
        }
        return CheckResult("Controller layer", .info, "no SDL in the \(runnerID) runner",
            hint: "Wine reads pads through macOS's HID layer instead. Xbox pads work best this way; "
                + "a PlayStation or Switch pad may need Steam Input (in Steam's controller settings) to act as one.")
    }

    // MARK: - cellar doctor

    /// The controller rows `cellar doctor` prints, from what was found. Pure, so every state is
    /// tested without hardware. Pads and wheels are `.info` whatever is connected: a device macOS
    /// sees is not proof a game takes it.
    public static func doctorChecks(pads: [Pad], wheels: [Wheels.Device], inputMonitoring: InputMonitoring,
                                    who: String, runnerLayer: CheckResult?, cellarSDL: Bool = false) -> [CheckResult] {
        var checks: [CheckResult] = []
        checks.append(CheckResult("Controllers", .info,
            pads.isEmpty ? "none connected" : pads.map { "\($0.name) (\($0.kind.displayName))" }.joined(separator: ", "),
            hint: pads.isEmpty ? nil : "Whether a game takes it depends on the game: its page says what its profile recorded."))
        if !wheels.isEmpty {
            checks.append(CheckResult("Racing wheels", .info,
                wheels.map { "\($0.name) (\($0.vendor.displayName) \($0.kind.displayName))" }.joined(separator: ", "),
                hint: Wheels.forceFeedbackNote(for: wheels, cellarSDL: cellarSDL) + " What to set up first: cellar controllers"))
        }
        checks.append(inputMonitoringCheck(inputMonitoring, who: who))
        if let runnerLayer { checks.append(runnerLayer) }
        return checks
    }
}
