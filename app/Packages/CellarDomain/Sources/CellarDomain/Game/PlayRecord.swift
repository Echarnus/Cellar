import Foundation

/// How long, how often and how recently one game was played (`Playtime` keeps them on disk).
public struct PlayRecord: Codable, Sendable, Equatable {
    public var totalSeconds: Int = 0
    public var sessions: Int = 0
    public var lastPlayed: Date?
    /// A session that started and hasn't been closed yet.
    public var openSince: Date?

    public init(totalSeconds: Int = 0, sessions: Int = 0, lastPlayed: Date? = nil, openSince: Date? = nil) {
        self.totalSeconds = totalSeconds
        self.sessions = sessions
        self.lastPlayed = lastPlayed
        self.openSince = openSince
    }
}
