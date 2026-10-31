import Foundation

/// The games waiting to be downloaded, in the order the player asked for them.
///
/// Cellar runs one command at a time, and a download can take an hour. Before this, Install on a
/// second game did nothing until the first had finished, so the player had to come back and press
/// it again. Now the second game waits its turn here and starts by itself.
///
/// The game being downloaded is not in the queue. It belongs to whatever is running the command,
/// and the queue only ever holds what has not started yet.
public struct InstallQueue: Sendable, Equatable {
    /// One game waiting its turn.
    public struct Entry: Sendable, Equatable, Identifiable {
        public let slug: String
        public let name: String
        public let store: GameStore
        public var id: String { slug }

        public init(slug: String, name: String, store: GameStore) {
            self.slug = slug
            self.name = name
            self.store = store
        }
    }

    public private(set) var waiting: [Entry] = []

    public init(_ waiting: [Entry] = []) {
        self.waiting = waiting
    }

    public var isEmpty: Bool { waiting.isEmpty }
    public var count: Int { waiting.count }

    /// Puts a game at the back of the line. Nothing happens when it is already waiting, or when it
    /// is the one being downloaded now (`running`). Pressing Install twice is not two downloads.
    @discardableResult
    public mutating func enqueue(_ entry: Entry, running: String? = nil) -> Bool {
        guard entry.slug != running, !contains(entry.slug) else { return false }
        waiting.append(entry)
        return true
    }

    /// Takes a game out of the line before it has started.
    @discardableResult
    public mutating func remove(_ slug: String) -> Bool {
        guard let index = waiting.firstIndex(where: { $0.slug == slug }) else { return false }
        waiting.remove(at: index)
        return true
    }

    /// The game whose turn it is, taken off the front of the line.
    public mutating func next() -> Entry? {
        waiting.isEmpty ? nil : waiting.removeFirst()
    }

    public func contains(_ slug: String) -> Bool {
        waiting.contains { $0.slug == slug }
    }

    /// Where a game stands in the line, counting from 1 for the next one to start.
    public func position(of slug: String) -> Int? {
        waiting.firstIndex { $0.slug == slug }.map { $0 + 1 }
    }
}
