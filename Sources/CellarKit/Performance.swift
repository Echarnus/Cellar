import Foundation

/// The performance switches a player can flip per game without editing a profile. Each is a plain
/// scalar key, so it reads the same in a profile (the game's default) and in a bottle's
/// `bottle.toml` (the player's choice, which wins). See `PerformanceSettings.resolve`.
public enum PerformanceSetting: String, CaseIterable {
    /// Wine's debug channels. `off` (`WINEDEBUG=-all`) for play; a channel spec such as
    /// `err+all,warn+crypt` only while chasing a bug — tracing costs CPU on every call it logs.
    case wineDebug = "wine_debug"
    /// Metal's API validation layer. Slower (~7% on an M5), but a workaround for D3DMetal races that
    /// crash some games — Planet Coaster 2 turns it on in its profile for that reason.
    case metalValidation = "metal_validation"
    /// Present the NVIDIA identity so the game's DLSS option becomes MetalFX (see `WineRunner.usesMetalFX`).
    case metalFXUpscaling = "metalfx_upscaling"
    /// Metal's performance HUD (FPS / frame time), remembered per game.
    case metalHUD = "metal_hud"

    public var key: String { rawValue }

    public static func named(_ key: String) -> PerformanceSetting? { PerformanceSetting(rawValue: key) }

    var isBool: Bool { self != .wineDebug }

    /// The switch's value as a raw `[env]` block states it, if that block sets its variable.
    func value(fromEnv env: [String: String]) -> String? {
        switch self {
        case .wineDebug:        return env["WINEDEBUG"].map { $0 == "-all" ? "off" : $0 }
        case .metalValidation:  return env["MTL_DEBUG_LAYER"].map { $0 == "0" ? "false" : "true" }
        case .metalHUD:         return env["MTL_HUD_ENABLED"].map { $0 == "0" ? "false" : "true" }
        case .metalFXUpscaling: return nil
        }
    }

    public var defaultValue: String { self == .wineDebug ? "off" : "false" }

    /// One line for `cellar perf`, saying what the switch costs or buys.
    public var summary: String {
        switch self {
        case .wineDebug:        return "Wine debug logging: off, or channels such as err+all (slows the game)"
        case .metalValidation:  return "Metal validation layer: a crash workaround for some games, costs FPS"
        case .metalFXUpscaling: return "MetalFX upscaling through the game's DLSS option (D3DMetal only)"
        case .metalHUD:         return "Metal performance HUD: FPS and frame time on screen"
        }
    }

    /// The canonical spelling of `value`, or an error naming what this setting accepts.
    public func normalise(_ value: String) throws -> String {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        if isBool {
            switch trimmed.lowercased() {
            case "true", "on", "yes", "1":  return "true"
            case "false", "off", "no", "0": return "false"
            default:
                throw CellarError.invalidArgument("\(key) is on or off, not '\(value)'.")
            }
        }
        if ["off", "-all"].contains(trimmed.lowercased()) { return "off" }
        // Written into a TOML line between quotes, and read back by scanners that cut at " #".
        guard !value.isEmpty, !value.contains(where: { $0.isWhitespace || $0 == "\"" || $0 == "#" }) else {
            throw CellarError.invalidArgument(
                "\(key) is off, or Wine debug channels such as err+all,warn+crypt — not '\(value)'.")
        }
        return value
    }
}

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
            for (key, value) in raw { env[key] = value }
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
        return Resolved(env: env, entries: entries)
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
        }
    }
}

/// A bottle's `bottle.toml`: the player's own per-game settings, which no profile update touches.
public enum BottleConfig {
    public static func url(forBottle name: String) -> URL {
        Paths.prefixes.appendingPathComponent(name, isDirectory: true).appendingPathComponent("bottle.toml")
    }

    public static func fields(_ url: URL) -> [String: String] { PrefixManager.readBottleConfig(url) }

    public static func env(_ url: URL) -> [String: String] { ProfileStore.env(at: url) }

    /// Writes `key = "value"` in place of an existing line, or under `[performance]` (created at the
    /// end of the file if missing). Every other line, comment included, is left as it was.
    public static func set(_ setting: PerformanceSetting, to value: String, in url: URL) throws {
        let normalised = try setting.normalise(value)
        let line = "\(setting.key) = \"\(normalised)\""
        var lines = readLines(url)
        if let index = lines.firstIndex(where: { isLine($0, for: setting) }) {
            lines[index] = line
        } else if let header = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "[performance]" }) {
            lines.insert(line, at: header + 1)
        } else {
            while lines.last?.trimmingCharacters(in: .whitespaces).isEmpty == true { lines.removeLast() }
            lines += lines.isEmpty ? ["[performance]", line] : ["", "[performance]", line]
        }
        try write(lines, to: url)
    }

    public static func unset(_ setting: PerformanceSetting, in url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let lines = readLines(url)
        let kept = lines.filter { !isLine($0, for: setting) }
        guard kept.count != lines.count else { return }
        try write(kept, to: url)
    }

    private static func isLine(_ line: String, for setting: PerformanceSetting) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.hasPrefix("#"), let eq = trimmed.firstIndex(of: "=") else { return false }
        return trimmed[..<eq].trimmingCharacters(in: .whitespaces) == setting.key
    }

    private static func readLines(_ url: URL) -> [String] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        var lines = text.components(separatedBy: "\n")
        if lines.last == "" { lines.removeLast() }
        return lines
    }

    private static func write(_ lines: [String], to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try (lines.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
    }
}
