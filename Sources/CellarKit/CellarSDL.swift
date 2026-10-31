import Foundation

/// Cellar's own build of SDL, loaded by Wine ahead of the runner's.
///
/// Wine's input layer (winebus) loads `libSDL2-2.0.0.dylib` by name and hands every game controller,
/// and a game's force-feedback effects, to it. The runner ships an SDL 2 whose only way to drive a
/// wheel's motor is macOS's ForceFeedback plug-ins — which no wheel maker ships for Apple Silicon.
/// Cellar's build is SDL 3 with sdl2-compat in front of it: SDL 3.4 talks to Logitech's older wheels
/// over USB itself (HIDAPI), and Cellar's own patch (`Shim/sdl/`) drives Fanatec bases the same way,
/// so the effects reach the motor. `Scripts/build-sdl.sh` builds it; it is
/// installed beside the `cellar` binary the same way the Dock shim is.
///
/// Missing — a partial build, an old install — every launch uses the runner's SDL, exactly as before:
/// a wheel steers but has no force feedback. `CELLAR_RUNNER_SDL=1` chooses that on purpose.
public enum CellarSDL {
    static let directoryName = "sdl"
    static let libraryName = "libSDL2-2.0.0.dylib"

    /// The wheels this build drives force feedback for, by maker, in the player's words. Kept beside
    /// the build so the doctor row and the FAQ never claim a wheel the library cannot drive.
    public static let forceFeedbackWheels: [Wheels.Vendor: String] = [
        .logitech: "G29, G27, G25, Driving Force GT and Driving Force Pro",
        .fanatec: "CSL DD, GT DD Pro, ClubSport DD, Podium DD1 and DD2, CSL Elite, ClubSport V2 and V2.5, CSR Elite and Porsche 911",
    ]

    /// The USB product IDs behind `forceFeedbackWheels`: SDL 3.4's Logitech driver's own list, and
    /// the bases `CellarFanatec_IsSupported` takes (Shim/sdl/0001-cellar-fanatec-force-feedback.patch).
    /// The CSL DD, GT DD Pro and ClubSport DD all report 0x0020 in PC mode.
    static let forceFeedbackProducts: [Wheels.Vendor: Set<Int>] = [
        .logitech: [0xC24F, 0xC29B, 0xC299, 0xC29A, 0xC298, 0xC294],
        .fanatec: [0x0001, 0x0004, 0x0005, 0x0006, 0x0007, 0x0011, 0x0020, 0x0197, 0x0E03],
    ]

    /// How strong Cellar lets a wheel it drives get, in percent of the base's maximum, until the
    /// player raises it (`CELLAR_FFB_MAX_PERCENT`). A direct-drive base at full torque can hurt.
    public static let defaultStrengthPercent = 50

    /// Whether Cellar's SDL drives this device's motor. Pedals and shifters have none.
    public static func drivesForceFeedback(_ device: Wheels.Device) -> Bool {
        device.kind == .wheel && forceFeedbackProducts[device.vendor]?.contains(device.productID) == true
    }

    /// The directory holding Cellar's SDL, most specific first — the same places `DockShim` looks.
    public static var libraryDirectory: URL? {
        libraryDirectory(environment: ProcessInfo.processInfo.environment,
                         resources: Bundle.main.resourceURL,
                         executable: ProcessInfo.processInfo.arguments.first,
                         workingDirectory: FileManager.default.currentDirectoryPath,
                         appSupport: Paths.appSupport)
    }

    /// The lookup itself, with everything it reads passed in, so it is tested without touching the
    /// process's environment.
    static func libraryDirectory(environment: [String: String], resources: URL?, executable: String?,
                                 workingDirectory: String, appSupport: URL) -> URL? {
        if environment["CELLAR_RUNNER_SDL"] == "1" { return nil }
        var candidates: [URL] = []
        if let override = environment["CELLAR_SDL_DIR"], !override.isEmpty {
            candidates.append(URL(fileURLWithPath: override, isDirectory: true))
        }
        // Cellar.app/Contents/Resources/sdl
        if let resources {
            candidates.append(resources.appendingPathComponent(directoryName, isDirectory: true))
        }
        if let executable {
            let binDir = URL(fileURLWithPath: executable).resolvingSymlinksInPath().deletingLastPathComponent()
            // An installed CLI: <prefix>/bin/cellar next to <prefix>/share/cellar/sdl.
            candidates.append(binDir.appendingPathComponent("../share/cellar/\(directoryName)").standardizedFileURL)
        }
        // The default output of Scripts/build-sdl.sh, run from the repo root.
        candidates.append(URL(fileURLWithPath: workingDirectory)
            .appendingPathComponent(".build/\(directoryName)", isDirectory: true))
        candidates.append(appSupport.appendingPathComponent(directoryName, isDirectory: true))
        return candidates.first(where: isComplete)
    }

    /// Both halves present: sdl2-compat alone would fail to start without the SDL 3 beside it, and
    /// winebus would then run with no controllers at all — worse than the runner's SDL.
    static func isComplete(_ directory: URL) -> Bool {
        let fm = FileManager.default
        return fm.fileExists(atPath: directory.appendingPathComponent(libraryName).path)
            && fm.fileExists(atPath: directory.appendingPathComponent("libSDL3.dylib").path)
    }

    /// `dyld` with Cellar's SDL in front, so Wine's load-by-name finds it before the runner's copy.
    /// Unchanged without one.
    public static func libraryPath(_ dyld: [String], sdl directory: URL?) -> [String] {
        guard let directory else { return dyld }
        return [directory.path] + dyld.filter { $0 != directory.path }
    }
}

// MARK: - Force-feedback strength

extension CellarSDL {
    /// The variable Cellar's Fanatec driver reads its cap from (`Shim/sdl/`).
    static let fanatecStrengthVariable = "CELLAR_FFB_MAX_PERCENT"
    /// The variable SDL's own Logitech driver reads its device gain from, 0–65535.
    static let logitechGainVariable = "SDL_HAPTIC_LG4FF_GAIN"

    /// The strengths offered in Settings and accepted by `cellar controllers strength`, in percent.
    public static let strengthChoices = [25, 50, 75, 100]

    /// What a wheel Cellar drives is told about its strength, for a launch. nil — the player has not
    /// chosen — leaves every driver at its own default: Fanatec at `defaultStrengthPercent`,
    /// Logitech at full, since a G29's motor is a fraction of a direct-drive base's.
    public static func strengthEnvironment(_ percent: Int?) -> [String: String] {
        guard let percent else { return [:] }
        let clamped = min(max(percent, 1), 100)
        return [fanatecStrengthVariable: String(clamped),
                logitechGainVariable: String(65535 * clamped / 100)]
    }

    /// Adds `strengthEnvironment` to a launch's environment. A value already there — someone typed
    /// `CELLAR_FFB_MAX_PERCENT=80 cellar launch …` — wins over Settings.
    public static func applyStrength(_ percent: Int?, to env: inout [String: String]) {
        for (key, value) in strengthEnvironment(percent) where env[key]?.isEmpty ?? true {
            env[key] = value
        }
    }

    /// The strength in the player's words, for Settings, the CLI and doctor.
    public static func strengthDescription(_ percent: Int?) -> String {
        guard let percent else {
            return "Cellar's default: Fanatec bases at half strength, Logitech wheels at full strength"
        }
        return "\(min(max(percent, 1), 100))% of the wheel's maximum, for every wheel Cellar drives"
    }
}

extension CellarSettings {
    static let strengthKey = "force_feedback_strength"

    /// The force-feedback strength the player chose for every wheel Cellar drives, in percent; nil
    /// keeps each driver's own default (`CellarSDL.strengthEnvironment`).
    public static var forceFeedbackStrength: Int? {
        BottleConfig.fields(url)[strengthKey].flatMap(Int.init).map { min(max($0, 1), 100) }
    }

    public static func setForceFeedbackStrength(_ percent: Int?) throws {
        if let percent {
            guard (1...100).contains(percent) else {
                throw CellarError.invalidArgument("Force-feedback strength is a percentage from 1 to 100, not \(percent).")
            }
            try BottleConfig.set(key: strengthKey, to: String(percent), section: "controllers", in: url)
        } else {
            try BottleConfig.unset(key: strengthKey, in: url)
        }
    }
}
