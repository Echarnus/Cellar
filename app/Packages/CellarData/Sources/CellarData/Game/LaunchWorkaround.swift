import Foundation

/// What a supervised launch tries when the game dies as it starts and the player had switched off a
/// crash workaround its profile turns on (`PerformanceSetting.isCrashWorkaround`).
///
/// Retrying the same crash eight times and then giving up is what Planet Coaster 2 did with Metal
/// validation off: two minutes of a window flashing up and dying. So after the first such death the
/// launch carries on with `env` — the game's environment with the workaround back on — and if the
/// game then stays up, `keep` makes that the bottle's setting again, so the next Play just works.
public struct LaunchWorkaround {
    /// The game's environment with the workarounds back on.
    public let env: [String: String]
    /// The sentence the player reads when the launch switches over.
    public let message: String
    /// Called once the game stayed up with `env`.
    public let keep: () -> Void

    public init(env: [String: String], message: String, keep: @escaping () -> Void) {
        self.env = env
        self.message = message
        self.keep = keep
    }
}

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

public extension GamePlan {
    /// The workaround a launch of this game falls back to, or nil when the player switched none off.
    var launchWorkaround: LaunchWorkaround? {
        guard let env = launchEnvWithWorkarounds, let message = restoringWorkaroundsMessage else { return nil }
        let plan = self
        return LaunchWorkaround(env: env, message: message, keep: { plan.restoreCrashWorkarounds() })
    }
}
