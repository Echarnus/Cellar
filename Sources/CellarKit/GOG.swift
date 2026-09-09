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

/// The tokens GOG hands back, and how long the access token is good for.
struct GOGSession: Codable {
    var accessToken: String
    var refreshToken: String
    var userID: String
    var expiresAt: Date

    /// Refresh a minute early — a token that expires mid-download is a confusing failure.
    var isFresh: Bool { expiresAt.timeIntervalSinceNow > 60 }
}

/// Sign-in state for GOG, persisted as a refresh token in the keychain.
public enum GOGAuth {
    /// One keychain item; the account label is fixed because Cellar models one signed-in player.
    static let keychainAccount = "oauth-session"

    public static var isSignedIn: Bool { storedSession() != nil }

    /// Exchange the authorization code from the sign-in page for a session. Called once per sign-in.
    @discardableResult
    public static func signIn(authorizationCode code: String) throws -> String {
        let response = try Downloader.json("\(GOG.authHost)/token", body: [
            "client_id": GOG.clientID,
            "client_secret": GOG.clientSecret,
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": GOG.redirectURI,
        ])
        let session = try session(from: response)
        try store(session)
        return try username()
    }

    public static func signOut() throws {
        try Keychain.remove(account: keychainAccount, store: .gog)
    }

    /// A valid access token, refreshing transparently. Every API call goes through here, so an
    /// expired session repairs itself instead of surfacing as a 401 the player has to interpret.
    public static func accessToken() throws -> String {
        guard let session = storedSession() else {
            throw CellarError.invalidArgument("Not signed in to GOG. Run: cellar gog login")
        }
        if session.isFresh { return session.accessToken }
        let response = try Downloader.json("\(GOG.authHost)/token", body: [
            "client_id": GOG.clientID,
            "client_secret": GOG.clientSecret,
            "grant_type": "refresh_token",
            "refresh_token": session.refreshToken,
        ])
        let refreshed = try self.session(from: response)
        try store(refreshed)
        return refreshed.accessToken
    }

    /// The signed-in player's GOG username — what the UI shows beside the store.
    public static func username() throws -> String {
        let data = try Downloader.json("\(GOG.embedHost)/userData.json", bearer: try accessToken())
        guard let name = data["username"] as? String, !name.isEmpty else {
            throw CellarError.ioFailure("GOG did not return a username for this session.")
        }
        return name
    }

    /// Cached username, for a UI that must not block or throw while drawing a row.
    public static var cachedUsername: String? {
        UserDefaults.standard.string(forKey: "cellar.gog.username")
    }

    public static func cacheUsername(_ name: String?) {
        let defaults = UserDefaults.standard
        if let name { defaults.set(name, forKey: "cellar.gog.username") }
        else { defaults.removeObject(forKey: "cellar.gog.username") }
    }

    // MARK: - Persistence

    static func storedSession() -> GOGSession? {
        guard let json = Keychain.get(account: keychainAccount, store: .gog),
              let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(GOGSession.self, from: data)
    }

    static func store(_ session: GOGSession) throws {
        let data = try JSONEncoder().encode(session)
        try Keychain.set(String(decoding: data), account: keychainAccount, store: .gog)
    }

    static func session(from response: [String: Any]) throws -> GOGSession {
        guard let access = response["access_token"] as? String,
              let refresh = response["refresh_token"] as? String else {
            throw CellarError.ioFailure(
                "GOG did not return a sign-in token. If you were signed in before, sign in again: cellar gog login")
        }
        let expires = (response["expires_in"] as? Double) ?? 3600
        let userID = (response["user_id"] as? String) ?? (response["user_id"] as? Int).map(String.init) ?? ""
        return GOGSession(accessToken: access, refreshToken: refresh, userID: userID,
                          expiresAt: Date().addingTimeInterval(expires))
    }
}

extension String {
    init(decoding data: Data) { self = String(data: data, encoding: .utf8) ?? "" }
}
