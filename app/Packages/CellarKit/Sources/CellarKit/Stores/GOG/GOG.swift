import CellarDomain
import Foundation

/// GOG.com — the store where OAuth actually buys something.
///
/// Steam and Battle.net both answer "how do I install this?" with *their own client, inside the
/// bottle*: a 1.4 GB download, a window the player has to drive, and a session the game needs at
/// runtime. GOG answers it with an HTTP API and a token. Its catalogue is DRM-free by policy, so
/// there is no client in the bottle, no live session to keep alive, and nothing to keep silent —
/// Cellar downloads the installer the player owns, runs it, and launches the exe.
///
/// That makes GOG the only store where "sign in once, then play anything" is honestly achievable,
/// which is why it exists here. See docs/LEGAL.md: these are the published Galaxy endpoints, used to
/// authenticate as the player and fetch games they own. Nothing is circumvented and nothing is
/// bundled.
public enum GOG {
    // GOG Galaxy's own OAuth client. Public knowledge — it ships in the client and is what every
    // third-party GOG integration (Heroic, Lutris, gogdl) authenticates with. GOG runs no
    // registration portal for third-party apps, so there is no per-app id to obtain instead.
    static let clientID = "46899977096215655"
    static let clientSecret = "9d85c43b1482497dbbce61f6e4aa173a433796eeae2ca8c5f6129f2dc4de46d9"
    static let redirectURI = "https://embed.gog.com/on_login_success?origin=client"

    static let authHost = "https://auth.gog.com"
    static let embedHost = "https://embed.gog.com"
    static let apiHost = "https://api.gog.com"

    /// Where the player signs in. The flow ends by redirecting to `redirectURI` with `?code=…`;
    /// there is no custom URL scheme, so whoever drives this watches for that navigation (the app
    /// uses a WKWebView window) or has the player paste the code (the CLI).
    public static var authorizationURL: URL {
        var components = URLComponents(string: "\(authHost)/auth")!
        components.queryItems = [
            .init(name: "client_id", value: clientID),
            .init(name: "redirect_uri", value: redirectURI),
            .init(name: "response_type", value: "code"),
            .init(name: "layout", value: "client2"),
        ]
        return components.url!
    }

    /// Pull the `code` out of the URL the sign-in page finally lands on. Accepts a bare code too, so
    /// a player who copied only the interesting part of a long URL is not told they got it wrong.
    public static func authorizationCode(from text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let components = URLComponents(string: trimmed),
           let code = components.queryItems?.first(where: { $0.name == "code" })?.value, !code.isEmpty {
            return code
        }
        // A bare code: GOG's are long, alphanumeric and contain no spaces or slashes.
        let looksLikeACode = trimmed.count > 20 && trimmed.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" }
        return looksLikeACode ? trimmed : nil
    }
}
