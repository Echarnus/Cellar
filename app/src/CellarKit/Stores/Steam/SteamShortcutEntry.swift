import CellarDomain
import Foundation

public struct SteamShortcutEntry {
    public let appName: String
    public let exe: String           // path to the inner .app launcher, wrapped in literal quotes
    public let startDir: String      // its directory, wrapped in literal quotes
    public let icon: String
    public let launchOptions: String

    /// Build an entry that points Steam at a generated .app's inner launcher (so Steam tracks
    /// the process correctly for Play/Stop and current-session playtime).
    public init(appName: String, launcherBinary: URL, icon: String = "", launchOptions: String = "") {
        self.appName = appName
        self.exe = "\"\(launcherBinary.path)\""
        self.startDir = "\"\(launcherBinary.deletingLastPathComponent().path)/\""
        self.icon = icon
        self.launchOptions = launchOptions
    }
}
