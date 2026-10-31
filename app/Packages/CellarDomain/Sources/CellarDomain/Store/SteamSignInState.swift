import Foundation

/// The three states the Accounts screen has to draw, and the only three there are.
public enum SteamSignInState: Sendable, Equatable {
    /// How long a Steam session lasts, roughly: `aging` turns on as one nears the end.
    public static let expectedLifetimeInDays = 200

    /// Nobody has signed in, or the sign-in was forgotten.
    case signedOut
    /// Signed in and usable. `aging` is true once it is old enough to expire soon.
    case signedIn(account: String, days: Int, aging: Bool)
    /// Steam rejected the stored session. The account name is kept, because the fix is to sign
    /// in again *as that person*, and saying who makes that clearer.
    case expired(account: String, reason: String)

    public var isUsable: Bool { if case .signedIn = self { return true }; return false }

    /// The account name, whatever the state — nil only when nobody ever signed in.
    public var accountName: String? {
        switch self {
        case .signedOut:                  return nil
        case .signedIn(let name, _, _):   return name
        case .expired(let name, _):       return name
        }
    }

    /// One sentence saying exactly where things stand. Used verbatim by the CLI and the app so
    /// the two cannot describe the same session differently.
    public var summary: String {
        switch self {
        case .signedOut:
            return String(localized: "Not signed in. One scan with the Steam mobile app covers every Steam game.")
        case .signedIn(let name, let days, let aging):
            let age = days == 0 ? String(localized: "today") : days == 1 ? String(localized: "yesterday") : String(localized: "\(days) days ago")
            return aging
                ? String(localized: "Signed in as \(name) \(age). Steam sessions last about \(Self.expectedLifetimeInDays) days, so this one may ask you to scan again soon.")
                : String(localized: "Signed in as \(name) \(age).")
        case .expired(let name, let reason):
            return String(localized: "Steam ended the session for \(name) (\(reason)). Sign in again — it takes one scan.")
        }
    }
}
