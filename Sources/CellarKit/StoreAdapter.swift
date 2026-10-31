import Foundation

/// What a store *does*, one type per store — where `StoreDescriptor` is what a store *is*.
///
/// Per-store behaviour used to be a `switch plan.store` repeated in every function that needed it,
/// so adding a store meant finding all of them. An adapter answers those questions for its own
/// store, and `GameStore.adapter` is the one switch left. Capabilities move here one at a time
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
}

extension GameStore {
    /// The adapter for this store — the only `switch` on a store that behaviour should need.
    public var adapter: any StoreAdapter {
        switch self {
        case .steam:     return SteamAdapter()
        case .battlenet: return BattleNetAdapter()
        case .gog:       return GOGAdapter()
        }
    }
}

public struct SteamAdapter: StoreAdapter {
    public init() {}
    public var store: GameStore { .steam }
    public func isClientInstalled(_ plan: GamePlan) -> Bool { SteamBottle.isInstalled(in: plan.prefix) }
    public var isClientRunning: Bool { SteamBottle.isRunning }
    public func signedInAccount(_ plan: GamePlan) -> String? { SteamBottle.loggedInAccount(in: plan.prefix) }
    /// Steam's appmanifest is authoritative — and only counts when its folder holds files.
    public func recordsGameInstalled(_ plan: GamePlan) -> Bool? {
        plan.appID.map { SteamBottle.isGameInstalled(in: plan.prefix, appID: $0) }
    }

    public func setUpClient(_ plan: GamePlan, wine: WineRunner, step: (String) -> Void,
                            phase: (InstallProgress) -> Void) throws {
        // The client is a *runtime* dependency, not an install one: Cellar downloads the game
        // itself now, so a title whose DRM never talks to a running Steam has no reason to pull
        // a 1.4 GB client it will never start. Setting one up anyway would be an invented step,
        // and the game screen already promises not to demand it (`GameSummary.nextStep`).
        guard plan.needsLiveSession else {
            step("No Steam client needed — this game runs without a live Steam session.")
            return
        }
        if !SteamBottle.isInstalled(in: plan.prefix) { phase(InstallProgress(.client)) }
        try SteamBottle.install(runner: wine, progress: step)
        // Done here rather than on first Play, where Steam would draw its own update window.
        try SteamBottle.updateClient(runner: wine, progress: step) {
            phase(InstallProgress(.clientUpdate, fraction: $0))
        }
    }

    public func installGame(_ plan: GamePlan, wine: WineRunner, step: (String) -> Void,
                            progress: (String) -> Void, phase: (InstallProgress) -> Void) throws {
        guard let appID = plan.appID else {
            throw CellarError.invalidArgument("Profile '\(plan.slug)' has no steam_appid.")
        }
        // Steam already installed it — leave that copy alone. Downloading a second one into
        // Cellar's own directory would cost the player the whole game twice.
        if SteamBottle.isGameInstalled(in: plan.prefix, appID: appID) {
            step("\(plan.name) is already installed in your Steam library.")
            return
        }
        guard let credentials = SteamAccount.credentials else {
            throw CellarError.invalidArgument(
                "Not signed in to Steam. One scan covers every Steam game: cellar steam login")
        }
        step("Downloading \(plan.name) from your Steam library (AppID \(appID))…")
        // `progress` is non-escaping and the download does not outlive this call — the tool's
        // output is handed over line by line while it runs.
        phase(InstallProgress(.downloading))
        try withoutActuallyEscaping(progress) { report in
            try withoutActuallyEscaping(phase) { phase in
                try DepotTool.fetch(appID: appID, into: plan.depotGameDir, credentials: credentials) { line in
                    if let fraction = DepotProgress.fraction(in: line) {
                        phase(InstallProgress(.downloading, fraction: fraction))
                    }
                    report(line)
                }
            }
        }
        SteamDRM.markAppDirectory(plan.depotGameDir, appID: appID)
        step("Downloaded to \(plan.depotGameDir.path)")
    }

    public func openClient(_ plan: GamePlan, wine: WineRunner, showHUD: Bool) throws {
        guard SteamBottle.isInstalled(in: plan.prefix) else {
            throw CellarError.invalidArgument(
                "Windows Steam isn't installed in this bottle. Run: cellar setup --profile \(plan.slug)")
        }
        try SteamBottle.updateClient(runner: wine)
        try SteamBottle.launchClient(runner: wine, showHUD: showHUD, gameEnv: plan.env)
    }
}

public struct BattleNetAdapter: StoreAdapter {
    public init() {}
    public var store: GameStore { .battlenet }
    public func isClientInstalled(_ plan: GamePlan) -> Bool { BattleNetBottle.isInstalled(in: plan.prefix) }
    public var isClientRunning: Bool { BattleNetBottle.isRunning }
    public func signedInAccount(_ plan: GamePlan) -> String? { BattleNetBottle.rememberedAccount(in: plan.prefix) }
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
}

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
}
