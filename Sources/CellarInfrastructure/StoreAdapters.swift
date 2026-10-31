import CellarDomain
import CellarKit
import Foundation

// The concrete store adapters: each one drives a real store (a bottle's Steam client, Blizzard's
// Battle.net, GOG's API) through CellarKit's port `StoreAdapter`. Moved here from CellarKit (#77)
// so the engine's use cases depend on the port alone; only composition roots import this module.

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

    public func launchThroughClient(_ plan: GamePlan, wine: WineRunner, showHUD: Bool, forceStore: Bool,
                                    progress: (String) -> Void, stage: (LaunchStage) -> Void,
                                    update: (InstallProgress) -> Void) throws -> LaunchRoute {
        guard let appID = plan.appID else {
            throw CellarError.invalidArgument("Profile '\(plan.slug)' has no steam_appid to launch.")
        }
        // A game with no live-session DRM runs without the client, so reaching here with its exe
        // missing means it isn't downloaded — not that Steam needs setting up.
        if !plan.needsLiveSession, !forceStore, !SteamBottle.isGameInstalled(in: plan.prefix, appID: appID) {
            throw CellarError.invalidArgument(
                "\(plan.name) isn't installed yet. Run: cellar install \(plan.slug)")
        }
        // A bottle set up before Cellar did Steam's first update itself still has only the
        // bootstrapper, which would put Steam's own update window on screen mid-launch.
        try SteamBottle.updateClient(runner: wine, progress: progress) {
            update(InstallProgress(.clientUpdate, fraction: $0))
        }
        SteamBottle.alignGameLanguage(plan.language.language, in: plan.prefix, appID: appID)
        // Cellar downloaded this copy, so Steam has no appmanifest for it and `rungameid` would
        // find nothing. The game's own DRM still wants a live session, so the client is brought
        // up quietly first and the exe is launched beside it — Steamworks finds the running,
        // signed-in client the same way it does for any game started outside the library.
        if !SteamBottle.isGameInstalled(in: plan.prefix, appID: appID), let exe = plan.directLaunchExe {
            guard SteamBottle.isInstalled(in: plan.prefix) else {
                throw CellarError.invalidArgument(
                    "\(plan.name) needs a running Steam client for its DRM, and this bottle has none. Run: cellar setup --profile \(plan.slug)")
            }
            // A client nobody is signed in to would move the failure to the game's own licence
            // check, where it looks like the game is broken. So the client is handed the session
            // the player gave Cellar; only when that can't be done does Play open the client's
            // window and wait for the player to sign in to it.
            // Handed over now, or already remembered from a previous launch: either way the
            // client signs itself in, and the game has to wait for that to land.
            let signsItself = SteamBottle.handOverSession(runner: wine, progress: progress).signsInByItself
            // The guard stays unconditional: a hand-over leaves `loginusers.vdf` naming the
            // account, so it costs nothing here — and it is the only thing that catches a client
            // that is up but signed out, where the cold-start logon wait never runs.
            if SteamBottle.loggedInAccount(in: plan.prefix) == nil {
                stage(.signIn)
                try SteamBottle.waitForClientSignIn(runner: wine, game: plan.name, showHUD: showHUD,
                                                    gameEnv: plan.launchEnv, progress: progress)
            }
            progress("Starting Steam quietly for \(plan.name)'s DRM, then launching the game…")
            try SteamBottle.launchAlongside(runner: wine, exe: exe, appID: appID,
                                            showHUD: showHUD, gameEnv: plan.launchEnv,
                                            bundledLoader: GameApp.prepare(for: plan, runner: wine),
                                            game: plan.name, expectsSignIn: signsItself,
                                            progress: progress, stage: stage)
            return .steamAlongside(exeName: exe.lastPathComponent, appID: appID)
        }
        guard SteamBottle.isInstalled(in: plan.prefix) else {
            throw CellarError.invalidArgument(
                "Windows Steam isn't installed in this bottle. Run: cellar setup --profile \(plan.slug)")
        }
        let signsItself = SteamBottle.handOverSession(runner: wine, progress: progress).signsInByItself
        progress("Launching \(plan.name) via Steam (AppID \(appID)) — runner \(plan.runnerID), backend \(plan.backend)…")
        try SteamBottle.runGameSupervised(runner: wine, appID: appID, showHUD: showHUD,
                                          gameEnv: plan.launchEnv, game: plan.name, expectsSignIn: signsItself,
                                          progress: progress, stage: stage)
        stage(.running)
        return .steam(appID: appID)
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
