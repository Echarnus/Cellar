import CellarDomain
import CellarData
import Foundation

public struct BattleNetAdapter: StoreAdapter {
    public init() {}
    public var store: GameStore { .battlenet }
    public func isClientInstalled(_ plan: GamePlan) -> Bool { BattleNetBottle.isInstalled(in: plan.prefix) }
    public var isClientRunning: Bool { BattleNetBottle.isRunning }
    public func signedInAccount(_ plan: GamePlan) -> String? { BattleNetBottle.rememberedAccount(in: plan.prefix) }
    public func shutDownClient(_ plan: GamePlan, wine: WineRunner) { BattleNetBottle.shutdown(runner: wine) }
    public func recordsGameInstalled(_ plan: GamePlan) -> Bool? { nil }

    public func setUpClient(_ plan: GamePlan, wine: WineRunner, step: (String) -> Void,
                            phase: (InstallProgress) -> Void) throws {
        if !BattleNetBottle.isInstalled(in: plan.prefix) { phase(InstallProgress(.client)) }
        try BattleNetBottle.install(runner: wine, progress: step)
    }

    public func installGame(_ plan: GamePlan, wine: WineRunner, step: (String) -> Void,
                            progress: (String) -> Void, phase: (InstallProgress) -> Void) throws {
        // Battle.net exposes no per-product install URL Cellar could drive, so the honest
        // move is to open the client where the player can do it in two clicks.
        step("Opening Battle.net — install \(plan.name) from the client, then come back.")
        try BattleNetBottle.launchClient(runner: wine, gameEnv: plan.env)
    }

    public func openClient(_ plan: GamePlan, wine: WineRunner, showHUD: Bool) throws {
        guard BattleNetBottle.isInstalled(in: plan.prefix) else {
            throw CellarError.invalidArgument(
                "Battle.net isn't installed in this bottle. Run: cellar setup --profile \(plan.slug)")
        }
        try BattleNetBottle.launchClient(runner: wine, showHUD: showHUD, gameEnv: plan.env)
    }

    public func launchThroughClient(_ plan: GamePlan, wine: WineRunner, showHUD: Bool, forceStore: Bool,
                                    progress: (String) -> Void, stage: (LaunchStage) -> Void,
                                    update: (InstallProgress) -> Void) throws -> LaunchRoute {
        guard BattleNetBottle.isInstalled(in: plan.prefix) else {
            throw CellarError.invalidArgument(
                "Battle.net isn't installed in this bottle. Run: cellar setup --profile \(plan.slug)")
        }
        guard let product = plan.productCode else {
            throw CellarError.invalidArgument(
                "Profile '\(plan.slug)' has no product_code — Battle.net needs one to launch (Diablo IV is 'Fen').")
        }
        let needles = plan.gameProcessNeedles
        guard !needles.isEmpty else {
            throw CellarError.invalidArgument(
                "Profile '\(plan.slug)' needs an `exe` or `install_dir` so Cellar can tell when the game is running.")
        }
        progress("Launching \(plan.name) via Battle.net (product \(product)) — runner \(plan.runnerID), backend \(plan.backend)…")
        try BattleNetBottle.runGameSupervised(runner: wine, product: product, gameNeedles: needles,
                                              showHUD: showHUD, gameEnv: plan.launchEnv,
                                              progress: progress, stage: stage)
        stage(.running)
        return .battlenet(product: product)
    }
}
