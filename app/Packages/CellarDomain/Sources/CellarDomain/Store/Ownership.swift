import Foundation

/// **Your games, not Cellar's catalogue.**
///
/// Cellar ships a profile per supported game, and it used to show all of them to everybody — so the
/// library was a list of what *somebody's* Mac could run, with Install buttons that could only ever
/// fail for a game you don't own. One rule replaces that: a game is listed when the store it comes
/// from says this account may have it.
///
/// The rule lives here, once, so `cellar library` and the app cannot drift apart.
public enum Ownership: Sendable, Equatable, Codable {
    /// The store confirmed it: this account can install and play it.
    case owned
    /// The store answered, and the answer was no.
    case notOwned
    /// Nobody asked yet, or the question could not be answered. **Never** rendered as "you don't
    /// own this" — an unanswered question is not a no.
    case unknown(String)

    public var isOwned: Bool { self == .owned }

    private enum CodingKeys: String, CodingKey { case state, reason }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(String.self, forKey: .state) {
        case "owned":    self = .owned
        case "notOwned": self = .notOwned
        default:         self = .unknown(try c.decodeIfPresent(String.self, forKey: .reason) ?? "not checked")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .owned:    try c.encode("owned", forKey: .state)
        case .notOwned: try c.encode("notOwned", forKey: .state)
        case .unknown(let why):
            try c.encode("unknown", forKey: .state)
            try c.encode(why, forKey: .reason)
        }
    }
}
