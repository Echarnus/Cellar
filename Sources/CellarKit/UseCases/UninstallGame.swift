import Foundation

/// `cellar uninstall`: what removing a game would take away, then taking it.
///
/// Two calls on purpose. `preview()` is what the player confirms; `run` asks everything that can
/// change while they read it again (`Uninstall.perform`), so a plan is never a licence to delete.
public struct UninstallGame {
    public let plan: GamePlan
    public let scope: RemovalScope

    public init(_ plan: GamePlan, scope: RemovalScope) {
        self.plan = plan
        self.scope = scope
    }

    /// Everything the removal would delete, and anything that blocks it — nothing is touched.
    public func preview() -> RemovalPlan { Uninstall.plan(for: plan, scope: scope) }

    /// Delete what `removal` names (a fresh `preview()` when nil). Returns the bytes freed.
    @discardableResult
    public func run(_ removal: RemovalPlan? = nil, report: (GameEvent) -> Void = { _ in }) throws -> Int64 {
        try Uninstall.perform(removal ?? preview(), for: plan, progress: { report(.step($0)) })
    }
}
