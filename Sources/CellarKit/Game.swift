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
    public let running: Bool           // the store's client is up
    /// Battle.net's equivalent of an AppID — how its client names this game (`Fen` = Diablo IV).
    public let productCode: String?
    /// Steam AppID to pull public artwork with — nil for stores that publish none.
    public let artworkAppID: Int?
    public let artPortraitURL: String?
    public let artHeroURL: String?

    public var id: String { slug }

    /// The single most useful next action given the current state.
    public enum NextStep: Sendable {
        case setup      // no runner, or no store client yet
        case signIn     // the client is there and we can see nobody is signed in
        case install    // signed in (or we can't tell), game not installed
        case play       // ready
    }

    public var nextStep: NextStep {
        if !runnerInstalled || !clientInstalled { return .setup }
        // Only Steam publishes a readable sign-in state. For Battle.net, signing in and installing
        // both happen inside the client's own window, so they are one step — claiming to know
        // otherwise would put a button in front of the player that can't be trusted.
        if store.descriptor.canDetectSignIn, account == nil { return .signIn }
        if !gameInstalled { return .install }
        return .play
    }

    /// The primary button's title. Store-specific on purpose: "Install" means something different
    /// in a client that installs games for you than in one Cellar drives itself.
    public var actionTitle: String {
        switch nextStep {
        case .setup:   return "Set up"
        case .signIn:  return "Sign in to \(store.displayName)"
        case .install:
            switch store {
            case .steam:      return "Install"
            case .battlenet:  return "Open Battle.net"
            case .gog:        return "Download"
            case .standalone: return "Download"
            }
        case .play:    return "Play"
        }
    }

    public var actionSymbol: String {
        switch nextStep {
        case .play:   return "play.fill"
        case .setup:  return "wrench.and.screwdriver.fill"
        case .signIn: return "person.crop.circle.fill"
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
        case .signIn:
            // A token store is signed in once for the whole account; a client store is signed in
            // inside its own window. Promising the wrong one is exactly the dishonesty ux.md forbids.
            switch store.descriptor.authStyle {
            case .cellarHeldToken:
                return "Sign in to \(store.displayName) once — it covers every \(store.displayName) game, not just this one."
            case .inClientWindow, .none:
                return "Sign in to your \(store.descriptor.accountNoun). A \(store.displayName) window opens; the QR code with the mobile app is quickest."
            }
        case .install:
            switch store {
            case .steam:      return "Install the game — Cellar asks Steam to download it. You already own it."
            case .battlenet:  return "Battle.net opens. Sign in if you haven't, then install the game from there. Cellar takes over once the files are down."
            case .gog:        return "Cellar downloads it from your GOG library and installs it. No client, and nothing runs alongside the game."
            case .standalone: return "Cellar downloads the game's files straight from your library — no store client involved."
            }
        case .play:
            return needsClientAtRuntime
                ? "Ready. Play starts \(store.displayName) quietly in the background and closes the whole layer when you quit."
                : "Ready. Play runs the game directly — no store client at all — and closes the layer when you quit."
        }
    }

    /// Whether playing this game will bring a store client up alongside it.
    public let needsClientAtRuntime: Bool
    /// What the profile says about the game — the app's information panel.
    public let facts: GameFacts
    /// The runtime this profile pins, for the app to show without re-reading the TOML.
    public let runnerID: String
    public let backend: String
    public let bottleName: String

    public init(slug: String, name: String, store: GameStore, appID: Int?, iconPath: String?,
                runnerInstalled: Bool, clientInstalled: Bool, account: String?, gameInstalled: Bool,
                running: Bool, productCode: String?, artworkAppID: Int?,
                artPortraitURL: String?, artHeroURL: String?,
                needsClientAtRuntime: Bool, facts: GameFacts, runnerID: String, backend: String,
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
        self.running = running
        self.productCode = productCode
        self.artworkAppID = artworkAppID
        self.artPortraitURL = artPortraitURL
        self.artHeroURL = artHeroURL
        self.needsClientAtRuntime = needsClientAtRuntime
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
                                                    appID: plan.appID, installDir: plan.installDir)?.path,
                runnerInstalled: RunnerManager.find(id: plan.runnerID) != nil,
                clientInstalled: clientInstalled,
                account: clientInstalled ? signedInAccount(plan) : nil,
                gameInstalled: isGameInstalled(plan),
                running: storeClientRunning(plan),
                productCode: plan.productCode,
                // Only Steam publishes free cover art keyed on an app id; everything else has to
                // bring its own URLs or fall back to Cellar's generated cover.
                artworkAppID: plan.store == .steam ? plan.appID : nil,
                artPortraitURL: plan.artPortraitURL,
                artHeroURL: plan.artHeroURL,
                needsClientAtRuntime: !plan.canLaunchStoreFree,
                facts: plan.facts,
                runnerID: plan.runnerID,
                backend: plan.backend,
                bottleName: plan.bottleName)
        }
    }

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
                notes: fields["notes"])
        )
    }

    static func defaultInstallMethod(for store: GameStore) -> String {
        switch store {
        case .steam:      return "windows-steam-in-bottle"
        case .battlenet:  return "battlenet-in-bottle"
        case .gog:        return "gog-installer"
        case .standalone: return "depot"
        }
    }

    /// The bottle's Wine runner, if the runner is installed.
    public static func wineRunner(_ plan: GamePlan) -> WineRunner? {
        guard let install = RunnerManager.find(id: plan.runnerID) else { return nil }
        return WineRunner(install: install, prefix: plan.prefix, backend: plan.graphicsBackend)
    }

    // MARK: - Store-aware state

    /// Whether the store's client is present in the bottle. A standalone game needs no client, so
    /// it is "installed" by definition and never asks the player to set one up.
    public static func storeClientInstalled(_ plan: GamePlan) -> Bool {
        switch plan.store {
        case .steam:      return SteamBottle.isInstalled(in: plan.prefix)
        case .battlenet:  return BattleNetBottle.isInstalled(in: plan.prefix)
        // GOG needs no client in the bottle at all, so there is never one to set up.
        case .gog:        return true
        case .standalone: return true
        }
    }

    public static func storeClientRunning(_ plan: GamePlan) -> Bool {
        switch plan.store {
        case .steam:      return SteamBottle.isRunning
        case .battlenet:  return BattleNetBottle.isRunning
        case .gog:        return false
        case .standalone: return false
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
        case .standalone: return nil
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
    public static func setUp(_ plan: GamePlan, progress: (String) -> Void) throws -> WineRunner {
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

        let install = try RunnerManager.install(spec, progress: step)
        let wine = WineRunner(install: install, prefix: plan.prefix, backend: plan.graphicsBackend)

        if !FileManager.default.fileExists(atPath: plan.prefix.path) {
            step("Creating bottle '\(plan.bottleName)'…")
            try PrefixManager.create(name: plan.bottleName, backend: plan.graphicsBackend, runner: plan.runnerID)
        }

        let registry = plan.prefix.appendingPathComponent("system.reg")
        if !FileManager.default.fileExists(atPath: registry.path) {
            step("Initialising the Wine prefix (64-bit + WoW64)…")
            try wine.initializePrefix()
            try wine.setWindowsVersion("win10")
            let x86 = plan.prefix.appendingPathComponent("drive_c/Program Files (x86)")
            guard FileManager.default.fileExists(atPath: x86.path) else {
                throw CellarError.ioFailure(
                    "The prefix has no 'Program Files (x86)' — the runner is not a WoW64 build, and the 32-bit store clients can't install into it.")
            }
        } else {
            step("Wine prefix already initialised.")
        }

        switch plan.store {
        case .steam:
            try SteamBottle.install(runner: wine, progress: step)
        case .battlenet:
            try BattleNetBottle.install(runner: wine, progress: step)
        case .gog:
            step("No store client needed — GOG games are DRM-free, so Cellar installs and runs them directly.")
        case .standalone:
            step("No store client needed — this game runs straight from its files.")
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
        let wine = WineRunner(install: install, prefix: plan.prefix, backend: plan.graphicsBackend)
        if !FileManager.default.fileExists(atPath: plan.prefix.appendingPathComponent("system.reg").path) {
            step("Initialising the Wine prefix…")
            try wine.initializePrefix(); try wine.setWindowsVersion("win10")
        }
        step("Downloading \(plan.name) (Windows depot) via DepotDownloader…")
        try DepotTool.fetch(appID: appID, into: plan.depotGameDir, credentials: credentials)
        step("Downloaded to \(plan.depotGameDir.path)")
        CellarLog.info(.install, "Depot download finished.", subject: plan.slug)
    }

    /// Ask the store's client to install the game (or, for a standalone title, say what to run).
    public static func installGame(_ plan: GamePlan, progress: (String) -> Void = { _ in }) throws {
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
            step("Asking the bottle's Steam to install \(plan.name) (AppID \(appID))…")
            try SteamBottle.installGame(runner: wine, appID: appID)
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
            let parts = try GOGInstall.download(productID: productID, progress: step)
            try GOGInstall.install(setup: parts[0], slug: plan.slug, runner: wine, progress: step)
            guard plan.directLaunchExe != nil else {
                throw CellarError.ioFailure(
                    "The installer finished but Cellar can't find '\(plan.launchExe ?? "the game's exe")' under C:\\Games\\\(plan.slug). Check the profile's `exe`.")
            }
            step("\(plan.name) is installed. Play it with: cellar launch \(plan.slug)")
        case .standalone:
            throw CellarError.invalidArgument(
                "\(plan.name) has no store client. Download it with: cellar fetch-depot \(plan.slug) --username <steam-account>")
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
        case .standalone:
            throw CellarError.invalidArgument("\(plan.name) has no store client to open.")
        }
    }

    // MARK: - Launch

    /// Launch the game by whichever route its profile and its store call for, supervising the
    /// startup so the D3DMetal race doesn't surface as "it just didn't open".
    ///
    /// `forceStore` skips the store-free shortcut, for debugging a title that normally runs bare.
    @discardableResult
    public static func launch(_ plan: GamePlan, showHUD: Bool = false, forceStore: Bool = false,
                              progress: (String) -> Void = { _ in }) throws -> LaunchRoute {
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
            let route = try route(plan, showHUD: showHUD, forceStore: forceStore, progress: step)
            Diagnostics.playSessionBegan(slug: plan.slug, name: plan.name, route: route.logDescription)
            return route
        } catch {
            CellarLog.failure(.launch, "\(plan.name) did not start", error, subject: plan.slug)
            throw error
        }
    }

    /// Pick the route and take it. Split out of `launch` so the logging above wraps every path.
    private static func route(_ plan: GamePlan, showHUD: Bool, forceStore: Bool,
                              progress: (String) -> Void) throws -> LaunchRoute {
        guard let wine = wineRunner(plan) else {
            throw CellarError.invalidArgument(
                "Runner '\(plan.runnerID)' isn't installed. Run: cellar setup --profile \(plan.slug)")
        }

        // No live-session DRM and the exe is on disk → run it directly, no client at all.
        if plan.canLaunchStoreFree && !forceStore {
            let exe = plan.directLaunchExe!
            progress("Launching \(plan.name) directly (no store client) — \(exe.lastPathComponent), backend \(plan.backend)…")
            try launchDirect(plan, showHUD: showHUD)
            return .direct(exeName: exe.lastPathComponent)
        }

        switch plan.store {
        case .steam:
            guard SteamBottle.isInstalled(in: plan.prefix) else {
                throw CellarError.invalidArgument(
                    "Windows Steam isn't installed in this bottle. Run: cellar setup --profile \(plan.slug)")
            }
            guard let appID = plan.appID else {
                throw CellarError.invalidArgument("Profile '\(plan.slug)' has no steam_appid to launch.")
            }
            progress("Launching \(plan.name) via Steam (AppID \(appID)) — runner \(plan.runnerID), backend \(plan.backend)…")
            try SteamBottle.runGameSupervised(runner: wine, appID: appID, showHUD: showHUD,
                                              gameEnv: plan.env, progress: progress)
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
                                                  showHUD: showHUD, gameEnv: plan.env, progress: progress)
            return .battlenet(product: product)

        case .gog:
            // Reaching here means the exe isn't on disk: a DRM-free game never needs the store route.
            throw CellarError.invalidArgument(
                "\(plan.name) isn't installed yet. Run: cellar gog install \(plan.slug)")
        case .standalone:
            throw CellarError.invalidArgument(
                "No launchable exe found for '\(plan.slug)'. Run: cellar fetch-depot \(plan.slug) --username <steam-account>")
        }
    }

    /// Launch the game's exe directly through Wine — no store client. Only valid when `canLaunchStoreFree`.
    public static func launchDirect(_ plan: GamePlan, showHUD: Bool = false) throws {
        guard let wine = wineRunner(plan) else {
            throw CellarError.invalidArgument("Runner '\(plan.runnerID)' isn't installed.")
        }
        guard let exe = plan.directLaunchExe else {
            throw CellarError.invalidArgument(
                "No launchable exe found for '\(plan.slug)'. Run: cellar fetch-depot \(plan.slug) --username <steam-account>")
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
