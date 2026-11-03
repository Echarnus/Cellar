import CellarDomain
import Foundation

/// **The player's Steam library, as Steam itself lists it** (#288).
///
/// Asking DepotDownloader game by game answers "may this account download it", which is not the same
/// question: for a free-to-play game the tool asks Steam for a free licence first, Steam hands one
/// out, and the game reads as owned (and the licence lands on the account). Steam's own
/// `IPlayerService/GetOwnedGames` answers the library question directly: paid games, plus free games
/// the player has actually played, and *not* free licences nobody used (`include_free_sub=false`).
///
/// It is authorised with the session the player already gave Cellar: the refresh token is traded
/// for a short-lived access token (`IAuthenticationService/GenerateAccessTokenForApp`), both sent as
/// a form body over curl's stdin (`Downloader.json`), so neither reaches an argument list or a log.
/// The access token lives only for this call.
public enum SteamOwnedGames {

    static let tokenURL = "https://api.steampowered.com/IAuthenticationService/GenerateAccessTokenForApp/v1/"
    static let ownedURL = "https://api.steampowered.com/IPlayerService/GetOwnedGames/v1/"

    /// The app ids in the signed-in player's library, or nil when Steam couldn't be asked. Nil is
    /// never "owns nothing": the caller falls back to asking game by game.
    public static func appIDs(account: String) -> Set<Int>? {
        guard let refresh = DepotTool.refreshToken(for: account),
              let steamID = SteamClientSession.claims(ofToken: refresh)?.steamID else { return nil }
        do {
            let token = try accessToken(Downloader.json(tokenURL, body: tokenForm(refresh: refresh, steamID: steamID)))
            guard let token else { return nil }
            return appIDs(inResponse: try Downloader.json(ownedURL, body: ownedForm(access: token, steamID: steamID)))
        } catch {
            // The message names a host and a status, never a token (Downloader.json).
            CellarLog.info(.account, "Steam's library list didn't answer: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Requests and answers, kept pure so they are tested without Steam

    static func tokenForm(refresh: String, steamID: String) -> [String: String] {
        ["refresh_token": refresh, "steamid": steamID]
    }

    static func ownedForm(access: String, steamID: String) -> [String: String] {
        ["access_token": access, "steamid": steamID,
         // Free games count once they've been played; a free licence nobody used does not.
         "include_played_free_games": "true", "include_free_sub": "false",
         "include_appinfo": "false", "skip_unvetted_apps": "false"]
    }

    static func accessToken(_ response: [String: Any]) -> String? {
        guard let token = (response["response"] as? [String: Any])?["access_token"] as? String,
              !token.isEmpty else { return nil }
        return token
    }

    /// The app ids in a `GetOwnedGames` answer. Steam answers a request it won't serve with an empty
    /// `response`, which is "couldn't ask", not "owns nothing" — only a `game_count` makes it a list.
    static func appIDs(inResponse response: [String: Any]) -> Set<Int>? {
        guard let body = response["response"] as? [String: Any], body["game_count"] != nil else { return nil }
        let games = body["games"] as? [[String: Any]] ?? []
        return Set(games.compactMap { ($0["appid"] as? Int) ?? ($0["appid"] as? NSNumber)?.intValue })
    }

    /// Every profile's answer, from the library: in it is owned, not in it is not.
    static func answers(for appIDs: Set<Int>, library: Set<Int>) -> [String: Ownership] {
        Dictionary(uniqueKeysWithValues: appIDs.map { ("\($0)", library.contains($0) ? Ownership.owned : .notOwned) })
    }
}
