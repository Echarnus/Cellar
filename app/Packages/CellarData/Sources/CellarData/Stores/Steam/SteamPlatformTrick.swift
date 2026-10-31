import CellarDomain
import Foundation

/// The kaon `steam_dev.cfg` trick: force the *native* macOS Steam client to show Install/Play for
/// Windows-only games. Advanced/opt-in only — it blocks Steam's self-update and can empty games
/// that have a macOS depot. The non-Steam-shortcut path (SteamShortcuts) is preferred.
public enum SteamPlatformTrick {
    public static var cfgPath: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Steam/Steam.AppBundle/Steam/Contents/MacOS/steam_dev.cfg")
    }

    public static var isEnabled: Bool {
        FileManager.default.fileExists(atPath: cfgPath.path)
    }

    public static func enable() throws {
        try FileManager.default.createDirectory(
            at: cfgPath.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "@sSteamCmdForcePlatformType windows\n".write(to: cfgPath, atomically: true, encoding: .utf8)
    }

    public static func disable() throws {
        if FileManager.default.fileExists(atPath: cfgPath.path) {
            try FileManager.default.removeItem(at: cfgPath)
        }
    }
}
