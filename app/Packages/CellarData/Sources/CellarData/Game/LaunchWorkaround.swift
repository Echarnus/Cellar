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

public extension GamePlan {
    /// The workaround a launch of this game falls back to, or nil when the player switched none off.
    var launchWorkaround: LaunchWorkaround? {
        guard let env = launchEnvWithWorkarounds, let message = restoringWorkaroundsMessage else { return nil }
        let plan = self
        return LaunchWorkaround(env: env, message: message, keep: { plan.restoreCrashWorkarounds() })
    }
}
