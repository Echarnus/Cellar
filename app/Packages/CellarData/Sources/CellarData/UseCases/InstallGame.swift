import CellarDomain
import Foundation

/// `cellar install`: the game through its store — a depot download for Steam, the client for
/// Battle.net, the offline installer for GOG. The bottle must already be set up (`SetUpGame`).
public struct InstallGame {
    public let plan: GamePlan
    public let adapter: any StoreAdapter

    public init(_ plan: GamePlan, adapter: (any StoreAdapter)? = nil) {
        self.plan = plan
        self.adapter = adapter ?? plan.store.adapter
    }

    public func run(_ report: (GameEvent) -> Void = { _ in }) throws {
        let plan = plan
        func step(_ message: String) {
            CellarLog.debug(.install, message, subject: plan.slug)
            report(.step(message))
        }
        // A download tool's own output: shown, but too chatty to keep in the log line by line.
        func output(_ line: String) { report(.step(line)) }
        func phase(_ progress: InstallProgress) { report(.install(progress)) }

        CellarLog.info(.install, "Installing \(plan.name) via \(plan.store.displayName).", subject: plan.slug)
        if let error = GameStorage.missingDriveError(plan) { throw error }
        guard let wine = Game.wineRunner(plan) else {
            throw CellarError.invalidArgument(
                "Runner '\(plan.runnerID)' isn't installed. Run: cellar setup --profile \(plan.slug)")
        }
        // Until the store's install returns, whatever is on disk is not the game (`UnfinishedInstall`).
        // A throw — a failure, or the player cancelling — leaves the note in place.
        UnfinishedInstall.begin(plan)
        try adapter.installGame(plan, wine: wine, step: step, progress: output, phase: phase)
        UnfinishedInstall.finish(plan)
    }
}
