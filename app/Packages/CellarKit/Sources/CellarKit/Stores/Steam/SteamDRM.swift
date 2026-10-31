import CellarDomain
import Foundation

/// Telling a Steamworks game which app it is when Cellar, not Steam, started it.
///
/// This is not a DRM workaround and does not weaken one. `steam_appid.txt` is Valve's own developer
/// file: `steam_api` reads it to learn the app id, then talks to the **running, signed-in** Steam
/// client, which must hold a licence for that app or the game refuses to start. Cellar downloads
/// games with the player's own credentials and runs their DRM untouched (docs/LEGAL.md).
public enum SteamDRM {
    /// Drop `steam_appid.txt` beside a downloaded game so it can find the live session.
    public static func markAppDirectory(_ directory: URL, appID: Int) {
        try? "\(appID)\n".write(to: directory.appendingPathComponent("steam_appid.txt"),
                                atomically: true, encoding: .utf8)
    }
}
