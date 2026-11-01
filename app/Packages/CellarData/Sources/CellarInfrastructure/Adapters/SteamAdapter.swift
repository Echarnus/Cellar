import CellarDomain
import CellarData
import Foundation

// The concrete store adapters: each one drives a real store (a bottle's Steam client, Blizzard's
// Battle.net, GOG's API) through CellarData's port `StoreAdapter`. Moved here from CellarData (#77)
// so the engine's use cases depend on the port alone; only composition roots import this module.

public struct SteamAdapter: StoreAdapter {
    public init() {}
    public var store: GameStore { .steam }
    public func isClientInstalled(_ plan: GamePlan) -> Bool { SteamBottle.isInstalled(in: plan.prefix) }
    public var isClientRunning: Bool { SteamBottle.isRunning }
    public func verificationMark(_ plan: GamePlan) -> UInt64 { SteamSessionCheck.mark(in: plan.prefix) }
    public func verificationChecks(_ plan: GamePlan, since mark: UInt64, launchSteps: [String]) -> [VerificationCheck] {
        SteamSessionCheck.checks(prefix: plan.prefix, since: mark, launchSteps: launchSteps)
            + [SteamDLCCheck.check(plan)]
    }
    public func shutDownClient(_ plan: GamePlan, wine: WineRunner) { SteamBottle.shutdown(runner: wine) }
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
        // The DLC came down with the game; this is what lets the game see it (`SteamLibraryEntry`).
        SteamLibraryEntry.register(plan)
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

    /// Whether the client installed this copy itself. The entry Cellar writes for its own download
    /// (`SteamLibraryEntry`) makes Steam count that copy as installed, but it is still Cellar's copy
    /// and keeps Cellar's route: started beside the client, never through `rungameid`.
    public static func isClientCopy(_ plan: GamePlan, appID: Int) -> Bool {
        SteamBottle.isGameInstalled(in: plan.prefix, appID: appID) && !SteamLibraryEntry.isCellarEntry(plan)
    }

    /// Whether Cellar starts the game's exe itself, beside the client, rather than asking the
    /// client to. Always for a copy the client doesn't have; for the client's own copy only when
    /// that buys Game Mode, and never when the player asked for the store route by name.
    public static func startsGameItself(clientCopy: Bool, forceStore: Bool, gameAppAvailable: Bool) -> Bool {
        !clientCopy || (gameAppAvailable && !forceStore)
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
        // Before the client starts: Steam reads its library once, at start-up. Also what brings a
        // copy downloaded before Cellar did this into the library, DLC and all.
        SteamLibraryEntry.register(plan)
        SteamBottle.alignGameLanguage(plan.language.language, in: plan.prefix, appID: appID)
        // The client is brought up quietly first and the exe is launched beside it — Steamworks
        // finds the running, signed-in client the same way it does for any game started outside
        // the library. Taken when Cellar downloaded this copy (Steam has no appmanifest for it, so
        // `rungameid` would find nothing), and also for the client's own copy whenever the game can
        // start from its game app: a game Steam starts is Steam's child, a bare `wine` that macOS
        // never gives Game Mode (`GameApp`).
        let clientCopy = Self.isClientCopy(plan, appID: appID)
        if let exe = plan.directLaunchExe,
           Self.startsGameItself(clientCopy: clientCopy, forceStore: forceStore,
                                 gameAppAvailable: GameApp.isAvailable(runnerBinary: wine.binary)) {
            guard SteamBottle.isInstalled(in: plan.prefix) else {
                throw CellarError.invalidArgument(
                    "\(plan.name) needs a running Steam client for its DRM, and this bottle has none. Run: cellar setup --profile \(plan.slug)")
            }
            // Steam's stub hands off to the publisher's launcher; without it there is nothing to
            // hand off to, and the game never appears.
            if let launcher = plan.publisherLauncher, !launcher.isInstalled(in: plan.prefix) {
                throw CellarError.invalidArgument(
                    "\(plan.name) starts through the \(launcher.displayName), and this bottle doesn't have it yet. Run: cellar setup --profile \(plan.slug)")
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
                                            start: plan.directStartExe,
                                            publisherLauncher: plan.publisherLauncher,
                                            progress: progress, stage: stage)
            return .steamAlongside(exeName: exe.lastPathComponent, appID: appID)
        }
        guard SteamBottle.isInstalled(in: plan.prefix) else {
            throw CellarError.invalidArgument(
                "Windows Steam isn't installed in this bottle. Run: cellar setup --profile \(plan.slug)")
        }
        let signsItself = SteamBottle.handOverSession(runner: wine, progress: progress).signsInByItself
        progress("Launching \(plan.name) via Steam (AppID \(appID)) — runner \(plan.runnerID), backend \(plan.backend)…")
        if let launcher = plan.publisherLauncher {
            progress("Steam hands \(plan.name) to the \(launcher.displayName). If it asks, sign in with your \(launcher.accountNoun) there.")
        }
        try SteamBottle.runGameSupervised(runner: wine, appID: appID, showHUD: showHUD,
                                          gameEnv: plan.launchEnv, game: plan.name, expectsSignIn: signsItself,
                                          progress: progress, stage: stage)
        stage(.running)
        return .steam(appID: appID)
    }
}
