import CellarDomain
import Foundation

/// `cellar launch`: start the game by whichever route its profile and its store call for,
/// supervising the startup so the D3DMetal race doesn't surface as "it just didn't open" — and,
/// afterwards, take the whole layer down when the player quits.
///
/// The direct route (no client: the exe on disk, no live-session DRM) is decided here; every route
/// through a client belongs to the store's adapter.
public struct LaunchGame {
    public let plan: GamePlan
    public let adapter: any StoreAdapter
    public var showHUD: Bool
    /// Skips the store-free shortcut, for debugging a title that normally runs bare.
    public var forceStore: Bool
    /// Bring a Cellar-downloaded copy up to the store's current build first.
    public var checkUpdates: Bool

    public init(_ plan: GamePlan, showHUD: Bool = false, forceStore: Bool = false,
                checkUpdates: Bool = true, adapter: (any StoreAdapter)? = nil) {
        self.plan = plan
        self.showHUD = showHUD
        self.forceStore = forceStore
        self.checkUpdates = checkUpdates
        self.adapter = adapter ?? plan.store.adapter
    }

    @discardableResult
    public func run(_ report: (GameEvent) -> Void = { _ in }) throws -> LaunchRoute {
        let plan = plan
        func stage(_ stage: LaunchStage) { report(.launch(stage)) }
        func update(_ progress: InstallProgress) { report(.install(progress)) }
        // Every progress line the player reads is also kept, so a session can be reconstructed
        // afterwards from the log alone.
        func step(_ message: String) {
            CellarLog.debug(.launch, message, subject: plan.slug)
            report(.step(message))
        }
        stage(.preparing)
        CellarLog.info(.launch, "Launching \(plan.name) — store \(plan.store.rawValue), runner "
            + "\(plan.runnerID), backend \(plan.backend)\(forceStore ? ", store route forced" : "")",
            subject: plan.slug)
        do {
            let route = try self.route(progress: step, stage: stage, update: update)
            Diagnostics.playSessionBegan(slug: plan.slug, name: plan.name, route: route.logDescription)
            return route
        } catch {
            CellarLog.failure(.launch, "\(plan.name) did not start", error, subject: plan.slug)
            throw error
        }
    }

    /// Pick the route and take it. Split out of `run` so the logging there wraps every path.
    private func route(progress: (String) -> Void,
                       stage: (LaunchStage) -> Void,
                       update: (InstallProgress) -> Void) throws -> LaunchRoute {
        // A game moved to a drive that isn't plugged in: said by name, before anything reads as
        // "not installed" and offers to download it onto the disk the player was keeping free.
        if let error = GameStorage.missingDriveError(plan) { throw error }
        guard let wine = Game.wineRunner(plan) else {
            throw CellarError.invalidArgument(
                "Runner '\(plan.runnerID)' isn't installed. Run: cellar setup --profile \(plan.slug)")
        }
        // After a runner update Wine would rebuild the prefix inside this launch, with its own
        // "Please wait" box on screen. Do it first, where nothing is drawn.
        wine.updatePrefixIfStale()
        // Retina mode lives in the registry, not the environment. Only written when the profile or
        // the player said something about it: every other game keeps Wine's default and pays nothing.
        if let retina = plan.performance.entries.first(where: { $0.setting == .retina }), retina.source != .cellarDefault {
            wine.setRetinaMode(retina.value == "true")
        }

        // A copy Cellar downloaded has nobody else to keep it current: Steam doesn't know it exists.
        // So Cellar does what Steam does before it starts anything — catch it up first.
        if checkUpdates, GameUpdates.managesUpdates(plan) {
            try Self.updateBeforeLaunch(plan, progress: progress, update: update)
        }

        // No live-session DRM and the exe is on disk → run it directly, no client at all.
        if plan.canLaunchStoreFree && !forceStore {
            let exe = plan.directLaunchExe!
            progress("Launching \(plan.name) directly (no store client) — \(exe.lastPathComponent), backend \(plan.backend)…")
            stage(.starting)
            try Game.launchDirect(plan, showHUD: showHUD)
            // Watch for the process rather than declaring victory on a successful spawn: Wine
            // returns immediately, so "it launched" is otherwise a claim about nothing. Not
            // appearing is a failure and is thrown as one, the way the supervised store routes
            // throw after their last attempt — a ✓ for a state Cellar could not check is worse
            // than no launch at all.
            stage(.waiting)
            guard ProcessWatch.waitToAppear([exe.lastPathComponent], seconds: 40) else {
                throw CellarError.ioFailure(
                    "Cellar started \(exe.lastPathComponent) but its process never appeared. Check the log, and that the profile's `exe` still matches what is installed: cellar profiles show \(plan.slug)")
            }
            stage(.running)
            return .direct(exeName: exe.lastPathComponent)
        }

        return try adapter.launchThroughClient(plan, wine: wine, showHUD: showHUD, forceStore: forceStore,
                                              progress: progress, stage: stage, update: update)
    }

    /// How long an "up to date" answer is trusted before Play asks Steam again. Long enough that a
    /// relaunch straight after a crash doesn't pay for the check twice, short enough that a patch
    /// released this afternoon is picked up this evening.
    static let updateCheckReuse: TimeInterval = 15 * 60

    /// Bring a Cellar-downloaded game up to Steam's current build before it starts.
    ///
    /// Only one thing stands between the player and the build they have: files that are mid-change.
    /// A check that can't reach Steam, or an update that can't begin (offline, sign-in expired),
    /// says so and starts the intact build on disk. An update that stopped after it began replacing
    /// files does not, because half a patch is a game in no known state; the next Play resumes it.
    ///
    /// Steam is asked afresh unless it said "up to date" in the last few minutes — never on the
    /// strength of an older "update available", which an update since then would have made stale.
    static func updateBeforeLaunch(_ plan: GamePlan, progress: (String) -> Void,
                                   update: (InstallProgress) -> Void) throws {
        if DepotTool.isDownloading(into: plan.depotGameDir) {
            throw CellarError.ioFailure(
                "An update for \(plan.name) is still downloading into its folder. Wait for it to finish, then press Play — starting the game now would run it on files that are being replaced.")
        }
        let cached = GameUpdates.cachedState(plan)
        if case .upToDate = cached, GameUpdates.isFresh(cached, within: updateCheckReuse) { return }

        progress("Checking with Steam for a newer version of \(plan.name)…")
        update(InstallProgress(.updateCheck))
        switch GameUpdates.check(plan, timeout: 60) {
        case .available:
            progress("A newer version of \(plan.name) is out — downloading only what changed…")
            do {
                try GameUpdates.apply(plan, progress: progress, phase: update)
            } catch GameUpdates.UpdateFailure.notStarted(let why) {
                progress("Couldn't download the update (\(why)) — starting the version you have.")
            } catch GameUpdates.UpdateFailure.alreadyDownloading {
                throw CellarError.ioFailure(
                    "An update for \(plan.name) is already downloading into its folder. Wait for it to finish, then press Play.")
            } catch {
                CellarLog.failure(.launch, "\(plan.name)'s update stopped partway", error, subject: plan.slug)
                throw CellarError.ioFailure(
                    "\(plan.name)'s update stopped partway (\(CellarLog.describe(error))). Press Play again to pick it up where it left off, or run: cellar update \(plan.slug)")
            }
        case .unknown(let why):
            progress("Couldn't check for updates (\(why)) — starting the version you have.")
        case .upToDate:
            break
        }
    }

    /// Block until the player quits, then take the whole layer down — the behaviour that makes
    /// Cellar feel like a game launcher rather than a pile of Wine processes.
    ///
    /// `exited` is called the moment the game is gone, before the teardown starts: closing Steam
    /// takes seconds, and the player should not be told they are still playing while it does.
    public func waitForExitThenShutDown(_ route: LaunchRoute, exited: () -> Void = {}) {
        let wine = Game.wineRunner(plan)
        defer {
            Diagnostics.playSessionEnded(slug: plan.slug, name: plan.name,
                                         processNeedles: plan.gameProcessNeedles)
            CellarLog.debug(.session, "Layer shut down (\(route.logDescription)).", subject: plan.slug)
        }
        switch route {
        case .direct(let exeName):
            ProcessWatch.waitToExit([exeName])
            exited()
            wine?.shutDown()
        case .steamAlongside(let exeName, _):
            // Steam was started for the game's DRM, so it goes when the game does — asked to quit
            // first, the same as on the client route, rather than only losing its wineserver.
            ProcessWatch.waitToExit([exeName])
            exited()
            if let wine { SteamBottle.shutdown(runner: wine) }
        case .steam(let appID):
            SteamBottle.waitForGameExit(in: plan.prefix, appID: appID)
            exited()
            if let wine { SteamBottle.shutdown(runner: wine) }
        case .battlenet:
            ProcessWatch.waitToExit(plan.gameProcessNeedles)
            exited()
            if let wine { BattleNetBottle.shutdown(runner: wine) }
        }
    }
}
