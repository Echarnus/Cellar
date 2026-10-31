import CellarDomain
import CellarKit
import Foundation

public struct GOGAdapter: StoreAdapter {
    public init() {}
    public var store: GameStore { .gog }
    /// GOG needs no client in the bottle at all, so there is never one to set up.
    public func isClientInstalled(_ plan: GamePlan) -> Bool { true }
    public var isClientRunning: Bool { false }
    /// Cellar holds the GOG token itself, so this is a fact, not a guess — but read it from the
    /// cache: `summaries()` runs on every library refresh and must not make a network call.
    public func signedInAccount(_ plan: GamePlan) -> String? {
        GOGAuth.isSignedIn ? (GOGAuth.cachedUsername ?? "your GOG account") : nil
    }
    public func recordsGameInstalled(_ plan: GamePlan) -> Bool? { nil }

    public func setUpClient(_ plan: GamePlan, wine: WineRunner, step: (String) -> Void,
                            phase: (InstallProgress) -> Void) throws {
        step("No store client needed — GOG games are DRM-free, so Cellar installs and runs them directly.")
    }

    public func installGame(_ plan: GamePlan, wine: WineRunner, step: (String) -> Void,
                            progress: (String) -> Void, phase: (InstallProgress) -> Void) throws {
        guard let productID = plan.gogProductID else {
            throw CellarError.invalidArgument(
                "Profile '\(plan.slug)' has no gog_product_id, so Cellar can't tell which GOG game it is.")
        }
        guard GOGAuth.isSignedIn else {
            throw CellarError.invalidArgument("Not signed in to GOG. Run: cellar gog login")
        }
        phase(InstallProgress(.downloading))
        let parts = try GOGInstall.download(productID: productID, progress: step)
        phase(InstallProgress(.installing))
        try GOGInstall.install(setup: parts[0], slug: plan.slug, runner: wine, progress: step)
        guard plan.directLaunchExe != nil else {
            throw CellarError.ioFailure(
                "The installer finished but Cellar can't find '\(plan.launchExe ?? "the game's exe")' under C:\\Games\\\(plan.slug). Check the profile's `exe`.")
        }
        step("\(plan.name) is installed. Play it with: cellar launch \(plan.slug)")
    }

    public func openClient(_ plan: GamePlan, wine: WineRunner, showHUD: Bool) throws {
        throw CellarError.invalidArgument(
            "GOG has no client in the bottle — Cellar talks to GOG directly. Sign in with: cellar gog login")
    }

    public func launchThroughClient(_ plan: GamePlan, wine: WineRunner, showHUD: Bool, forceStore: Bool,
                                    progress: (String) -> Void, stage: (LaunchStage) -> Void,
                                    update: (InstallProgress) -> Void) throws -> LaunchRoute {
        // Reaching here means the exe isn't on disk: a DRM-free game never needs the store route.
        throw CellarError.invalidArgument(
            "\(plan.name) isn't installed yet. Run: cellar gog install \(plan.slug)")
    }
}
