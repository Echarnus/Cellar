import CellarDomain
import Foundation

/// The tokens GOG hands back, and how long the access token is good for.
struct GOGSession: Codable {
    var accessToken: String
    var refreshToken: String
    var userID: String
    var expiresAt: Date

    /// Refresh a minute early — a token that expires mid-download is a confusing failure.
    var isFresh: Bool { expiresAt.timeIntervalSinceNow > 60 }
}
