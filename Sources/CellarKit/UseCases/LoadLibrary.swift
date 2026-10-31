import Foundation

/// Read every profile and say how ready each game is — the app's library and `cellar library`.
///
/// Its two dependencies are passed in: which profiles exist, and how one becomes a `GamePlan`. The
/// defaults read the profile database; a test can hand it a fixed list.
///
/// Never asks a store anything over the network: it runs on every library refresh. Ownership comes
/// from `StoreLibrary`'s cache, which `StoreLibrary.refreshAll` is the one to fill.
public struct LoadLibrary {
    public var slugs: () -> [String]
    public var plan: (String) throws -> GamePlan

    public init(slugs: @escaping () -> [String] = { ProfileStore.all().map(\.slug) },
                plan: @escaping (String) throws -> GamePlan = { try Game.plan(slug: $0) }) {
        self.slugs = slugs
        self.plan = plan
    }

    /// A readiness summary for every known profile — the GUI's data source.
    public func summaries() -> [GameSummary] {
        // Read once, closing any session a crash left open — unless that game is running now.
        let played = Playtime.all(isRunning: { slug in (try? plan(slug)).map(Uninstall.isGameRunning) ?? false })
        return slugs().compactMap { slug in
            guard let plan = try? plan(slug) else { return nil }
            var summary = Self.summary(of: plan)
            summary.playtime = played[plan.slug]
            return summary
        }
    }

    /// **The player's library**: the games their stores confirmed they own, plus the ones no store
    /// can be asked about. Everything the app and `cellar library` show goes through here, so the
    /// two cannot disagree about whose games these are.
    public func library() -> [GameSummary] { summaries().filter(\.isVisible) }

    /// One game's readiness, read from disk (no playtime: that is read once for the whole library).
    public static func summary(of plan: GamePlan) -> GameSummary {
        let adapter = plan.store.adapter
        let clientInstalled = adapter.isClientInstalled(plan)
        var summary = GameSummary(
            slug: plan.slug,
            name: plan.name,
            store: plan.store,
            appID: plan.appID,
            iconPath: AppBundle.resolveGameICNS(slug: plan.slug, prefix: plan.prefix,
                                                appID: plan.appID, installRoots: plan.installRoots)?.path,
            runnerInstalled: RunnerManager.find(id: plan.runnerID) != nil,
            clientInstalled: clientInstalled,
            account: clientInstalled ? adapter.signedInAccount(plan) : nil,
            gameInstalled: Game.isGameInstalled(plan),
            bottleExists: FileManager.default.fileExists(atPath: plan.prefix.path),
            running: adapter.isClientRunning,
            productCode: plan.productCode,
            // Cache only — `summaries()` runs on every library refresh, so it must never ask a
            // store anything. `StoreLibrary.refreshAll` is what does the asking.
            ownership: StoreLibrary.ownership(of: plan),
            needsLiveSession: plan.needsLiveSession,
            clientSignsInByItself: plan.store == .steam && plan.needsLiveSession && clientInstalled
                && SteamBottle.clientSessionReadiness(in: plan.prefix).signsInByItself,
            // Only Steam publishes free cover art keyed on an app id; everything else has to
            // bring its own URLs or fall back to Cellar's generated cover.
            artworkAppID: plan.store == .steam ? plan.appID : nil,
            artPortraitURL: plan.artPortraitURL,
            artHeroURL: plan.artHeroURL,
            needsClientAtRuntime: !plan.canLaunchStoreFree,
            update: GameUpdates.cachedState(plan),
            facts: plan.facts,
            runnerID: plan.runnerID,
            backend: plan.backend,
            bottleName: plan.bottleName)
        summary.profileBackend = plan.profileBackend
        summary.fallbackBackend = plan.fallbackBackend
        summary.isDraft = plan.isDraft
        summary.missingDrive = GameStorage.missingDrive(plan)
        summary.isOnOtherDrive = GameStorage.movedLocation(slug: plan.slug) != nil
        return summary
    }
}
