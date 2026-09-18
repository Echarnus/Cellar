import Foundation

/// Handing the Windows Steam client in a bottle the session the player already approved in Cellar,
/// so it signs in by itself instead of showing its own login window.
///
/// The client remembers a sign-in the way it does on Windows: the account's refresh token, encrypted
/// with `CryptProtectData` (entropy = the lowercased account name), in `local.vdf` under
/// `ConnectCache/<crc32(lowercased name) in hex>1`. Wine's `CryptProtectData` is deterministic given
/// the Wine user name (`WineDPAPI`), so Cellar writes that entry from DepotDownloader's token, plus
/// the account in `loginusers.vdf`/`config.vdf` and `AutoLoginUser` in the bottle's registry — the
/// same four things a real "Remember me" sign-in leaves behind.
///
/// A token is plaintext for exactly as long as it takes to encrypt it. Nothing here logs it, and no
/// error or result carries it.
public enum SteamClientSession {
    /// What a refresh token says about itself — read from its JWT payload, never verified (Steam does
    /// that). Enough to refuse to seed a token the client could not use.
    struct Claims: Equatable {
        var steamID: String
        var audiences: [String]
        var expires: Date
        /// `per`: whether Steam issued a persistent ("remember me") session.
        var persistent: Bool?

        var isClientToken: Bool { audiences.contains("client") }

        func isUsable(at now: Date = Date()) -> Bool {
            // An hour of margin: a token that dies while the client is starting is no better.
            isClientToken && expires > now.addingTimeInterval(3600) && steamID.hasPrefix("7656119")
        }
    }

    static func claims(ofToken token: String) -> Claims? {
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return nil }
        var payload = parts[1].replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)
        guard let data = Data(base64Encoded: payload),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sub = json["sub"] as? String,
              let exp = (json["exp"] as? NSNumber)?.doubleValue
        else { return nil }
        let audiences = (json["aud"] as? [String]) ?? (json["aud"] as? String).map { [$0] } ?? []
        return Claims(steamID: sub, audiences: audiences, expires: Date(timeIntervalSince1970: exp),
                      persistent: (json["per"] as? NSNumber).map(\.boolValue))
    }

    /// `printf("%x", crc32(lowercased name)) + "1"` — the client's key for an account's token.
    static func connectCacheKey(account: String) -> String {
        String(CRC32.checksum(account.lowercased()), radix: 16) + "1"
    }

    /// The ConnectCache value: the token protected for `wineUser`, as lowercase hex.
    static func protectedToken(_ token: String, account: String, wineUser: String, salt: Data? = nil) -> String? {
        WineDPAPI.protect(Data(token.utf8), user: wineUser, entropy: Data(account.lowercased().utf8), salt: salt)
            .map { $0.map { String(format: "%02x", $0) }.joined() }
    }

    // MARK: - The files

    /// `C:\users\<wine user>\AppData\Local\Steam\local.vdf` — per bottle, unlike the shared install.
    static func localConfig(in prefix: URL, wineUser: String) -> URL {
        prefix.appendingPathComponent("drive_c/users/\(wineUser)/AppData/Local/Steam/local.vdf")
    }

    static func withConnectCache(_ file: TextVDF, account: String, value: String) -> TextVDF {
        var file = file
        file.edit(connectCachePath) {
            $0.set(connectCacheKey(account: account), value)
        }
        return file
    }

    /// The account as the client's own "Remember me" writes it, and the most recent one. An existing
    /// entry keeps its persona name; a new one uses the account name until the client fills it in.
    static func withLoginUser(_ file: TextVDF, steamID: String, account: String, now: Date = Date()) -> TextVDF {
        var file = file
        file.edit(["users"]) { users in
            for i in users.entries.indices where users.entries[i].key != steamID {
                if case .block(var other) = users.entries[i].value {
                    other.set("MostRecent", "0")
                    users.entries[i].value = .block(other)
                }
            }
            users.edit([steamID]) { user in
                user.set("AccountName", account.lowercased())
                if user.string("PersonaName") == nil { user.set("PersonaName", account) }
                user.set("RememberPassword", "1")
                user.set("WantsOfflineMode", "0")
                user.set("SkipOfflineModeWarning", "0")
                user.set("AllowAutoLogin", "1")
                user.set("MostRecent", "1")
                user.set("Timestamp", String(Int(now.timeIntervalSince1970)))
            }
        }
        return file
    }

    static func withAccount(_ file: TextVDF, steamID: String, account: String) -> TextVDF {
        var file = file
        file.edit(["InstallConfigStore", "Software", "Valve", "Steam", "Accounts", account.lowercased()]) {
            $0.set("SteamID", steamID)
        }
        // Otherwise a client that has seen more than one account opens on its account picker.
        file.edit(["InstallConfigStore", "Software", "WebStorage", "Auth"]) {
            $0.set("AlwaysShowUserChooser", "0")
        }
        return file
    }
}

// MARK: - Deciding, handing over, taking back

public extension SteamClientSession {
    /// Whether a bottle's client can sign in without its login window.
    enum Readiness: Equatable, Sendable {
        /// This bottle's client already remembers a session for the account Cellar is signed in to.
        case remembered
        /// Cellar can hand the client the session it holds, before the client starts.
        case canHandOver
        /// It can't, and the client will ask the player itself.
        case unavailable(Unavailable)

        public var signsInByItself: Bool {
            if case .unavailable = self { return false }
            return true
        }

        /// For the diagnostics report: the decision, never an account or a token.
        public var diagnosis: String {
            switch self {
            case .remembered:              return "remembered"
            case .canHandOver:             return "handed over at launch"
            case .unavailable(let reason): return "not handed over (\(reason.rawValue))"
            }
        }
    }

    enum Unavailable: String, Equatable, Sendable {
        /// Cellar holds no usable Steam session.
        case notSignedIn
        /// Cellar's session is not one the client accepts, or it is about to expire.
        case tokenNotForClient
        /// The client is signed in to a different account; Cellar leaves that alone.
        case otherAccount
        /// The bottle has no Wine user folder yet, so there is nowhere to put the session.
        case bottleNotReady
        /// One of Steam's files could not be read, and a file Cellar can't read it won't rewrite.
        case unreadableFiles
        /// The client is running and would overwrite anything written under it.
        case clientRunning
    }

    /// The Wine user whose `CryptProtectData` key the client will use: `GetUserNameA` in a bottle is
    /// the `USER` of the process that started Wine, falling back to the login name as Wine does.
    static func wineUser(environment: [String: String]) -> String {
        environment["USER"].flatMap { $0.isEmpty ? nil : $0 } ?? NSUserName()
    }
}

extension SteamClientSession {
    /// Everything the decision reads, gathered in one place so it can be tested without a disk.
    struct Snapshot {
        var cellarAccount: String?
        var token: String?
        var localConfig: String?
        var loginUsers: String?
        var config: String?
        var hasWineUserFolder: Bool
    }

    static func readiness(_ s: Snapshot, now: Date = Date()) -> Readiness {
        guard let account = s.cellarAccount else { return .unavailable(.notSignedIn) }
        // A missing file is fine — it gets created. One that is there but won't parse is not.
        func unreadable(_ text: String?) -> Bool { text.map { TextVDF.parse($0) == nil } ?? false }
        guard !unreadable(s.localConfig), !unreadable(s.loginUsers), !unreadable(s.config) else {
            return .unavailable(.unreadableFiles)
        }
        let local = s.localConfig.flatMap(TextVDF.parse)
        let users = s.loginUsers.flatMap(TextVDF.parse)
        let knowsAccount = users.map { remembers($0, account: account) } ?? false
        if knowsAccount,
           local?.block(at: connectCachePath)?.string(connectCacheKey(account: account)) != nil {
            return .remembered
        }
        // Someone signed the client in to another account by hand: that is theirs to change.
        if let listed = users?.block("users"), !listed.entries.isEmpty, !knowsAccount {
            return .unavailable(.otherAccount)
        }
        guard let token = s.token, let claims = claims(ofToken: token), claims.isUsable(at: now) else {
            return .unavailable(.tokenNotForClient)
        }
        guard s.hasWineUserFolder else { return .unavailable(.bottleNotReady) }
        return .canHandOver
    }

    static let connectCachePath = ["MachineUserConfigStore", "Software", "Valve", "Steam", "ConnectCache"]

    static func remembers(_ loginUsers: TextVDF, account: String) -> Bool {
        loginUsers.block("users")?.entries.contains { isAccount($0, account) } ?? false
    }

    private static func isAccount(_ entry: TextVDF.Entry, _ account: String) -> Bool {
        guard case .block(let user) = entry.value else { return false }
        return user.string("AccountName")?.caseInsensitiveCompare(account) == .orderedSame
    }

    static func loginUsersFile(steamDirectory: URL) -> URL {
        steamDirectory.appendingPathComponent("config/loginusers.vdf")
    }

    static func configFile(steamDirectory: URL) -> URL {
        steamDirectory.appendingPathComponent("config/config.vdf")
    }

    /// Reads the token too, so the library and the launch decide from the same facts: a session the
    /// client would refuse is never promised on a game's page.
    static func snapshot(prefix: URL, steamDirectory: URL, wineUser: String) -> Snapshot {
        let state = SteamAccount.state
        let account = state.isUsable ? state.accountName : nil
        func read(_ url: URL) -> String? { try? String(contentsOf: url, encoding: .utf8) }
        var isDirectory: ObjCBool = false
        let userFolder = prefix.appendingPathComponent("drive_c/users/\(wineUser)").path
        return Snapshot(
            cellarAccount: account,
            token: account.flatMap(DepotTool.refreshToken(for:)),
            localConfig: read(localConfig(in: prefix, wineUser: wineUser)),
            loginUsers: read(loginUsersFile(steamDirectory: steamDirectory)),
            config: read(configFile(steamDirectory: steamDirectory)),
            hasWineUserFolder: FileManager.default.fileExists(atPath: userFolder, isDirectory: &isDirectory)
                && isDirectory.boolValue)
    }

    /// Write the session into the bottle's `local.vdf` and the shared install's `loginusers.vdf` and
    /// `config.vdf`. The registry half needs Wine and is `SteamBottle`'s. Returns what it decided:
    /// `.canHandOver` means the files are written.
    static func handOver(prefix: URL, steamDirectory: URL, wineUser: String, now: Date = Date()) -> Readiness {
        let s = snapshot(prefix: prefix, steamDirectory: steamDirectory, wineUser: wineUser)
        let decision = readiness(s, now: now)
        guard decision == .canHandOver, let account = s.cellarAccount, let token = s.token,
              let claims = claims(ofToken: token),
              let protected = protectedToken(token, account: account, wineUser: wineUser)
        else { return decision }

        func load(_ text: String?) -> TextVDF { text.flatMap(TextVDF.parse) ?? TextVDF() }
        let writes: [(URL, TextVDF)] = [
            (localConfig(in: prefix, wineUser: wineUser),
             withConnectCache(load(s.localConfig), account: account, value: protected)),
            (loginUsersFile(steamDirectory: steamDirectory),
             withLoginUser(load(s.loginUsers), steamID: claims.steamID, account: account, now: now)),
            (configFile(steamDirectory: steamDirectory),
             withAccount(load(s.config), steamID: claims.steamID, account: account)),
        ]
        do {
            for (url, file) in writes {
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                        withIntermediateDirectories: true)
                try file.text.write(to: url, atomically: true, encoding: .utf8)
            }
        } catch {
            return .unavailable(.unreadableFiles)
        }
        return .canHandOver
    }

    /// Take back a session Steam refused, so the client asks for a sign-in instead of retrying a
    /// dead token — and so `SteamBottle.loggedInAccount` stops naming an account nobody is signed in to.
    static func forget(account: String, prefix: URL, steamDirectory: URL, wineUser: String) {
        let local = localConfig(in: prefix, wineUser: wineUser)
        if let text = try? String(contentsOf: local, encoding: .utf8), var file = TextVDF.parse(text) {
            file.edit(connectCachePath) { cache in
                cache.entries.removeAll { $0.key == connectCacheKey(account: account) }
            }
            try? file.text.write(to: local, atomically: true, encoding: .utf8)
        }
        let users = loginUsersFile(steamDirectory: steamDirectory)
        if let text = try? String(contentsOf: users, encoding: .utf8), var file = TextVDF.parse(text) {
            file.edit(["users"]) { list in list.entries.removeAll { isAccount($0, account) } }
            try? file.text.write(to: users, atomically: true, encoding: .utf8)
        }
    }

    // MARK: - Did Steam take it?

    enum LogonResult: Equatable {
        case loggedOn
        /// Steam's own result name — `AccessDenied`, `Expired`, `InvalidPassword`… Never a token.
        case refused(String)
    }

    /// The last logon Steam recorded in this stretch of `connection_log.txt`.
    static func logonResult(inConnectionLog text: String) -> LogonResult? {
        guard let regex = try? NSRegularExpression(
            pattern: #"RecvMsgClientLogOnResponse\(\) : \[[^\]]*\] '([A-Za-z]+)'"#) else { return nil }
        guard let match = regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).last,
              let result = Range(match.range(at: 1), in: text) else { return nil }
        return text[result] == "OK" ? .loggedOn : .refused(String(text[result]))
    }
}
