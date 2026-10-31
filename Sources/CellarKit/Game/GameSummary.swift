import Foundation

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
        case .setup:   return String(localized: "Set up")
        case .install:
            switch store {
            case .steam:      return String(localized: "Install")
            case .battlenet:  return String(localized: "Open Battle.net")
            case .gog:        return String(localized: "Download")
            }
        case .play:    return String(localized: "Play")
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
                ? String(localized: "Cellar installs the Windows runtime and \(store.displayName) for this game. One click, a few minutes.")
                : String(localized: "Cellar installs the Windows runtime, then opens Blizzard's installer — that one needs a few clicks from you, because Battle.net ships no silent install.")
        case .install:
            // The first game on a Mac also fetches the Windows runtime. Saying so up front is what
            // keeps a few extra minutes from reading as a stall. Whole sentences either way, so a
            // translation never has to glue a clause onto another.
            switch (store, setupPending) {
            case (.steam, false):
                return String(localized: "Cellar downloads it from your Steam library with the sign-in you already gave it. No Steam window, nothing to click.")
            case (.steam, true):
                return String(localized: "Cellar downloads it from your Steam library with the sign-in you already gave it. No Steam window, nothing to click. The first time, Cellar also sets up the Windows runtime — a few extra minutes.")
            case (.battlenet, true):
                return String(localized: "Cellar sets up the Windows runtime, then Blizzard's installer opens — it needs a few clicks from you, because Battle.net ships no silent install. Then install the game from Battle.net.")
            case (.battlenet, false):
                return String(localized: "Battle.net opens. Sign in if you haven't, then install the game from there. Cellar takes over once the files are down.")
            case (.gog, false):
                return String(localized: "Cellar downloads it from your GOG library and installs it. No client, and nothing runs alongside the game.")
            case (.gog, true):
                return String(localized: "Cellar downloads it from your GOG library and installs it. No client, and nothing runs alongside the game. The first time, Cellar also sets up the Windows runtime — a few extra minutes.")
            }
        case .play:
            if updatePending {
                return String(localized: "A newer version is out. Play downloads only what changed, then starts the game.")
            }
            if clientSignInPending {
                return String(localized: "Installed. The first time, Play opens \(store.displayName)'s window so you can sign in to it, then starts the game.")
            }
            return needsClientAtRuntime
                ? String(localized: "Installed. Play starts \(store.displayName) quietly in the background and closes the whole layer when you quit.")
                : String(localized: "Installed. Play starts the game directly, without opening \(store.displayName)'s client, and closes the layer when you quit.")
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
    /// The profile's backend and its fallback, so the page can say whose choice `backend` is and
    /// the launch window can offer the fallback. Nil profile backend means "same as `backend`".
    public var profileBackend: String? = nil
    public var fallbackBackend: String? = nil
    /// Cellar guessed this game's settings (`DraftProfile`); the library shows it apart, saying so.
    public var isDraft = false
    /// The drive this game was moved to, when it isn't connected (`GameStorage`).
    public var missingDrive: String? = nil
    /// Whether the game's files live on another drive.
    public var isOnOtherDrive = false
    /// How long and how recently it was played (`Playtime`); nil when it never was.
    public var playtime: Playtime.Record? = nil
    public var lastPlayed: Date? { playtime?.lastPlayed }

    /// The player switched this game off the profile's backend.
    public var backendIsPlayerChoice: Bool { profileBackend.map { $0 != backend } ?? false }

    /// The backend to offer when a launch didn't bring the game up — see `BackendChoice.retry`.
    public var retryBackend: GraphicsBackend? {
        BackendChoice.retry(current: backend, primary: profileBackend ?? backend, fallback: fallbackBackend)
    }

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
