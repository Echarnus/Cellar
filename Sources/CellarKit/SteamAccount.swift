import Foundation

/// **The** Steam sign-in. One account, one credential, one place.
///
/// Cellar used to ask for Steam three times: once inside each bottle's Windows client, once for the
/// download session, and once more for a Web API key so it could list what you own. Three prompts
/// for one account is not a security boundary, it is a bug in the story — so there is now exactly
/// one: Steam's own device-authorization flow (the QR the real client shows), run once, from
/// Settings. Everything Cellar does with Steam afterwards — checking what you own, downloading it,
/// installing it — reuses that one session silently.
///
/// The token itself is never Cellar's to hold: DepotDownloader obtains it from Steam and keeps it
/// in its own account store. Cellar records only *who* signed in and *when*, so the Accounts screen
/// can say something true without keeping a second copy of a credential.
public enum SteamAccount {

    // MARK: - What Cellar knows

    /// The sign-in as Cellar recorded it. Deliberately not a credential: an account name and two
    /// dates. The token lives in DepotDownloader's store, and nowhere else.
    public struct SignIn: Codable, Sendable {
        public var accountName: String
        public var signedInAt: Date
        /// Set when Steam last *rejected* this session (expired, revoked, password changed). Its
        /// presence is the difference between "signed in" and "was signed in" — see `State`.
        public var rejectedAt: Date?
        public var rejectionReason: String?
        /// The last time the session was known to work. **Not** what age is measured from: a Steam
        /// refresh token's life runs from when it was issued, not from when it was last used, so
        /// using this for `ageInDays` would quietly under-report how close a session is to ending.
        /// Kept because "last worked on 3 September" is the useful thing to know when one fails.
        public var lastUsedAt: Date?

        public var isRejected: Bool { rejectedAt != nil }

        /// Days since the sign-in was established. Steam's refresh tokens are long-lived but not
        /// eternal (about 200 days for a device-flow login, and Steam may end one early), so age is
        /// the only honest thing Cellar can say about expiry: it cannot read the token, so it never
        /// prints a countdown to a date it does not know.
        public var ageInDays: Int {
            max(0, Calendar.current.dateComponents([.day], from: signedInAt, to: Date()).day ?? 0)
        }

        /// True once the sign-in is old enough that a re-scan is plausible at any time. Not a
        /// prediction — a heads-up, so an expiry lands as "as expected" rather than as a failure.
        public var isAging: Bool { ageInDays >= SteamAccount.agingAfterDays }
    }

    /// Steam sessions of this kind last roughly 200 days. Cellar starts mentioning it at 180 —
    /// early enough to be a warning, late enough not to be noise.
    public static let expectedLifetimeInDays = 200
    static let agingAfterDays = 180

    /// The three states the Accounts screen has to draw, and the only three there are.
    public enum State: Sendable, Equatable {
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
                return "Not signed in. One scan with the Steam mobile app covers every Steam game."
            case .signedIn(let name, let days, let aging):
                let age = days == 0 ? "today" : days == 1 ? "yesterday" : "\(days) days ago"
                return aging
                    ? "Signed in as \(name) \(age). Steam sessions last about \(expectedLifetimeInDays) days, so this one may ask you to scan again soon."
                    : "Signed in as \(name) \(age)."
            case .expired(let name, let reason):
                return "Steam ended the session for \(name) (\(reason)). Sign in again — it takes one scan."
            }
        }
    }

    // MARK: - Reading and writing the record

    /// Beside the shared Steam install, not inside a bottle: the sign-in belongs to the account.
    static var recordFile: URL { Paths.shared.appendingPathComponent("steam-account.json") }

    public static var record: SignIn? {
        guard let data = try? Data(contentsOf: recordFile) else { return nil }
        return try? JSONDecoder.cellar.decode(SignIn.self, from: data)
    }

    static func write(_ signIn: SignIn?) {
        guard let signIn else { try? FileManager.default.removeItem(at: recordFile); return }
        try? FileManager.default.createDirectory(at: Paths.shared, withIntermediateDirectories: true)
        try? JSONEncoder.cellar.encode(signIn).write(to: recordFile, options: .atomic)
    }

    /// The current state, read from disk.
    ///
    /// A record without a token store is *not* a sign-in: the two go out of step if somebody
    /// deletes Cellar's tools directory, and claiming a session Cellar cannot use would be exactly
    /// the kind of unverified ✓ this project refuses to draw.
    public static var state: State {
        guard let record, DepotTool.hasStoredSession else { return .signedOut }
        if record.isRejected {
            return .expired(account: record.accountName, reason: record.rejectionReason ?? "session ended")
        }
        return .signedIn(account: record.accountName, days: record.ageInDays, aging: record.isAging)
    }

    public static var isSignedIn: Bool { state.isUsable }

    /// How to authenticate the next DepotDownloader run, or nil when nobody is signed in.
    public static var credentials: DepotTool.Credentials? {
        guard case .signedIn(let account, _, _) = state else { return nil }
        return .session(username: account)
    }

    // MARK: - Signing in

    /// Sign in by QR — the only sign-in Cellar asks for.
    ///
    /// `output` receives DepotDownloader's lines as they arrive, which is how the app turns the
    /// drawn challenge into a scannable code. The account name comes from the tool's own success
    /// line; capturing it is what makes every *later* run silent, because a stored token can only
    /// be looked up by the username it was stored under.
    @discardableResult
    public static func signIn(output: ((String) -> Void)? = nil) throws -> State {
        var captured: String?
        try DepotTool.signIn(credentials: .qr) { line in
            if let name = accountName(inSuccessLine: line) { captured = name }
            output?(line)
        }
        guard let captured else {
            // No success line: the scan was never completed, or Steam refused. Leave any previous
            // record alone — a failed attempt is not a sign-out.
            return state
        }
        write(SignIn(accountName: captured, signedInAt: Date(), lastUsedAt: Date()))
        return state
    }

    /// DepotDownloader announces a completed device login with:
    ///   `Success! Next time you can login with -username kennethdc -remember-password instead of -qr.`
    /// That line is the only place the account name appears, so it is parsed rather than guessed.
    public static func accountName(inSuccessLine line: String) -> String? {
        guard line.contains("-username") else { return nil }
        let parts = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard let i = parts.firstIndex(of: "-username"), i + 1 < parts.count else { return nil }
        let name = parts[i + 1].trimmingCharacters(in: CharacterSet(charactersIn: "'\"`.,"))
        return name.isEmpty ? nil : name
    }

    /// Sign out: forget the token *and* the record. Both, always — a record left behind would show
    /// an account nobody can use, and a token left behind would be a credential the player believes
    /// they removed.
    public static func signOut() throws {
        try DepotTool.forgetSession()
        write(nil)
    }

    // MARK: - Expiry, learned the only way it can be

    /// Cellar cannot read the token, so it cannot read its expiry date. What it *can* do is notice
    /// the moment Steam refuses it — DepotDownloader prints `Access token was rejected (Expired).`
    /// — and turn that into a state the player can act on, instead of a failed download.
    ///
    /// Called with every line of every DepotDownloader run.
    public static func note(_ line: String) {
        if let reason = rejection(in: line) {
            guard var record else { return }
            record.rejectedAt = Date()
            record.rejectionReason = reason
            write(record)
        }
    }

    public static func rejection(in line: String) -> String? {
        guard line.contains("Access token was rejected") else { return nil }
        // `Access token was rejected (Expired).` — keep Steam's own word for it.
        if let open = line.firstIndex(of: "("), let close = line[open...].firstIndex(of: ")") {
            let reason = String(line[line.index(after: open)..<close]).lowercased()
            return reason.isEmpty ? "session ended" : reason
        }
        return "session ended"
    }

    /// Record that the session just worked. Cheap, and it keeps "signed in N days ago" measured
    /// from something real rather than from the sign-in that may have been renewed since.
    public static func noteSuccess() {
        guard var record, !record.isRejected else { return }
        record.lastUsedAt = Date()
        write(record)
    }
}

extension JSONEncoder {
    static let cellar: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()
}

extension JSONDecoder {
    static let cellar: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}
