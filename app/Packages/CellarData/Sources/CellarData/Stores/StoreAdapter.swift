import CellarDomain
import Foundation
import Synchronization

/// What a store *does*, one type per store — where `StoreDescriptor` is what a store *is*.
///
/// Per-store behaviour used to be a `switch plan.store` repeated in every function that needed it,
/// so adding a store meant finding all of them. An adapter answers those questions for its own
/// store. The adapters themselves live in `CellarInfrastructure`; this module holds only the port
/// and the registry the composition root fills (`StoreAdapters`). Capabilities move here one at a time
/// (docs/APP-ARCHITECTURE.md → Target: the engine); `Game`'s static functions stay as the façade
/// every caller already uses.
///
/// Every game comes through a store, so there is no adapter for "no store".
public protocol StoreAdapter: Sendable {
    var store: GameStore { get }
    /// Whether the store's client is present in the bottle. A store with no client in the bottle is
    /// "installed" by definition and never asks the player to set one up.
    func isClientInstalled(_ plan: GamePlan) -> Bool
    /// Whether the store's client is running now.
    var isClientRunning: Bool { get }
    /// The signed-in account, or nil when the store doesn't say (see `GameSummary.account`).
    func signedInAccount(_ plan: GamePlan) -> String?
    /// Whether the game's files are on disk, by the store's own record — nil when the store keeps
    /// none, and the profile's exe is the only answer.
    func recordsGameInstalled(_ plan: GamePlan) -> Bool?

    /// The last step of `cellar setup`: the store's client in the bottle, if the game needs one.
    func setUpClient(_ plan: GamePlan, wine: WineRunner, step: (String) -> Void,
                     phase: (InstallProgress) -> Void) throws
    /// Install the game through its store. `progress` gets a download tool's raw output as well as
    /// `step`'s sentences.
    func installGame(_ plan: GamePlan, wine: WineRunner, step: (String) -> Void,
                     progress: (String) -> Void, phase: (InstallProgress) -> Void) throws
    /// Open the store's client in the bottle (sign in, browse, manage installs).
    func openClient(_ plan: GamePlan, wine: WineRunner, showHUD: Bool) throws
    /// Start the game through the store, once Play has ruled out running its exe directly: the
    /// client in the bottle for a store that has one, an honest "not installed" for one that doesn't.
    func launchThroughClient(_ plan: GamePlan, wine: WineRunner, showHUD: Bool, forceStore: Bool,
                             progress: (String) -> Void, stage: (LaunchStage) -> Void,
                             update: (InstallProgress) -> Void) throws -> LaunchRoute

    // MARK: Verification (#203)

    /// Where the store's own session record stands now, so `cellar verify` reads only what this
    /// run adds to it. Zero for a store that keeps none.
    func verificationMark(_ plan: GamePlan) -> UInt64
    /// The store's baseline checks for one run (`signed-in`, `steam-online`), read from what the
    /// store wrote since `mark`. `launchSteps` is every sentence the launch reported.
    func verificationChecks(_ plan: GamePlan, since mark: UInt64, launchSteps: [String]) -> [VerificationCheck]
    /// Quit the store's client in the bottle, and the bottle's Wine with it.
    func shutDownClient(_ plan: GamePlan, wine: WineRunner)
}
