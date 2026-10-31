import CellarDomain
import Foundation

/// Sign-in state for GOG, persisted as a refresh token in the keychain.
public enum GOGAuth {
    /// One keychain item; the account label is fixed because Cellar models one signed-in player.
    static let keychainAccount = "oauth-session"

    /// Asks the keychain whether the item exists, without reading it. The app checks this to draw
    /// Accounts; reading the token there would copy a secret into the GUI for a yes/no, and — the
    /// item trusting the CLI that wrote it — put a keychain prompt in front of the player for it.
    public static var isSignedIn: Bool { Keychain.contains(account: keychainAccount, store: .gog) }

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

    /// Sign out: the token, and the name Cellar showed beside it. A name left behind would draw
    /// "Signed in as …" for a session that no longer exists.
    public static func signOut() throws {
        try Keychain.remove(account: keychainAccount, store: .gog)
        cacheUsername(nil)
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
    ///
    /// A file both binaries read, not `UserDefaults`: the CLI and the app have different defaults
    /// domains, so a name the CLI learned at sign-in never reached the app — which then fetched it
    /// itself, with the token, in the GUI process. Private (`0600`), because it says whose library
    /// this is.
    public static var cachedUsername: String? {
        guard let text = try? String(contentsOf: usernameFile, encoding: .utf8) else { return nil }
        let name = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }

    public static func cacheUsername(_ name: String?) {
        // The old home of the cache, emptied whichever way this goes, so a sign-out leaves no name.
        UserDefaults.standard.removeObject(forKey: "cellar.gog.username")
        guard let name, !name.isEmpty else {
            try? FileManager.default.removeItem(at: usernameFile)
            return
        }
        try? PrivateFiles.write(Data(name.utf8), to: usernameFile)
    }

    /// Beside Steam's record: both are the account's, not any one game's.
    static var usernameFile: URL { Paths.shared.appendingPathComponent("gog-account") }

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
