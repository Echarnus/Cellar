import CellarDomain
import Foundation

/// Resolving a profile into a `GamePlan`, the questions every caller asks of one, and the façades
/// over the use cases (`LoadLibrary`, `SetUpGame`, `InstallGame`, `LaunchGame`, `UninstallGame`),
/// kept so callers that pass a closure per kind of progress don't all have to change at once.
/// New code calls the use case.
public enum Game {
    /// A readiness summary for every known profile — the façade over `LoadLibrary`.
    public static func summaries() -> [GameSummary] { LoadLibrary().summaries() }

    /// The player's library — see `LoadLibrary.library()`.
    public static func library() -> [GameSummary] { LoadLibrary().library() }

    /// Bottle names belonging to profiles from one store. Cheap: it reads the profile TOMLs and
    /// nothing else — no runner lookups, no icon extraction, no filesystem walk of the bottles.
    public static func bottleNames(forStore store: GameStore) -> Set<String> {
        var names: Set<String> = []
        for ref in ProfileStore.all() {
            let fields = ProfileStore.fields(ref)
            guard GameStore(profileValue: fields["store"]) == store else { continue }
            names.insert(fields["bottle"] ?? ref.slug)
        }
        return names
    }

    /// Every profile that lives in this bottle. Usually just one — a bottle is per-game by default
    /// — but a profile can opt into sharing one, and a removal has to know before it takes the
    /// bottle away from games that were never mentioned.
    public static func slugs(sharingBottle bottleName: String) -> [String] {
        ProfileStore.all().filter { ref in
            (ProfileStore.fields(ref)["bottle"] ?? ref.slug) == bottleName
        }.map(\.slug)
    }

    public static func plan(slug: String) throws -> GamePlan {
        guard let ref = ProfileStore.find(slug) else {
            throw CellarError.invalidArgument("No profile '\(slug)'. Try: cellar profiles list")
        }
        let fields = ProfileStore.fields(ref)
        // Every game Cellar runs came from a store, and the store decides the whole pipeline. A
        // profile that names none (or one Cellar doesn't support) is refused, never guessed at:
        // guessing Steam would stand the wrong client up in the bottle.
        guard let store = GameStore(profileValue: fields["store"]) else {
            let named = fields["store"].map { "names the store '\($0)', which Cellar doesn't support" }
                ?? "doesn't name its store"
            throw CellarError.invalidArgument(
                "The profile '\(slug)' \(named). Cellar only runs games installed through Steam, "
                + "Battle.net or GOG — add store = \"steam\", \"battlenet\" or \"gog\" to \(ref.slug).toml.")
        }
        // A publisher launcher the game can't start without. Named but unknown is refused for the
        // same reason as an unknown store: launching without it fails in a way that looks like the
        // game is broken.
        let launcher = PublisherLauncher(profileValue: fields["publisher_launcher"])
        if let named = fields["publisher_launcher"], !named.trimmingCharacters(in: .whitespaces).isEmpty, launcher == nil {
            throw CellarError.invalidArgument(
                "The profile '\(slug)' names the publisher launcher '\(named)', which Cellar doesn't know. "
                + "The one it can set up is publisher_launcher = \"rockstar\".")
        }
        // Several games can share one bottle (one sign-in, one download cache); a profile
        // opts in with `bottle = "<name>"`. Default: one bottle per game.
        let bottleName = fields["bottle"] ?? slug
        let bottleFile = BottleConfig.url(forBottle: bottleName)
        let profileBackend = fields["backend"] ?? "d3dmetal"
        let performance = PerformanceSettings.resolve(
            profileFields: fields, profileEnv: ProfileStore.env(ref),
            bottleFields: BottleConfig.fields(bottleFile), bottleEnv: BottleConfig.env(bottleFile))
        return GamePlan(
            slug: slug,
            name: fields["name"] ?? slug,
            bottleName: bottleName,
            runnerID: fields["id"] ?? RunnerCatalog.defaultID,
            store: store,
            appID: fields["steam_appid"].flatMap { Int($0) },
            backend: BackendChoice.chosen(in: bottleFile)?.rawValue ?? profileBackend,
            profileBackend: profileBackend,
            fallbackBackend: fields["fallback_backend"],
            env: performance.env,
            installMethod: fields["method"] ?? defaultInstallMethod(for: store),
            launchExe: fields["exe"],
            installDir: fields["install_dir"],
            productCode: fields["product_code"],
            gogProductID: fields["gog_product_id"].flatMap { Int($0) },
            // Default to needing the store unless a profile explicitly says otherwise — safe for DRM.
            // `needs_live_steam` is the original spelling, kept working.
            needsLiveSession: ((fields["needs_live_session"] ?? fields["needs_live_steam"]) ?? "true")
                .lowercased() != "false",
            artPortraitURL: fields["art_portrait"],
            artHeroURL: fields["art_hero"],
            facts: GameFacts(
                developer: fields["developer"],
                released: fields["released"],
                engine: fields["engine"],
                graphicsAPI: fields["graphics_api"],
                anticheat: fields["anticheat"],
                drm: fields["drm"],
                online: fields["online"],
                requiresAccount: fields["requires_account"],
                status: fields["status"],
                notes: fields["notes"],
                controller: fields["controller"],
                wheel: fields["wheel"],
                wheelSetup: fields["wheel_setup"]),
            metalFXUpscaling: performance.metalFXUpscaling,
            language: LanguageChoice.resolve(game: BottleConfig.language(bottleFile), global: CellarSettings.language),
            performance: performance,
            isDraft: fields["generated"]?.lowercased() == "true",
            publisherLauncher: launcher,
            startExe: fields["start_exe"]
        )
    }

    static func defaultInstallMethod(for store: GameStore) -> String {
        switch store {
        case .steam:      return "windows-steam-in-bottle"
        case .battlenet:  return "battlenet-in-bottle"
        case .gog:        return "gog-installer"
        }
    }

    /// The bottle's Wine runner, if the runner is installed.
    public static func wineRunner(_ plan: GamePlan) -> WineRunner? {
        guard let install = RunnerManager.find(id: plan.runnerID) else { return nil }
        return WineRunner(install: install, prefix: plan.prefix, backend: plan.graphicsBackend, metalFX: plan.metalFXUpscaling,
                          language: plan.language.language)
    }

    // MARK: - Store-aware state

    // The questions every store answers differently live in its `StoreAdapter`; these are the
    // façade every caller already uses.

    public static func storeClientInstalled(_ plan: GamePlan) -> Bool {
        plan.store.adapter.isClientInstalled(plan)
    }

    public static func storeClientRunning(_ plan: GamePlan) -> Bool {
        plan.store.adapter.isClientRunning
    }

    public static func signedInAccount(_ plan: GamePlan) -> String? {
        plan.store.adapter.signedInAccount(plan)
    }

    /// Whether the game's files are on disk. A store that keeps a record of its own (Steam's
    /// appmanifest) is authoritative; otherwise the profile's exe is the answer.
    public static func isGameInstalled(_ plan: GamePlan) -> Bool {
        // An install still running, or one that stopped partway, has files but not a game.
        if UnfinishedInstall.isPending(plan) { return false }
        if plan.directLaunchExe != nil { return true }
        return plan.store.adapter.recordsGameInstalled(plan) ?? false
    }

    // MARK: - Setup

    /// Set the game's bottle up — the façade over `SetUpGame`.
    @discardableResult
    public static func setUp(_ plan: GamePlan, progress: (String) -> Void,
                             phase: (InstallProgress) -> Void = { _ in }) throws -> WineRunner {
        try SetUpGame(plan).run { $0.deliver(progress: progress, install: phase) }
    }

    // MARK: - Install / download

    /// Download the game's Windows files via DepotDownloader into the bottle (no store client).
    /// Steam credentials authenticate the download only; 2FA is prompted on the terminal.
    public static func fetchDepot(_ plan: GamePlan, credentials: DepotTool.Credentials,
                                 progress: (String) -> Void) throws {
        func step(_ message: String) {
            CellarLog.debug(.install, message, subject: plan.slug)
            progress(message)
        }
        CellarLog.info(.install, "Downloading \(plan.name) from a Steam depot.", subject: plan.slug)
        guard let appID = plan.appID else {
            throw CellarError.invalidArgument("Profile '\(plan.slug)' has no steam_appid to download.")
        }
        guard plan.store != .battlenet else {
            throw CellarError.invalidArgument(
                "\(plan.name) comes from Battle.net — Blizzard has no depot downloader. Install it in the client: cellar battlenet install \(plan.slug)")
        }
        guard plan.store != .gog else {
            throw CellarError.invalidArgument(
                "\(plan.name) comes from GOG, not Steam. Install it with: cellar gog install \(plan.slug)")
        }
        guard let spec = RunnerCatalog.spec(forID: plan.runnerID) else {
            throw CellarError.invalidArgument("Unknown runner '\(plan.runnerID)'.")
        }
        let install = try RunnerManager.install(spec, progress: step)
        let wine = WineRunner(install: install, prefix: plan.prefix, backend: plan.graphicsBackend, metalFX: plan.metalFXUpscaling,
                              language: plan.language.language)
        if !FileManager.default.fileExists(atPath: plan.prefix.appendingPathComponent("system.reg").path) {
            step("Initialising the Wine prefix…")
            try wine.initializePrefix(); try wine.setWindowsVersion("win10")
        }
        step("Downloading \(plan.name) (Windows depot) via DepotDownloader…")
        try DepotTool.fetch(appID: appID, into: plan.depotGameDir, credentials: credentials)
        step("Downloaded to \(plan.depotGameDir.path)")
        CellarLog.info(.install, "Depot download finished.", subject: plan.slug)
    }

    /// Install the game through its store — the façade over `InstallGame`.
    public static func installGame(_ plan: GamePlan, progress: (String) -> Void = { _ in },
                                   phase: (InstallProgress) -> Void = { _ in }) throws {
        try InstallGame(plan).run { $0.deliver(progress: progress, install: phase) }
    }

    /// Open the store's client in the bottle (sign in, browse, manage installs).
    public static func openStoreClient(_ plan: GamePlan, showHUD: Bool = false) throws {
        CellarLog.info(.store, "Opening \(plan.store.displayName) in bottle '\(plan.bottleName)'.",
                       subject: plan.slug)
        guard let wine = wineRunner(plan) else {
            throw CellarError.invalidArgument(
                "Runner '\(plan.runnerID)' isn't installed. Run: cellar setup --profile \(plan.slug)")
        }
        try plan.store.adapter.openClient(plan, wine: wine, showHUD: showHUD)
    }

    // MARK: - Launch

    /// Launch the game — the façade over `LaunchGame`, for callers that want a closure per kind.
    @discardableResult
    public static func launch(_ plan: GamePlan, showHUD: Bool = false, forceStore: Bool = false,
                              checkUpdates: Bool = true,
                              stage: (LaunchStage) -> Void = { _ in },
                              update: (InstallProgress) -> Void = { _ in },
                              progress: (String) -> Void = { _ in }) throws -> LaunchRoute {
        try LaunchGame(plan, showHUD: showHUD, forceStore: forceStore, checkUpdates: checkUpdates)
            .run { $0.deliver(progress: progress, install: update, launch: stage) }
    }

    /// Launch the game's exe directly through Wine — no store client. Only valid when `canLaunchStoreFree`.
    public static func launchDirect(_ plan: GamePlan, showHUD: Bool = false) throws {
        guard let wine = wineRunner(plan) else {
            throw CellarError.invalidArgument("Runner '\(plan.runnerID)' isn't installed.")
        }
        guard let exe = plan.directLaunchExe else {
            throw CellarError.invalidArgument(
                "No launchable exe found for '\(plan.slug)'. Run: cellar install \(plan.slug)")
        }
        var env = WineRunner.d3dMetalEnv(showHUD: showHUD)
        for (key, value) in plan.launchEnv { env[key] = value }
        let wineLog = Paths.logs.appendingPathComponent("game-\(plan.slug).log")
        CellarLog.debug(.launch, "Starting \(exe.lastPathComponent) directly; Wine output → "
            + wineLog.lastPathComponent, subject: plan.slug)
        try wine.spawn([exe.path], extraEnv: env, log: wineLog,
                       bundledLoader: GameApp.prepare(for: plan, runner: wine))
    }

    /// Block until the player quits, then take the whole layer down — see `LaunchGame`.
    public static func waitForExitThenShutDown(_ plan: GamePlan, route: LaunchRoute) {
        LaunchGame(plan).waitForExitThenShutDown(route)
    }
}
