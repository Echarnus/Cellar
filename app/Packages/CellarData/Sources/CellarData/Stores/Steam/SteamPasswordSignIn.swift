import Foundation

/// Signing in to Steam with an account name and password — for the players the QR code can't serve.
///
/// The QR sign-in needs the Steam mobile app on a phone, signed in to the account. Steam itself does
/// not: a player can sign in with a name and a password and then, depending on how the account is
/// protected, type a code Steam emailed them, type the code from the Steam app's authenticator, or
/// nothing at all (an account with Steam Guard off). This type covers those routes.
///
/// DepotDownloader does the talking to Steam (`IAuthenticationService/BeginAuthSessionViaCredentials`,
/// password RSA-encrypted to Steam's key). Cellar's part is the conversation: it hands the password
/// and each code to the tool **on its stdin** — never on a command line, which every process on the
/// Mac can read with `ps` — and reads the tool's questions back out of its output. Afterwards only
/// Steam's session token is kept, exactly as after a QR sign-in (`SteamTokenVault`); the password is
/// never written anywhere.
public enum SteamPasswordSignIn {

    // MARK: - What DepotDownloader asks

    /// A question DepotDownloader 3.4.0 prints and then waits on stdin for. Each is printed with
    /// `Console.Write`, so it arrives *without* a line ending — the reader has to look at the
    /// unfinished tail of the output, not only at whole lines.
    public enum Prompt: Equatable, Sendable {
        /// `Enter account password for "name": ` — no stored session for that name.
        case password
        /// Steam Guard by email. `hint` is what Steam says about the address (its domain), if anything.
        case emailCode(hint: String?)
        /// The rolling code from the Steam app's authenticator.
        case authenticatorCode
    }

    /// The question at the end of `text`, if it ends in one.
    ///
    /// Two spellings of each code prompt: SteamKit's authenticator (`STEAM GUARD! Please enter…`,
    /// used during the credentials auth session) and DepotDownloader's own older logon fallback
    /// (`Please enter the authentication code sent to your email address: `).
    public static func prompt(in text: String) -> Prompt? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasSuffix(":") else { return nil }
        if trimmed.hasPrefix("Enter account password for") { return .password }
        if trimmed.contains("auth code from your authenticator app")
            || trimmed.contains("2 factor auth code from your authenticator app") {
            return .authenticatorCode
        }
        if let range = trimmed.range(of: "auth code sent to the email at ") {
            let hint = trimmed[range.upperBound...].dropLast().trimmingCharacters(in: .whitespaces)
            return .emailCode(hint: hint.isEmpty ? nil : hint)
        }
        if trimmed.contains("authentication code sent to your email address") { return .emailCode(hint: nil) }
        return nil
    }

    /// SteamKit says this before asking again, when the code just sent was refused.
    public static func saysCodeWasWrong(_ line: String) -> Bool {
        line.contains("auth code you have provided is incorrect")
    }

    // MARK: - How it ended

    /// Why a sign-in did not complete, in terms the player can act on.
    public enum Failure: Equatable, Sendable {
        /// Steam refused the account name and password (`InvalidPassword`). Steam does not say
        /// which of the two was wrong, and neither does Cellar.
        case wrongPassword
        /// Steam is refusing sign-ins for a while (`RateLimitExceeded`, `AccountLoginDeniedThrottle`).
        case tooManyAttempts
        /// The player stopped answering — closed the form, or left a code empty.
        case cancelled
        /// Anything else, with Steam's own word for it.
        case other(String)
    }

    /// The failure a line of DepotDownloader output reports, if it reports one.
    ///
    /// `Failed to authenticate with Steam: Authentication failed with result InvalidPassword.` is
    /// SteamKit's `AuthenticationException` text; `Unable to login to Steam3: …` is the logon
    /// itself failing after the auth session.
    public static func failure(in line: String) -> Failure? {
        let failed = line.contains("Failed to authenticate with Steam") || line.contains("Unable to login to Steam3")
        guard failed else { return nil }
        if line.contains("InvalidPassword") { return .wrongPassword }
        if line.contains("RateLimitExceeded") || line.contains("Throttle") { return .tooManyAttempts }
        let why = line.components(separatedBy: "result ").last.map {
            $0.trimmingCharacters(in: CharacterSet(charactersIn: " .:"))
        } ?? ""
        if line.contains("Unable to login to Steam3"), let colon = line.lastIndex(of: ":") {
            return .other(line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces))
        }
        return .other(why.isEmpty ? "unknown" : why)
    }

    // MARK: - The conversation

    /// One sign-in's side of the conversation with DepotDownloader, apart from the process so it can
    /// be tested line by line.
    ///
    /// The password is answered exactly once. A second password prompt means the first was refused
    /// before Steam said why, and typing it again would only spend the player's attempts — so the
    /// conversation stops there and reports a wrong password.
    public struct Conversation {
        private let password: String
        private var passwordSent = false
        private var lastCodeWasWrong = false
        public private(set) var failure: Failure?
        public private(set) var established = false

        public init(password: String) { self.password = password }

        /// Take in one whole line of output.
        public mutating func read(_ line: String) {
            if SteamPasswordSignIn.saysCodeWasWrong(line) { lastCodeWasWrong = true }
            if failure == nil, let failed = SteamPasswordSignIn.failure(in: line) { failure = failed }
            if SteamAccount.isSessionEstablished(line) { established = true }
        }

        /// What to type in answer to `prompt`, or nil to stop the sign-in. `askForCode` is asked
        /// for each Steam Guard code, told whether the previous one was refused.
        public mutating func answer(_ prompt: Prompt,
                                    askForCode: (SteamSignInRequest) -> String?) -> String? {
            switch prompt {
            case .password:
                guard !passwordSent else { failure = .wrongPassword; return nil }
                passwordSent = true
                return password
            case .emailCode(let hint):
                return code(askForCode(.emailCode(hint: hint, retry: takeWrongCode())))
            case .authenticatorCode:
                return code(askForCode(.authenticatorCode(retry: takeWrongCode())))
            }
        }

        private mutating func takeWrongCode() -> Bool {
            defer { lastCodeWasWrong = false }
            return lastCodeWasWrong
        }

        /// A code as typed — spaces and dashes are how people copy one out of an email.
        private mutating func code(_ typed: String?) -> String? {
            let cleaned = typed.map { $0.filter { !$0.isWhitespace && $0 != "-" } } ?? ""
            guard !cleaned.isEmpty else { failure = failure ?? .cancelled; return nil }
            return cleaned
        }
    }
}

extension SteamPasswordSignIn.Failure {
    /// The CLI's line for this failure — and the app reads it back with `init(sentence:)`.
    public var sentence: String {
        switch self {
        case .wrongPassword: return Self.wrongPasswordLine
        case .tooManyAttempts: return Self.tooManyLine
        case .cancelled: return Self.cancelledLine
        case .other(let why): return Self.otherLead + why + ")."
        }
    }

    static let wrongPasswordLine = "Steam didn't accept that account name and password."
    static let tooManyLine = "Steam has seen too many sign-in attempts. Wait a few minutes, then try again."
    static let cancelledLine = "Sign-in stopped before Steam got a code."
    static let otherLead = "Steam didn't sign you in ("

    public init?(sentence line: String) {
        let text = line.trimmingCharacters(in: .whitespaces)
        switch text {
        case Self.wrongPasswordLine: self = .wrongPassword
        case Self.tooManyLine: self = .tooManyAttempts
        case Self.cancelledLine: self = .cancelled
        default:
            guard text.hasPrefix(Self.otherLead), text.hasSuffix(").") else { return nil }
            self = .other(String(text.dropFirst(Self.otherLead.count).dropLast(2)))
        }
    }
}
