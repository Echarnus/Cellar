import CellarDomain
import Foundation

/// The Steam half of `cellar verify`'s baseline: signed in, and online (#203).
///
/// Both are read from what the bottle's Steam wrote during this run, never from what Cellar
/// believes it set up. Steam's `connection_log.txt` records every logon and its result, and
/// `loginusers.vdf` records whether the account was put in offline mode. The IDs are the ones the
/// pre-delivery checklist uses (`signed-in`, `steam-online`).
public enum SteamSessionCheck {
    /// The checks for one run, from the stretch of the connection log this run wrote.
    ///
    /// - `connectionLog`: what Steam added to `connection_log.txt` since the run began.
    /// - `loginUsers`: `config/loginusers.vdf` as it is now.
    /// - `bottleAccount`: the account the bottle's Steam has signed in.
    /// - `playerAccount`: the account the player signed in to Cellar with, if known.
    /// - `launchSteps`: every progress sentence the launch reported, which says when Steam's own
    ///   sign-in window had to be opened.
    static func checks(connectionLog: String, loginUsers: String?, bottleAccount: String?,
                       playerAccount: String?, launchSteps: [String]) -> [VerificationCheck] {
        [signedIn(connectionLog: connectionLog, bottleAccount: bottleAccount, playerAccount: playerAccount,
                  launchSteps: launchSteps),
         online(connectionLog: connectionLog, loginUsers: loginUsers, account: bottleAccount)]
    }

    static let signedInTitle = "Steam is signed in as your account, with no sign-in window"
    static let onlineTitle = "Steam is online, not in offline mode"

    static func signedIn(connectionLog: String, bottleAccount: String?, playerAccount: String?,
                         launchSteps: [String]) -> VerificationCheck {
        let prompts = launchSteps.filter(isSignInPrompt)
        func check(_ verdict: VerificationVerdict, _ detail: String, _ evidence: [String] = []) -> VerificationCheck {
            VerificationCheck(id: "signed-in", title: signedInTitle, verdict: verdict, detail: detail,
                              evidence: evidence + prompts)
        }
        switch SteamClientSession.logonResult(inConnectionLog: connectionLog) {
        case .refused(let reason)?:
            return check(.fail, "Steam refused the sign-in (\(reason)).", logonLines(connectionLog))
        case nil:
            return check(.fail, "Steam never reported signing in during this run.", logonLines(connectionLog))
        case .loggedOn?:
            if !prompts.isEmpty {
                return check(.fail, "Steam signed in, but only after its own sign-in window was opened.")
            }
            if let bottleAccount, let playerAccount, bottleAccount.lowercased() != playerAccount.lowercased() {
                return check(.fail, "Steam signed in as a different account (\(bottleAccount)) from the one you signed in to Cellar with (\(playerAccount)).")
            }
            return check(.pass, "Steam signed in by itself" + (bottleAccount.map { " as \($0)" } ?? "") + ".")
        }
    }

    static func online(connectionLog: String, loginUsers: String?, account: String?) -> VerificationCheck {
        func check(_ verdict: VerificationVerdict, _ detail: String, _ evidence: [String] = []) -> VerificationCheck {
            VerificationCheck(id: "steam-online", title: onlineTitle, verdict: verdict, detail: detail, evidence: evidence)
        }
        if let loginUsers, wantsOfflineMode(loginUsers) {
            return check(.fail, "Steam is set to offline mode for this account (WantsOfflineMode is 1 in loginusers.vdf).")
        }
        guard SteamClientSession.logonResult(inConnectionLog: connectionLog) == .loggedOn else {
            return check(.fail, "Steam never came online: there was no successful logon in its connection log.",
                         logonLines(connectionLog))
        }
        let dropped = disconnectsAfterLastLogon(connectionLog)
        if !dropped.isEmpty {
            return check(.fail, "Steam signed in and then lost its connection while the game ran.", dropped)
        }
        return check(.pass, "Steam logged on to its servers and stayed connected for the whole run.")
    }

    /// Words the launch uses when it has to fall back to Steam's own sign-in window.
    static func isSignInPrompt(_ step: String) -> Bool {
        let lower = step.lowercased()
        return lower.contains("its own window opens") || lower.contains("sign in to steam")
            || lower.contains("sign-in window") || lower.contains("steam guard")
    }

    static func wantsOfflineMode(_ loginUsers: String) -> Bool {
        loginUsers.range(of: #""WantsOfflineMode"\s*"1""#, options: .regularExpression) != nil
    }

    static func logonLines(_ log: String) -> [String] {
        log.split(whereSeparator: \.isNewline).map(String.init)
            .filter { $0.contains("LogOn") || $0.contains("Logon") || $0.contains("Logged") }
            .suffix(10).map { $0 }
    }

    /// Connection losses Steam recorded after its last successful logon.
    static func disconnectsAfterLastLogon(_ log: String) -> [String] {
        let lines = log.split(whereSeparator: \.isNewline).map(String.init)
        guard let last = lines.lastIndex(where: { $0.contains("RecvMsgClientLogOnResponse") && $0.contains("'OK'") }) else {
            return []
        }
        return lines[(last + 1)...].filter { line in
            let lower = line.lowercased()
            return lower.contains("disconnected") || lower.contains("logged off") || lower.contains("logoff")
                || lower.contains("connection lost") || lower.contains("offline")
        }
    }

    // MARK: - From the bottle

    /// How far the bottle's connection log has got, before the run starts.
    public static func mark(in prefix: URL) -> UInt64 { SteamBottle.connectionLogMark(in: prefix) }

    /// The checks, read from the bottle's files as they are now.
    public static func checks(prefix: URL, since mark: UInt64, launchSteps: [String]) -> [VerificationCheck] {
        let logs = SteamBottle.logsDirectory(in: prefix)
        let connectionLog = VerificationLog.text(of: logs.appendingPathComponent("connection_log.txt"), since: mark)
        let loginUsers = try? String(contentsOf: SteamBottle.steamDirectory(in: prefix)
            .appendingPathComponent("config/loginusers.vdf"), encoding: .utf8)
        var player: String?
        if case .signedIn(let account, _, _) = SteamAccount.state { player = account }
        return checks(connectionLog: connectionLog, loginUsers: loginUsers,
                      bottleAccount: SteamBottle.loggedInAccount(in: prefix), playerAccount: player,
                      launchSteps: launchSteps)
    }
}
