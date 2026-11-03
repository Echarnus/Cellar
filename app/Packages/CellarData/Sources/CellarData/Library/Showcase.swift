import CellarDomain
import Foundation

/// Capture-only: with `CELLAR_SHOWCASE=1` the app shows "Cellar" and its own icon wherever it would
/// name the player's accounts or show their Steam picture, so the website's screenshots and video
/// carry nobody's name or face (docs/SHOWCASE.md). It changes what is drawn, never the sign-in.
public enum Showcase {
    /// The name shown in place of every account name.
    public static let accountName = "Cellar"

    public static func isOn(_ environment: [String: String] = ProcessInfo.processInfo.environment) -> Bool {
        environment["CELLAR_SHOWCASE"] == "1"
    }

    /// The same sign-in, under the showcase name.
    public static func masking(_ state: SteamSignInState) -> SteamSignInState {
        switch state {
        case .signedOut:                          return .signedOut
        case .signedIn(_, let days, let aging):   return .signedIn(account: accountName, days: days, aging: aging)
        case .expired(_, let reason):             return .expired(account: accountName, reason: reason)
        }
    }

    /// Any other account name (the Windows Steam client's, GOG's), kept nil when there is none.
    public static func masking(_ name: String?) -> String? { name.map { _ in accountName } }

    /// Cellar's own icon, shown in place of the Steam picture. Nil outside an app bundle.
    public static var picture: URL? { Bundle.main.url(forResource: "AppIcon", withExtension: "icns") }
}
