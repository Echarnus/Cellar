import Foundation

/// What Cellar knows about whether a downloaded game is current.
public enum UpdateState: Sendable, Equatable {
    /// Steam confirmed every depot matches what is on disk, at `checked`.
    case upToDate(checked: Date)
    /// Steam is serving a newer build than the one on disk.
    case available(checked: Date)
    /// Not asked yet, or the question could not be answered. Never shown as "up to date": a
    /// check that did not happen is not a check that passed.
    case unknown(String)
}
