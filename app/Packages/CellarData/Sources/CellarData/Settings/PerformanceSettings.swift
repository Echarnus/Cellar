import CellarDomain
import Foundation

public enum PerformanceSettings {
    public enum Source: String { case cellarDefault = "default", profile, bottle }

    public struct Entry: Equatable {
        public let setting: PerformanceSetting
        public let value: String
        public let source: Source
    }

    public struct Resolved {
        /// The game's environment from the profile and bottle layers, on top of the runner's own.
        public let env: [String: String]
        public let entries: [Entry]
        /// Crash workarounds the profile turns on and the player's bottle switched off — the
        /// settings a launch that dies as it starts puts back (`GamePlan.launchEnvWithWorkarounds`).
        public var crashWorkaroundsSwitchedOff: [PerformanceSetting] = []
        /// Crash workarounds the profile turns on, whatever the bottle says — what the app warns
        /// about beside the switch.
        public var crashWorkaroundsInProfile: [PerformanceSetting] = []

        public func value(_ setting: PerformanceSetting) -> String {
            entries.first { $0.setting == setting }?.value ?? setting.defaultValue
        }
        public var metalFXUpscaling: Bool { value(.metalFXUpscaling) == "true" }
        public var metalHUD: Bool { value(.metalHUD) == "true" }
    }

    /// Layers, later wins: Cellar's default → the profile's switches → the profile's `[env]` → the
    /// bottle's switches → the bottle's `[env]`. The bottle beats the profile outright, so a player
    /// can turn off what a profile (or a hand-edited copy of one) turned on; within a layer, a raw
    /// `[env]` variable is the more specific statement and wins over that layer's switch.
    public static func resolve(profileFields: [String: String], profileEnv: [String: String],
                               bottleFields: [String: String], bottleEnv: [String: String]) -> Resolved {
        var env = ["WINEDEBUG": "-all"]
        var values: [PerformanceSetting: (String, Source)] = [:]
        for (fields, raw, source) in [(profileFields, profileEnv, Source.profile),
                                      (bottleFields, bottleEnv, Source.bottle)] {
            for setting in PerformanceSetting.allCases {
                // A value that doesn't parse is ignored rather than fatal: the earlier layer stands.
                guard let given = fields[setting.key], let value = try? setting.normalise(given) else { continue }
                values[setting] = (value, source)
                apply(setting, value, to: &env)
            }
            for (key, value) in raw {
                // Merged, never replaced: a bottle's DLL override must not drop the profile's.
                if key == "WINEDLLOVERRIDES", let earlier = env[key], !earlier.isEmpty {
                    env[key] = earlier + ";" + value
                } else {
                    env[key] = value
                }
            }
            // A raw variable is the same switch spelled differently: report what the game will get,
            // not what the typed key said — a hand-edited profile's `WINEDEBUG` must show up here.
            for setting in PerformanceSetting.allCases {
                if let value = setting.value(fromEnv: raw) { values[setting] = (value, source) }
            }
        }
        let entries = PerformanceSetting.allCases.map { setting in
            let (value, source) = values[setting] ?? (setting.defaultValue, .cellarDefault)
            return Entry(setting: setting, value: value, source: source)
        }
        var resolved = Resolved(env: env, entries: entries)
        let inProfile = PerformanceSetting.allCases.filter {
            $0.isCrashWorkaround && profileValue($0, fields: profileFields, env: profileEnv) == "true"
        }
        resolved.crashWorkaroundsInProfile = inProfile
        resolved.crashWorkaroundsSwitchedOff = entries.filter { entry in
            inProfile.contains(entry.setting) && entry.source == .bottle && entry.value == "false"
                // Only the switch: a raw variable in the bottle's [env] was typed by hand, on purpose.
                && entry.setting.value(fromEnv: bottleEnv) == nil
        }.map(\.setting)
        return resolved
    }

    /// What the profile alone says about `setting`: its raw `[env]` beats its switch, as above.
    static func profileValue(_ setting: PerformanceSetting, fields: [String: String], env: [String: String]) -> String? {
        if let value = setting.value(fromEnv: env) { return value }
        return fields[setting.key].flatMap { try? setting.normalise($0) }
    }

    private static func apply(_ setting: PerformanceSetting, _ value: String, to env: inout [String: String]) {
        let on = value == "true"
        switch setting {
        case .wineDebug:
            env["WINEDEBUG"] = value == "off" ? "-all" : value
        case .metalValidation:
            env["MTL_DEBUG_LAYER"] = on ? "1" : nil
            env["MTL_DEBUG_LAYER_ERROR_MODE"] = on ? "nslog" : nil
        case .metalHUD:
            env["MTL_HUD_ENABLED"] = on ? "1" : nil
        case .metalFXUpscaling:
            break   // not an env var of its own: WineRunner picks the GPU identity from it
        case .retina:
            break   // a registry value, written before launch (`WineRunner.setRetinaMode`)
        }
    }
}
