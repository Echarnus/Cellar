import CellarDomain
import Foundation

/// The performance switches a player can flip per game without editing a profile. Each is a plain
/// scalar key, so it reads the same in a profile (the game's default) and in a bottle's
/// `bottle.toml` (the player's choice, which wins). See `PerformanceSettings.resolve`.
public enum PerformanceSetting: String, CaseIterable, Sendable {
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
    /// Wine's Retina mode (`HKCU\Software\Wine\Mac Driver\RetinaMode`): the game renders at the
    /// display's full pixel density. Sharper, and a heavy cost — four times the pixels on most Macs.
    case retina = "retina"

    public var key: String { rawValue }

    public static func named(_ key: String) -> PerformanceSetting? { PerformanceSetting(rawValue: key) }

    var isBool: Bool { self != .wineDebug }

    /// The variable a raw `[env]` block would use for the same switch, if it has one.
    public var environmentVariable: String? {
        switch self {
        case .wineDebug:        return "WINEDEBUG"
        case .metalValidation:  return "MTL_DEBUG_LAYER"
        case .metalHUD:         return "MTL_HUD_ENABLED"
        case .metalFXUpscaling, .retina: return nil
        }
    }

    /// The switch's value as a raw `[env]` block states it, if that block sets its variable.
    func value(fromEnv env: [String: String]) -> String? {
        switch self {
        case .wineDebug:        return env["WINEDEBUG"].map { $0 == "-all" ? "off" : $0 }
        case .metalValidation:  return env["MTL_DEBUG_LAYER"].map { $0 == "0" ? "false" : "true" }
        case .metalHUD:         return env["MTL_HUD_ENABLED"].map { $0 == "0" ? "false" : "true" }
        case .metalFXUpscaling, .retina: return nil
        }
    }

    public var defaultValue: String { self == .wineDebug ? "off" : "false" }

    /// One line for `cellar perf`, saying what the switch costs or buys.
    public var summary: String {
        switch self {
        case .wineDebug:        return "Wine debug logging: off, or channels such as err+all (slows the game)"
        case .metalValidation:  return "Metal validation layer: a crash workaround for some games, costs FPS"
        case .metalFXUpscaling: return "MetalFX upscaling through the game's DLSS option (D3DMetal only)"
        case .metalHUD:         return "Metal performance HUD for this game (the app's overlay setting adds it to every game)"
        case .retina:           return "Retina mode: render at the display's full resolution (sharper, much slower)"
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
