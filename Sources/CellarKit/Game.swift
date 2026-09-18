import Foundation

/// Resolved launch plan for a game profile.
public struct GamePlan {
    public let slug: String
    public let name: String
    public let bottleName: String
    public let runnerID: String
    /// Which client has to exist inside the bottle for this game — the single fact that decides
    /// how it is set up, installed and launched. See `GameStore`.
    public let store: GameStore
    public let appID: Int?
    public let backend: String
    /// `[env]` from the profile — applied to the game and to the store client that spawns it.
    public let env: [String: String]
    /// Install method: `windows-steam-in-bottle` (default), `battlenet-in-bottle`, or `depot`.
    public let installMethod: String
    /// Relative path (from the game's install dir) of the exe to run, e.g. `AoE2DE_s.exe`.
    /// Also the process Cellar watches to know the game is alive.
    public let launchExe: String?
    /// The game's own install-directory name, when the store doesn't tell us
    /// (Battle.net: `Diablo IV`). Steam gets this from its appmanifest instead.
    public let installDir: String?
    /// Battle.net product code — `Fen` for Diablo IV. The argument to `--exec="launch …"`.
    public let productCode: String?
    /// GOG's product id, the key to everything on their API (owned check, metadata, installers).
    public let gogProductID: Int?
    /// Whether the game needs a live store session at *runtime* (Denuvo / Steamworks / always-online).
    /// When false and `launchExe` resolves, Cellar launches the exe directly with no client at all.
    public let needsLiveSession: Bool
    /// Optional profile-supplied cover / banner art, for stores with no public artwork CDN.
    public let artPortraitURL: String?
    public let artHeroURL: String?
    /// What the profile says about the game itself — shown in the app's information panel.
    public let facts: GameFacts
    /// `metalfx_upscaling = true`: present the NVIDIA identity so the game's DLSS option becomes
    /// MetalFX. Only takes effect on D3DMetal with a runtime that ships the shims (`WineRunner.usesMetalFX`).
    public var metalFXUpscaling: Bool = false

    public var prefix: URL { Paths.prefixes.appendingPathComponent(bottleName, isDirectory: true) }
    public var graphicsBackend: GraphicsBackend { GraphicsBackend(rawValue: backend) ?? .d3dmetal }

    /// Where DepotDownloader places this game's files inside the bottle.
    public var depotGameDir: URL { prefix.appendingPathComponent("drive_c/Games/\(slug)", isDirectory: true) }

    /// Every directory a game's files could plausibly live in, in search order. Stores install to
    /// different roots, and the player may have pointed the installer somewhere else again.
    public var installRoots: [URL] {
        var roots = [depotGameDir]
        if let installDir {
            roots += [
                prefix.appendingPathComponent("drive_c/Program Files (x86)/\(installDir)"),
                prefix.appendingPathComponent("drive_c/Program Files/\(installDir)"),
                prefix.appendingPathComponent("drive_c/Games/\(installDir)"),
                // Where the Windows Steam client puts a game it installed itself. Without this a
                // client-installed copy is invisible to every direct route, because Steam nests it
                // one directory deeper than the search below reaches.
                prefix.appendingPathComponent("drive_c/Program Files (x86)/Steam/steamapps/common/\(installDir)"),
            ]
        }
        roots.append(prefix.appendingPathComponent("drive_c/Program Files (x86)/Steam/steamapps/common"))
        return roots
    }

    /// The absolute exe to run for a direct launch, if one is configured and present on disk.
    public var directLaunchExe: URL? {
        guard let launchExe else { return nil }
        return installRoots
            .map { $0.appendingPathComponent(launchExe) }
            .first { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// True when this game can be launched with no store client at all.
    public var canLaunchStoreFree: Bool { !needsLiveSession && directLaunchExe != nil }

    /// Who is being launched and by which route — what the launch stages are worded from.
    public var launchContext: LaunchContext {
        LaunchContext(game: name, store: store, throughClient: !canLaunchStoreFree,
                      signsInFirst: needsLiveSession && store.descriptor.installsClientInBottle
                          && store.descriptor.canDetectSignIn && Game.signedInAccount(self) == nil
                          // Not a step when Cellar signs the client in itself.
                          && !(store == .steam && SteamBottle.clientSessionReadiness(in: prefix).signsInByItself))
    }

    /// Command-line fragments that identify the *game's own* process, so a supervised launch never
    /// mistakes the store client for the game. Wine reports Windows command lines, hence both
    /// separators.
    public var gameProcessNeedles: [String] {
        var needles: [String] = []
        if let launchExe { needles.append((launchExe as NSString).lastPathComponent) }
        if let installDir { needles += ["\\\(installDir)\\", "/\(installDir)/"] }
        return needles
    }
}

/// What a profile knows *about* the game, as opposed to how to run it.
///
/// These have always been in the TOML and were never shown to anyone. For a Steam title that was
/// survivable — the store page is a click away. For a Battle.net one there is no page to click, so
/// the profile is the only description of the game the player gets, and `notes` in particular is
/// where Cellar records what has actually been tested and what has not.
public struct GameFacts: Sendable {
    public let developer: String?
    public let released: String?
    public let engine: String?
    public let graphicsAPI: String?
    public let anticheat: String?
    public let drm: String?
    public let online: String?
    public let requiresAccount: String?
    /// `playable` / `untested` / `broken` — how far this profile has actually been verified.
    public let status: String?
    /// Free text: the caveats, the hardware something was tested on, the known patch-day breakage.
    public let notes: String?

    public init(developer: String? = nil, released: String? = nil, engine: String? = nil,
                graphicsAPI: String? = nil, anticheat: String? = nil, drm: String? = nil,
                online: String? = nil, requiresAccount: String? = nil, status: String? = nil,
                notes: String? = nil) {
        self.developer = developer
        self.released = released
        self.engine = engine
        self.graphicsAPI = graphicsAPI
        self.anticheat = anticheat
        self.drm = drm
        self.online = online
        self.requiresAccount = requiresAccount
        self.status = status
        self.notes = notes
    }

    /// The facts worth printing as a spec list, in reading order, skipping what a profile omits.
    public var about: [(label: String, value: String)] {
        [("Developer", developer), ("Released", released),
         ("Engine", engine), ("Graphics", graphicsAPI)]
            .compactMap { label, value in value.map { (label, $0) } }
    }

    /// The facts that answer "will this actually run, and what does it want from me?".
    public var compatibility: [(label: String, value: String)] {
        [("Anti-cheat", anticheat), ("DRM", drm), ("Online", online), ("Account", requiresAccount)]
            .compactMap { label, value in value.map { (label, $0) } }
    }
}

/// How a launch was actually carried out — the CLI needs this to say the right thing afterwards
/// and to know what to wait on.
public enum LaunchRoute {
    case direct(exeName: String)
    case steam(appID: Int)
    case battlenet(product: String)

    /// How the route reads in the log and in a diagnostics report.
    public var logDescription: String {
        switch self {
        case .direct(let exeName):    return "direct: \(exeName)"
        case .steam(let appID):       return "via Steam, AppID \(appID)"
        case .battlenet(let product): return "via Battle.net, product \(product)"
        }
    }
}

/// A game's readiness, for the GUI to decide what to show (and which button to offer next).
public struct GameSummary: Identifiable, Sendable {
    public let slug: String
    public let name: String
    public let store: GameStore
    public let appID: Int?
    public let iconPath: String?       // .icns, if one could be produced
    public let runnerInstalled: Bool   // the profile's Wine runner is present
    public let clientInstalled: Bool   // the store's client is installed in the bottle
    /// The signed-in account, when the store lets us know. **nil means "we can't tell"**, not
    /// "nobody" — only trust it as a negative when `store.descriptor.canDetectSignIn`.
    public let account: String?
    public let gameInstalled: Bool     // the game's files are on disk
    /// Whether the bottle exists on disk. Not the same question as `clientInstalled` — a GOG game
    /// never has a client, but it still has a bottle to remove.
    public let bottleExists: Bool
    public let running: Bool           // the store's client is up
    /// Battle.net's equivalent of an AppID — how its client names this game (`Fen` = Diablo IV).
    public let productCode: String?
    /// What the store says about this account owning the game. The library is filtered on it, so a
    /// game only appears once the store has confirmed it — see `StoreLibrary`.
    public let ownership: Ownership
    /// Whether the store's client has to be *running* for this game to start (Steamworks, Denuvo,
    /// always-online). Read from the profile, so it is known before the game is installed —
    /// `needsClientAtRuntime` cannot answer that, because it also depends on files being on disk.
    public let needsLiveSession: Bool
    /// Steam AppID to pull public artwork with — nil for stores that publish none.
    public let artworkAppID: Int?
    public let artPortraitURL: String?
    public let artHeroURL: String?

    public var id: String { slug }

    /// Whether this game belongs in the player's library at all.
    public var isVisible: Bool { verdict.isVisible }

    /// Why this game is or isn't in the library — the whole answer, so a caller that needs the
    /// sentence and the fix doesn't re-derive them from the parts.
    public var verdict: StoreLibrary.Verdict {
        StoreLibrary.verdict(store: store, ownership: ownership,
                             isConnected: StoreLibrary.isConnected(store))
    }

    /// The single most useful next action given the current state.
    public enum NextStep: Sendable {
        case setup      // no runner, or no store client yet
        case install    // game not installed
        case play       // ready
    }

    /// Signing in is never a step of its own on a game's page. Cellar's sign-in is account-level,
    /// done once in Settings, and a game whose store hasn't been signed in is not in the library.
    ///
    /// The store **client inside the bottle** keeps a session of its own: a Steamworks or Denuvo game
    /// talks to a running Steam. Cellar hands that client the player's session when it can
    /// (`SteamClientSession`); when it can't, the sign-in is folded into Play (`clientSignInPending`)
    /// — a separate "Sign in to Steam" button beside a Settings row already saying "Signed in" read
    /// as Cellar asking twice.
    public var nextStep: NextStep {
        // Install sets up whatever is missing before it fetches the game, so a game that isn't on
        // disk yet is one button away, never two. A separate "Set up" step asked the player for
        // nothing they could decide — Cellar can see what is missing and just do it.
        if !gameInstalled { return .install }
        // What is left of `.setup` is repair: the files are there but the runtime or the client the
        // game runs against has gone (a reset, a removed runner).
        if setupPending { return .setup }
        return .play
    }

    /// Whether Play first opens the store client's window for the player to sign in to it.
    ///
    /// Only where Cellar can actually *read* that nobody is signed in. Battle.net publishes nothing
    /// comparable, so it is never promised a sign-in — signing in stays folded into its client. And
    /// not where Cellar hands the client the session the player already gave it
    /// (`clientSignsInByItself`), which is the ordinary case for Steam.
    public var clientSignInPending: Bool {
        needsLiveSession && store.descriptor.installsClientInBottle
            && store.descriptor.canDetectSignIn && account == nil && !clientSignsInByItself
    }

    /// Whether the store client in the bottle signs in with Cellar's own session — already remembered
    /// there, or handed over when Play starts it (`SteamBottle.clientSessionReadiness`).
    public let clientSignsInByItself: Bool

    /// Whether install has to set things up before the game itself — the runtime, or a store
    /// client. The client only has to exist for a game that talks to it while it runs, and for
    /// Battle.net, where Blizzard installs games from inside it. A game Cellar downloads and
    /// launches itself needs none, and demanding one would be an invented 1.4 GB step.
    public var setupPending: Bool {
        if !runnerInstalled { return true }
        guard store.descriptor.installsClientInBottle, !clientInstalled else { return false }
        return needsLiveSession || !store.descriptor.hasSilentInstaller
    }

    /// The primary button's title. Store-specific on purpose: "Install" means something different
    /// in a client that installs games for you than in one Cellar drives itself.
    public var actionTitle: String {
        switch nextStep {
        case .setup:   return "Set up"
        case .install:
            switch store {
            case .steam:      return "Install"
            case .battlenet:  return "Open Battle.net"
            case .gog:        return "Download"
            }
        case .play:    return "Play"
        }
    }

    public var actionSymbol: String {
        switch nextStep {
        case .play:   return "play.fill"
        case .setup:  return "wrench.and.screwdriver.fill"
        case .install: return store == .battlenet ? "arrow.up.forward.app.fill" : "arrow.down.circle.fill"
        // (GOG and Steam both download, so both get the download mark.)
        }
    }

    /// One sentence under the button telling the player what is about to happen. Honest about the
    /// parts Cellar cannot do for them.
    public var actionHint: String {
        switch nextStep {
        case .setup:
            return store.descriptor.hasSilentInstaller
                ? "Cellar installs the Windows runtime and \(store.displayName) for this game. One click, a few minutes."
                : "Cellar installs the Windows runtime, then opens Blizzard's installer — that one needs a few clicks from you, because Battle.net ships no silent install."
        case .install:
            // The first game on a Mac also fetches the Windows runtime. Saying so up front is what
            // keeps a few extra minutes from reading as a stall.
            let first = setupPending
                ? " The first time, Cellar also sets up the Windows runtime — a few extra minutes." : ""
            switch store {
            case .steam:      return "Cellar downloads it from your Steam library with the sign-in you already gave it. No Steam window, nothing to click." + first
            case .battlenet:
                return setupPending
                    ? "Cellar sets up the Windows runtime, then Blizzard's installer opens — it needs a few clicks from you, because Battle.net ships no silent install. Then install the game from Battle.net."
                    : "Battle.net opens. Sign in if you haven't, then install the game from there. Cellar takes over once the files are down."
            case .gog:        return "Cellar downloads it from your GOG library and installs it. No client, and nothing runs alongside the game." + first
            }
        case .play:
            if updatePending {
                return "A newer version is out. Play downloads only what changed, then starts the game."
            }
            if clientSignInPending {
                return "Installed. The first time, Play opens \(store.displayName)'s window so you can sign in to it, then starts the game."
            }
            return needsClientAtRuntime
                ? "Installed. Play starts \(store.displayName) quietly in the background and closes the whole layer when you quit."
                : "Installed. Play runs the game directly — no store client at all — and closes the layer when you quit."
        }
    }

    /// Whether playing this game will bring a store client up alongside it.
    public let needsClientAtRuntime: Bool

    /// Whether this copy is on Steam's current build — only for a game Cellar downloaded itself,
    /// since Steam updates the ones in its own library. Nil means Cellar doesn't manage it. Read
    /// from the last check, never by asking Steam: this is built on every library refresh.
    public let update: GameUpdates.State?

    /// A newer build is known to be out, so Play fetches it first.
    public var updatePending: Bool {
        if case .available = update { return true }
        return false
    }

    /// Who is being launched and by which route — what the launch window words its steps from.
    public var launchContext: LaunchContext {
        LaunchContext(game: name, store: store, throughClient: needsClientAtRuntime,
                      signsInFirst: clientSignInPending)
    }
    /// What the profile says about the game — the app's information panel.
    public let facts: GameFacts
    /// The runtime this profile pins, for the app to show without re-reading the TOML.
    public let runnerID: String
    public let backend: String
    public let bottleName: String

    public init(slug: String, name: String, store: GameStore, appID: Int?, iconPath: String?,
                runnerInstalled: Bool, clientInstalled: Bool, account: String?, gameInstalled: Bool,
                bottleExists: Bool, running: Bool, productCode: String?,
                ownership: Ownership = .unknown("not checked"),
                needsLiveSession: Bool = true,
                clientSignsInByItself: Bool = false,
                artworkAppID: Int?,
                artPortraitURL: String?, artHeroURL: String?,
                needsClientAtRuntime: Bool, update: GameUpdates.State? = nil,
                facts: GameFacts, runnerID: String, backend: String,
                bottleName: String) {
        self.slug = slug
        self.name = name
        self.store = store
        self.appID = appID
        self.iconPath = iconPath
        self.runnerInstalled = runnerInstalled
        self.clientInstalled = clientInstalled
        self.account = account
        self.gameInstalled = gameInstalled
        self.bottleExists = bottleExists
        self.running = running
        self.productCode = productCode
        self.ownership = ownership
        self.needsLiveSession = needsLiveSession
        self.clientSignsInByItself = clientSignsInByItself
        self.artworkAppID = artworkAppID
        self.artPortraitURL = artPortraitURL
        self.artHeroURL = artHeroURL
        self.needsClientAtRuntime = needsClientAtRuntime
        self.update = update
        self.facts = facts
        self.runnerID = runnerID
        self.backend = backend
        self.bottleName = bottleName
    }
}

/// High-level orchestration tying runners, bottles, Wine, and the store clients together.
public enum Game {
    /// A readiness summary for every known profile — the GUI's data source.
    public static func summaries() -> [GameSummary] {
        ProfileStore.all().compactMap { ref in
            guard let plan = try? plan(slug: ref.slug) else { return nil }
            let clientInstalled = storeClientInstalled(plan)
            return GameSummary(
                slug: plan.slug,
                name: plan.name,
                store: plan.store,
                appID: plan.appID,
                iconPath: AppBundle.resolveGameICNS(slug: plan.slug, prefix: plan.prefix,
                                                    appID: plan.appID, installRoots: plan.installRoots)?.path,
                runnerInstalled: RunnerManager.find(id: plan.runnerID) != nil,
                clientInstalled: clientInstalled,
                account: clientInstalled ? signedInAccount(plan) : nil,
                gameInstalled: isGameInstalled(plan),
                bottleExists: FileManager.default.fileExists(atPath: plan.prefix.path),
                running: storeClientRunning(plan),
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
        }
    }

    /// **The player's library**: the games their stores confirmed they own, plus the ones no store
    /// can be asked about. Everything the app and `cellar library` show goes through here, so the
    /// two cannot disagree about whose games these are.
    public static func library() -> [GameSummary] { summaries().filter(\.isVisible) }

    /// Bottle names belonging to profiles from one store. Cheap: it reads the profile TOMLs and
    /// nothing else — no runner lookups, no icon extraction, no filesystem walk of the bottles.
    public static func bottleNames(forStore store: GameStore) -> Set<String> {
        var names: Set<String> = []
        for ref in ProfileStore.all() {
            let fields = ProfileStore.fields(ref)
            guard (GameStore(profileValue: fields["store"]) ?? .default) == store else { continue }
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
        let store = GameStore(profileValue: fields["store"]) ?? .default
        return GamePlan(
            slug: slug,
            name: fields["name"] ?? slug,
            // Several games can share one bottle (one sign-in, one download cache); a profile
            // opts in with `bottle = "<name>"`. Default: one bottle per game.
            bottleName: fields["bottle"] ?? slug,
            runnerID: fields["id"] ?? RunnerCatalog.defaultID,
            store: store,
            appID: fields["steam_appid"].flatMap { Int($0) },
            backend: fields["backend"] ?? "d3dmetal",
            env: ProfileStore.env(ref),
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
                notes: fields["notes"]),
            metalFXUpscaling: fields["metalfx_upscaling"]?.lowercased() == "true"
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
        return WineRunner(install: install, prefix: plan.prefix, backend: plan.graphicsBackend, metalFX: plan.metalFXUpscaling)
    }

    // MARK: - Store-aware state

    /// Whether the store's client is present in the bottle. A store with no client in the bottle is
    /// "installed" by definition and never asks the player to set one up.
    public static func storeClientInstalled(_ plan: GamePlan) -> Bool {
        switch plan.store {
        case .steam:      return SteamBottle.isInstalled(in: plan.prefix)
        case .battlenet:  return BattleNetBottle.isInstalled(in: plan.prefix)
        // GOG needs no client in the bottle at all, so there is never one to set up.
        case .gog:        return true
        }
    }

    public static func storeClientRunning(_ plan: GamePlan) -> Bool {
        switch plan.store {
        case .steam:      return SteamBottle.isRunning
        case .battlenet:  return BattleNetBottle.isRunning
        case .gog:        return false
        }
    }

    /// The signed-in account, or nil when the store doesn't say (see `GameSummary.account`).
    public static func signedInAccount(_ plan: GamePlan) -> String? {
        switch plan.store {
        case .steam:      return SteamBottle.loggedInAccount(in: plan.prefix)
        case .battlenet:  return BattleNetBottle.rememberedAccount(in: plan.prefix)
        // Cellar holds the GOG token itself, so this is a fact, not a guess — but read it from the
        // cache: `summaries()` runs on every library refresh and must not make a network call.
        case .gog:        return GOGAuth.isSignedIn ? (GOGAuth.cachedUsername ?? "your GOG account") : nil
        }
    }

    /// Whether the game's files are on disk. Steam has an authoritative answer in its appmanifest;
    /// the other stores are checked by looking for the exe the profile names.
    public static func isGameInstalled(_ plan: GamePlan) -> Bool {
        if plan.directLaunchExe != nil { return true }
        if plan.store == .steam, let appID = plan.appID {
            return SteamBottle.isGameInstalled(in: plan.prefix, appID: appID)
        }
        return false
    }

    // MARK: - Setup

    /// Minimal-setup pipeline: ensure runner → bottle → initialised prefix → the store's client.
    /// Idempotent: safe to re-run; skips steps already done.
    @discardableResult
    public static func setUp(_ plan: GamePlan, progress: (String) -> Void,
                             phase: (InstallProgress) -> Void = { _ in }) throws -> WineRunner {
        func step(_ message: String) {
            CellarLog.debug(.setup, message, subject: plan.slug)
            progress(message)
        }
        CellarLog.info(.setup, "Setting up \(plan.name) — store \(plan.store.rawValue), runner "
            + "\(plan.runnerID), backend \(plan.backend), bottle '\(plan.bottleName)'", subject: plan.slug)
        guard SystemEnvironment.isAppleSilicon else {
            throw CellarError.invalidArgument("Cellar requires an Apple Silicon Mac.")
        }
        guard SystemEnvironment.rosettaWorks else {
            throw CellarError.invalidArgument(
                "Rosetta 2 is required. Install it: softwareupdate --install-rosetta --agree-to-license")
        }
        guard let spec = RunnerCatalog.spec(forID: plan.runnerID) else {
            throw CellarError.invalidArgument("Unknown runner '\(plan.runnerID)'.")
        }
        if let why = spec.deprecated {
            step("Warning: runner '\(spec.id)' is deprecated — \(why)")
        }

        if RunnerManager.find(id: spec.id) == nil { phase(InstallProgress(.runtime)) }
        let install = try RunnerManager.install(spec, progress: step)
        let wine = WineRunner(install: install, prefix: plan.prefix, backend: plan.graphicsBackend, metalFX: plan.metalFXUpscaling)

        if !FileManager.default.fileExists(atPath: plan.prefix.appendingPathComponent("system.reg").path) {
            phase(InstallProgress(.bottle))
        }
        if !FileManager.default.fileExists(atPath: plan.prefix.path) {
            step("Creating bottle '\(plan.bottleName)'…")
            try PrefixManager.create(name: plan.bottleName, backend: plan.graphicsBackend, runner: plan.runnerID)
        }

        let registry = plan.prefix.appendingPathComponent("system.reg")
        if !FileManager.default.fileExists(atPath: registry.path) {
            step("Initialising the Wine prefix (64-bit + WoW64)…")
            if !HomeFolderAccess.hasAsked {
                // A pause the player will notice gets announced before it happens. The app asks on
                // first launch instead, so this is the terminal's version of that screen.
                step("macOS may ask to let Cellar use your Documents, Desktop and Downloads folders — that is where Windows games keep their saves.")
            }
            let redirected = try wine.initializePrefix()
            try wine.setWindowsVersion("win10")
            if !redirected.isEmpty {
                let names = redirected.map(\.displayName).joined(separator: ", ")
                progress("No access to \(names), so this game's \(redirected.count == 1 ? "folder stays" : "folders stay") inside the bottle. Change it in System Settings → Privacy & Security → Files and Folders.")
            }
            let x86 = plan.prefix.appendingPathComponent("drive_c/Program Files (x86)")
            guard FileManager.default.fileExists(atPath: x86.path) else {
                throw CellarError.ioFailure(
                    "The prefix has no 'Program Files (x86)' — the runner is not a WoW64 build, and the 32-bit store clients can't install into it.")
            }
        } else {
            step("Wine prefix already initialised.")
            wine.updatePrefixIfStale()
        }

        switch plan.store {
        case .steam:
            // The client is a *runtime* dependency, not an install one: Cellar downloads the game
            // itself now, so a title whose DRM never talks to a running Steam has no reason to pull
            // a 1.4 GB client it will never start. Setting one up anyway would be an invented step,
            // and the game screen already promises not to demand it (`GameSummary.nextStep`).
            if plan.needsLiveSession {
                if !SteamBottle.isInstalled(in: plan.prefix) { phase(InstallProgress(.client)) }
                try SteamBottle.install(runner: wine, progress: step)
                // Done here rather than on first Play, where Steam would draw its own update window.
                try SteamBottle.updateClient(runner: wine, progress: step) {
                    phase(InstallProgress(.clientUpdate, fraction: $0))
                }
            } else {
                step("No Steam client needed — this game runs without a live Steam session.")
            }
        case .battlenet:
            if !BattleNetBottle.isInstalled(in: plan.prefix) { phase(InstallProgress(.client)) }
            try BattleNetBottle.install(runner: wine, progress: step)
        case .gog:
            step("No store client needed — GOG games are DRM-free, so Cellar installs and runs them directly.")
        }
        CellarLog.info(.setup, "Setup finished for \(plan.name).", subject: plan.slug)
        return wine
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
        let wine = WineRunner(install: install, prefix: plan.prefix, backend: plan.graphicsBackend, metalFX: plan.metalFXUpscaling)
        if !FileManager.default.fileExists(atPath: plan.prefix.appendingPathComponent("system.reg").path) {
            step("Initialising the Wine prefix…")
            try wine.initializePrefix(); try wine.setWindowsVersion("win10")
        }
        step("Downloading \(plan.name) (Windows depot) via DepotDownloader…")
        try DepotTool.fetch(appID: appID, into: plan.depotGameDir, credentials: credentials)
        step("Downloaded to \(plan.depotGameDir.path)")
        CellarLog.info(.install, "Depot download finished.", subject: plan.slug)
    }

    /// Install the game through its store: a depot download for Steam, the client for Battle.net,
    /// the offline installer for GOG.
    public static func installGame(_ plan: GamePlan, progress: (String) -> Void = { _ in },
                                   phase: (InstallProgress) -> Void = { _ in }) throws {
        func step(_ message: String) {
            CellarLog.debug(.install, message, subject: plan.slug)
            progress(message)
        }
        CellarLog.info(.install, "Installing \(plan.name) via \(plan.store.displayName).", subject: plan.slug)
        guard let wine = wineRunner(plan) else {
            throw CellarError.invalidArgument(
                "Runner '\(plan.runnerID)' isn't installed. Run: cellar setup --profile \(plan.slug)")
        }
        switch plan.store {
        case .steam:
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
        case .battlenet:
            // Battle.net exposes no per-product install URL Cellar could drive, so the honest
            // move is to open the client where the player can do it in two clicks.
            step("Opening Battle.net — install \(plan.name) from the client, then come back.")
            try BattleNetBottle.launchClient(runner: wine, gameEnv: plan.env)
        case .gog:
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
    }

    /// Open the store's client in the bottle (sign in, browse, manage installs).
    public static func openStoreClient(_ plan: GamePlan, showHUD: Bool = false) throws {
        CellarLog.info(.store, "Opening \(plan.store.displayName) in bottle '\(plan.bottleName)'.",
                       subject: plan.slug)
        guard let wine = wineRunner(plan) else {
            throw CellarError.invalidArgument(
                "Runner '\(plan.runnerID)' isn't installed. Run: cellar setup --profile \(plan.slug)")
        }
        switch plan.store {
        case .steam:
            guard SteamBottle.isInstalled(in: plan.prefix) else {
                throw CellarError.invalidArgument(
                    "Windows Steam isn't installed in this bottle. Run: cellar setup --profile \(plan.slug)")
            }
            try SteamBottle.updateClient(runner: wine)
            try SteamBottle.launchClient(runner: wine, showHUD: showHUD, gameEnv: plan.env)
        case .battlenet:
            guard BattleNetBottle.isInstalled(in: plan.prefix) else {
                throw CellarError.invalidArgument(
                    "Battle.net isn't installed in this bottle. Run: cellar setup --profile \(plan.slug)")
            }
            try BattleNetBottle.launchClient(runner: wine, showHUD: showHUD, gameEnv: plan.env)
        case .gog:
            throw CellarError.invalidArgument(
                "GOG has no client in the bottle — Cellar talks to GOG directly. Sign in with: cellar gog login")
        }
    }

    // MARK: - Launch

    /// Launch the game by whichever route its profile and its store call for, supervising the
    /// startup so the D3DMetal race doesn't surface as "it just didn't open".
    ///
    /// `forceStore` skips the store-free shortcut, for debugging a title that normally runs bare.
    @discardableResult
    public static func launch(_ plan: GamePlan, showHUD: Bool = false, forceStore: Bool = false,
                              checkUpdates: Bool = true,
                              stage: (LaunchStage) -> Void = { _ in },
                              update: (InstallProgress) -> Void = { _ in },
                              progress: (String) -> Void = { _ in }) throws -> LaunchRoute {
        stage(.preparing)
        // Every progress line the player reads is also kept, so a session can be reconstructed
        // afterwards from the log alone.
        func step(_ message: String) {
            CellarLog.debug(.launch, message, subject: plan.slug)
            progress(message)
        }
        CellarLog.info(.launch, "Launching \(plan.name) — store \(plan.store.rawValue), runner "
            + "\(plan.runnerID), backend \(plan.backend)\(forceStore ? ", store route forced" : "")",
            subject: plan.slug)
        do {
            let route = try route(plan, showHUD: showHUD, forceStore: forceStore,
                                  checkUpdates: checkUpdates,
                                  progress: step, stage: stage, update: update)
            Diagnostics.playSessionBegan(slug: plan.slug, name: plan.name, route: route.logDescription)
            return route
        } catch {
            CellarLog.failure(.launch, "\(plan.name) did not start", error, subject: plan.slug)
            throw error
        }
    }

    /// Pick the route and take it. Split out of `launch` so the logging above wraps every path.
    private static func route(_ plan: GamePlan, showHUD: Bool, forceStore: Bool,
                              checkUpdates: Bool,
                              progress: (String) -> Void,
                              stage: (LaunchStage) -> Void,
                              update: (InstallProgress) -> Void) throws -> LaunchRoute {
        guard let wine = wineRunner(plan) else {
            throw CellarError.invalidArgument(
                "Runner '\(plan.runnerID)' isn't installed. Run: cellar setup --profile \(plan.slug)")
        }
        // After a runner update Wine would rebuild the prefix inside this launch, with its own
        // "Please wait" box on screen. Do it first, where nothing is drawn.
        wine.updatePrefixIfStale()

        // A copy Cellar downloaded has nobody else to keep it current: Steam doesn't know it exists.
        // So Cellar does what Steam does before it starts anything — catch it up first.
        if checkUpdates, GameUpdates.managesUpdates(plan) {
            try updateBeforeLaunch(plan, progress: progress, update: update)
        }

        // No live-session DRM and the exe is on disk → run it directly, no client at all.
        if plan.canLaunchStoreFree && !forceStore {
            let exe = plan.directLaunchExe!
            progress("Launching \(plan.name) directly (no store client) — \(exe.lastPathComponent), backend \(plan.backend)…")
            stage(.starting)
            try launchDirect(plan, showHUD: showHUD)
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

        switch plan.store {
        case .steam:
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
                                                        gameEnv: plan.env, progress: progress)
                }
                progress("Starting Steam quietly for \(plan.name)'s DRM, then launching the game…")
                try SteamBottle.launchAlongside(runner: wine, exe: exe, appID: appID,
                                                showHUD: showHUD, gameEnv: plan.env,
                                                game: plan.name, expectsSignIn: signsItself,
                                                progress: progress, stage: stage)
                return .direct(exeName: exe.lastPathComponent)
            }
            guard SteamBottle.isInstalled(in: plan.prefix) else {
                throw CellarError.invalidArgument(
                    "Windows Steam isn't installed in this bottle. Run: cellar setup --profile \(plan.slug)")
            }
            let signsItself = SteamBottle.handOverSession(runner: wine, progress: progress).signsInByItself
            progress("Launching \(plan.name) via Steam (AppID \(appID)) — runner \(plan.runnerID), backend \(plan.backend)…")
            try SteamBottle.runGameSupervised(runner: wine, appID: appID, showHUD: showHUD,
                                              gameEnv: plan.env, game: plan.name, expectsSignIn: signsItself,
                                              progress: progress, stage: stage)
            stage(.running)
            return .steam(appID: appID)

        case .battlenet:
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
                                                  showHUD: showHUD, gameEnv: plan.env,
                                                  progress: progress, stage: stage)
            stage(.running)
            return .battlenet(product: product)

        case .gog:
            // Reaching here means the exe isn't on disk: a DRM-free game never needs the store route.
            throw CellarError.invalidArgument(
                "\(plan.name) isn't installed yet. Run: cellar gog install \(plan.slug)")
        }
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
        for (key, value) in plan.env { env[key] = value }
        let wineLog = Paths.logs.appendingPathComponent("game-\(plan.slug).log")
        CellarLog.debug(.launch, "Starting \(exe.lastPathComponent) directly; Wine output → "
            + wineLog.lastPathComponent, subject: plan.slug)
        try wine.spawn([exe.path], extraEnv: env, log: wineLog)
    }

    /// Block until the player quits, then take the whole layer down — the behaviour that makes
    /// Cellar feel like a game launcher rather than a pile of Wine processes.
    public static func waitForExitThenShutDown(_ plan: GamePlan, route: LaunchRoute) {
        let wine = wineRunner(plan)
        defer {
            Diagnostics.playSessionEnded(slug: plan.slug, name: plan.name,
                                         processNeedles: plan.gameProcessNeedles)
            CellarLog.debug(.session, "Layer shut down (\(route.logDescription)).", subject: plan.slug)
        }
        switch route {
        case .direct(let exeName):
            ProcessWatch.waitToExit([exeName])
            wine?.killServer()
        case .steam(let appID):
            SteamBottle.waitForGameExit(in: plan.prefix, appID: appID)
            if let wine { SteamBottle.shutdown(runner: wine) }
        case .battlenet:
            ProcessWatch.waitToExit(plan.gameProcessNeedles)
            if let wine { BattleNetBottle.shutdown(runner: wine) }
        }
    }
}
