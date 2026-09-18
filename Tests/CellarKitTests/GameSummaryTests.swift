import Foundation
import Testing
@testable import CellarKit

/// The readiness ladder and the copy hanging off it.
///
/// `GameSummary` decides the one action a game's page offers and the sentence under it. In this
/// repo that is not cosmetic: `skills/ux.md` forbids showing a state Cellar cannot verify, and the
/// ladder is where that promise is kept or broken.
@Suite
struct GameSummaryTests {

    /// A summary with every knob defaulted to "ready", so a test can turn exactly one off.
    private func summary(store: GameStore = .steam,
                         runnerInstalled: Bool = true,
                         clientInstalled: Bool = true,
                         account: String? = "kenneth",
                         gameInstalled: Bool = true,
                         bottleExists: Bool = true,
                         running: Bool = false,
                         needsLiveSession: Bool = true,
                         needsClientAtRuntime: Bool = true,
                         clientSignsInByItself: Bool = false) -> GameSummary {
        GameSummary(slug: "fixture", name: "Fixture", store: store, appID: 1, iconPath: nil,
                    runnerInstalled: runnerInstalled, clientInstalled: clientInstalled,
                    account: account, gameInstalled: gameInstalled, bottleExists: bottleExists,
                    running: running,
                    productCode: nil, needsLiveSession: needsLiveSession,
                    clientSignsInByItself: clientSignsInByItself, artworkAppID: nil, artPortraitURL: nil, artHeroURL: nil,
                    needsClientAtRuntime: needsClientAtRuntime,
                    facts: GameFacts(developer: nil, released: nil, engine: nil, graphicsAPI: nil,
                                     anticheat: nil, drm: nil, online: nil, requiresAccount: nil,
                                     status: nil, notes: nil),
                    runnerID: "wineforge", backend: "d3dmetal", bottleName: "fixture")
    }

    // MARK: - The ladder

    @Test("A game that isn't installed is one Install away, whatever still has to be set up",
          arguments: GameStore.allCases)
    func installCoversSetup(_ store: GameStore) {
        // Install sets up the runtime, the bottle and any client before it fetches the game, so a
        // separate "Set up" first would be a button that asks the player nothing.
        #expect(summary(store: store, runnerInstalled: false, clientInstalled: false,
                        account: nil, gameInstalled: false).nextStep == .install)
        #expect(summary(store: store, clientInstalled: false, gameInstalled: false).nextStep == .install)
    }

    @Test("Setup survives only as repair: the game is there, what it runs on is not")
    func setupIsRepair() {
        #expect(summary(runnerInstalled: false).nextStep == .setup)
        #expect(summary(clientInstalled: false).nextStep == .setup)
        // A game that needs no live client is not sent to repair one it never uses.
        #expect(summary(clientInstalled: false, needsLiveSession: false).nextStep == .play)
    }

    @Test("The ladder climbs install → play, with no sign-in rung of its own")
    func ladderOrder() {
        #expect(summary(gameInstalled: false).nextStep == .install)
        // Signing in to the in-bottle client is folded into Play: a separate "Sign in to Steam"
        // beside a Settings row saying "Signed in" read as Cellar asking twice.
        #expect(summary(account: nil).nextStep == .play)
        #expect(summary().nextStep == .play)
    }

    @Test("Install copy says when the first game also sets up the runtime")
    func installCopyNamesFirstTimeSetup() {
        for store in [GameStore.steam, .gog] {
            let first = summary(store: store, runnerInstalled: false, gameInstalled: false).actionHint
            #expect(first.contains("Windows runtime"), "a few silent minutes read as a stall: \(store)")
            let later = summary(store: store, gameInstalled: false).actionHint
            #expect(!later.contains("Windows runtime"), "only the first time: \(store)")
        }
        let blizzard = summary(store: .battlenet, clientInstalled: false, account: nil,
                               gameInstalled: false).actionHint
        #expect(blizzard.contains("clicks from you"),
                "Install now runs Blizzard's installer, so it inherits the warning")
    }

    @Test("Battle.net is never asked to sign in, because Cellar cannot tell")
    func battleNetNeverShowsSignIn() {
        // Blizzard publishes no equivalent of loginusers.vdf. Offering a "Sign in" button here
        // would be a button Cellar cannot follow up on — signing in happens in the client's window,
        // which is the same window "Open Battle.net" already opens.
        let unknown = summary(store: .battlenet, account: nil, gameInstalled: false)
        #expect(unknown.nextStep == .install)
        #expect(unknown.actionTitle == "Open Battle.net")

        let ready = summary(store: .battlenet, account: nil)
        #expect(ready.nextStep == .play)
    }

    @Test("Only the in-bottle client's sign-in is still asked for, and only as part of Play")
    func onlyTheInBottleClientAsksForSignIn() {
        // Steam's client lives in the bottle and keeps its own session. When Cellar can't hand it the
        // player's, a Steamworks game must say so, or it fails its licence check with nothing on
        // screen having warned anyone.
        let steam = summary(store: .steam, account: nil)
        #expect(steam.clientSignInPending)
        #expect(steam.launchContext.signsInFirst)
        #expect(!summary(store: .steam).clientSignInPending, "a signed-in client is not asked again")
        let handedOver = summary(store: .steam, account: nil, clientSignsInByItself: true)
        #expect(!handedOver.clientSignInPending, "a client Cellar signs in itself never asks the player")
        #expect(!handedOver.launchContext.signsInFirst)
        #expect(!handedOver.actionHint.contains("sign in"))
        #expect(!summary(store: .steam, account: nil, needsLiveSession: false).clientSignInPending,
                "a game that never talks to the client never waits on its sign-in")

        // GOG holds a Cellar token and stands no client up; Battle.net cannot be read. Neither is
        // ever promised a sign-in it will not get.
        #expect(!summary(store: .gog, account: nil).clientSignInPending)
        #expect(!summary(store: .battlenet, account: nil).clientSignInPending)
    }

    @Test("A Steam game with no live-session DRM never waits on the in-bottle client")
    func steamWithoutLiveSessionSkipsClient() {
        let bare = summary(store: .steam, clientInstalled: false, account: nil, gameInstalled: false,
                           needsLiveSession: false, needsClientAtRuntime: false)
        #expect(bare.nextStep == .install)
        #expect(!bare.setupPending, "no 1.4 GB client for a game that never talks to it")
        let installed = summary(store: .steam, clientInstalled: false, account: nil,
                                needsLiveSession: false, needsClientAtRuntime: false)
        #expect(installed.nextStep == .play)
        #expect(!installed.clientSignInPending)
        #expect(installed.actionHint.contains("no store client"))
    }

    // MARK: - Copy

    @Test("Every reachable state has a title, a symbol and a full sentence",
          arguments: GameStore.allCases)
    func everyStateHasCopy(_ store: GameStore) {
        let states = [summary(store: store, runnerInstalled: false),
                      summary(store: store, runnerInstalled: false, gameInstalled: false),
                      summary(store: store, account: nil),
                      summary(store: store, gameInstalled: false),
                      summary(store: store)]
        for state in states {
            #expect(!state.actionTitle.isEmpty)
            #expect(!state.actionSymbol.isEmpty)
            let hint = state.actionHint
            #expect(!hint.isEmpty)
            #expect(hint.hasSuffix(".") || hint.hasSuffix("…"),
                    "the hint is a sentence, not a fragment: \"\(hint)\"")
            #expect(hint.first!.isUppercase, "sentence case: \"\(hint)\"")
        }
    }

    @Test("The install button says what that store actually does")
    func installTitlesAreStoreSpecific() {
        #expect(summary(store: .steam, gameInstalled: false).actionTitle == "Install")
        #expect(summary(store: .battlenet, account: nil, gameInstalled: false).actionTitle == "Open Battle.net",
                "Battle.net does the installing; Cellar only opens the window")
        #expect(summary(store: .gog, gameInstalled: false).actionTitle == "Download")
    }

    @Test("A client that still needs a sign-in keeps the Play button, and its hint says what opens")
    func pendingClientSignInStillPlays() {
        let pending = summary(store: .steam, account: nil)
        #expect(pending.actionTitle == "Play")
        #expect(pending.actionHint.contains("Steam's window"))
        #expect(pending.actionHint.contains("sign in"))
    }

    @Test("Setup copy warns about Battle.net's non-silent installer, and only Battle.net's")
    func setupCopyWarnsWhereItMust() {
        let blizzard = summary(store: .battlenet, runnerInstalled: false).actionHint
        #expect(blizzard.contains("clicks from you"),
                "an unexplained pause while a Blizzard window opens reads as a hang")

        for store in [GameStore.steam, .gog] {
            let hint = summary(store: store, runnerInstalled: false).actionHint
            #expect(hint.contains("One click"))
        }
    }

    @Test("A per-window sign-in says so; an account-level one never reaches a game's page")
    func signInCopyMatchesAuthStyle() {
        // A GOG game with no account is ready to play, so its hint must not imply a sign-in the
        // page is not going to offer — the honesty rule in skills/ux.md cuts both ways.
        let gog = summary(store: .gog, account: nil).actionHint
        #expect(!gog.lowercased().contains("sign in"))

        let steam = summary(store: .steam, account: nil).actionHint
        #expect(steam.contains("window"), "Steam's sign-in happens in Steam's own window")
    }

    @Test("Play copy tells the truth about whether a client comes up alongside the game")
    func playCopyMatchesRuntimeShape() {
        let withClient = summary(needsClientAtRuntime: true).actionHint
        #expect(withClient.contains("in the background"))

        let bare = summary(needsClientAtRuntime: false).actionHint
        #expect(bare.contains("no store client at all"))
        #expect(bare.contains("in the background") == false)
    }

    @Test("The action symbol distinguishes opening a client from downloading a game")
    func symbolsMatchTheAction() {
        #expect(summary().actionSymbol == "play.fill")
        #expect(summary(runnerInstalled: false).actionSymbol == "wrench.and.screwdriver.fill")
        #expect(summary(gameInstalled: false).actionSymbol == "arrow.down.circle.fill")
        #expect(summary(store: .battlenet, gameInstalled: false).actionSymbol == "arrow.up.forward.app.fill",
                "Battle.net opens outward; it does not download here")
    }

    @Test("A summary is identified by its slug, so the library list stays stable")
    func identity() {
        #expect(summary().id == "fixture")
    }

    // MARK: - Facts

    @Test("Facts list only what the profile actually states")
    func factsSkipUnknowns() {
        let partial = GameFacts(developer: "Frontier", released: nil, engine: "COBRA",
                                graphicsAPI: nil, anticheat: "none", drm: nil, online: nil,
                                requiresAccount: nil, status: "playable", notes: nil)
        #expect(partial.about.map(\.label) == ["Developer", "Engine"])
        #expect(partial.compatibility.map(\.label) == ["Anti-cheat"])

        let empty = GameFacts(developer: nil, released: nil, engine: nil, graphicsAPI: nil,
                              anticheat: nil, drm: nil, online: nil, requiresAccount: nil,
                              status: nil, notes: nil)
        #expect(empty.about.isEmpty)
        #expect(empty.compatibility.isEmpty)
    }

    @Test("Facts read in the documented order")
    func factsOrder() {
        let full = GameFacts(developer: "d", released: "r", engine: "e", graphicsAPI: "g",
                             anticheat: "a", drm: "m", online: "o", requiresAccount: "q",
                             status: "playable", notes: "n")
        #expect(full.about.map(\.label) == ["Developer", "Released", "Engine", "Graphics"])
        #expect(full.compatibility.map(\.label) == ["Anti-cheat", "DRM", "Online", "Account"])
    }
}
