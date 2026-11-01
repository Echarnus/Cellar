import Foundation

/// One launch's use of a `LaunchWorkaround`: switched to at most once, after the first death on
/// start, and kept only if the game then stays up. Both Steam routes drive their retries through it.
public final class LaunchWorkaroundSwitch {
    private let workaround: LaunchWorkaround?
    public private(set) var isOn = false

    public init(_ workaround: LaunchWorkaround?) { self.workaround = workaround }

    /// The game died as it started: the environment to try next, the first time only. Nil when there
    /// is no workaround to put back, or it is already on — then a retry is all that is left.
    public func diedStarting(progress: (String) -> Void) -> [String: String]? {
        guard let workaround, !isOn else { return nil }
        isOn = true
        progress(workaround.message)
        return workaround.env
    }

    /// The game stayed up: with the workaround on, that makes it the bottle's setting again.
    public func stayedUp() {
        if isOn { workaround?.keep() }
    }
}
