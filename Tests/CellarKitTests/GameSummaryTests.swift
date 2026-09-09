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
                         running: Bool = false,
                         needsClientAtRuntime: Bool = true) -> GameSummary {
        GameSummary(slug: "fixture", name: "Fixture", store: store, appID: 1, iconPath: nil,
                    runnerInstalled: runnerInstalled, clientInstalled: clientInstalled,
                    account: account, gameInstalled: gameInstalled, running: running,
                    productCode: nil, artworkAppID: nil, artPortraitURL: nil, artHeroURL: nil,
                    needsClientAtRuntime: needsClientAtRuntime,
                    facts: GameFacts(developer: nil, released: nil, engine: nil, graphicsAPI: nil,
                                     anticheat: nil, drm: nil, online: nil, requiresAccount: nil,
                                     status: nil, notes: nil),
                    runnerID: "wineforge", backend: "d3dmetal", bottleName: "fixture")
    }

    // MARK: - The ladder

    @Test("A missing runner is a setup step, whatever else is true")
    func noRunnerMeansSetup() {
        #expect(summary(runnerInstalled: false).nextStep == .setup)
        #expect(summary(runnerInstalled: false, clientInstalled: false,
                        account: nil, gameInstalled: false).nextStep == .setup)
    }

    @Test("A missing store client is a setup step")
    func noClientMeansSetup() {
        #expect(summary(clientInstalled: false).nextStep == .setup)
    }

    @Test("The ladder climbs setup → sign in → install → play")
    func ladderOrder() {
        #expect(summary(runnerInstalled: false).nextStep == .setup)
        #expect(summary(account: nil).nextStep == .signIn)
        #expect(summary(gameInstalled: false).nextStep == .install)
        #expect(summary().nextStep == .play)
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

    @Test("A store that can read its sign-in does show the step", arguments: [GameStore.steam, .gog])
    func detectableStoresShowSignIn(_ store: GameStore) {
        #expect(summary(store: store, account: nil).nextStep == .signIn)
    }

    @Test("Standalone games skip sign-in entirely — there is no account")
    func standaloneSkipsSignIn() {
        #expect(summary(store: .standalone, account: nil, gameInstalled: false).nextStep == .install)
        #expect(summary(store: .standalone, account: nil).nextStep == .play)
    }

    // MARK: - Copy

    @Test("Every reachable state has a title, a symbol and a full sentence",
          arguments: GameStore.allCases)
    func everyStateHasCopy(_ store: GameStore) {
        let states = [summary(store: store, runnerInstalled: false),
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
        #expect(summary(store: .standalone, gameInstalled: false).actionTitle == "Download")
    }

    @Test("The sign-in button names the store, so it is never an anonymous verb")
    func signInNamesTheStore() {
        #expect(summary(store: .steam, account: nil).actionTitle == "Sign in to Steam")
        #expect(summary(store: .gog, account: nil).actionTitle == "Sign in to GOG")
    }

    @Test("Setup copy warns about Battle.net's non-silent installer, and only Battle.net's")
    func setupCopyWarnsWhereItMust() {
        let blizzard = summary(store: .battlenet, runnerInstalled: false).actionHint
        #expect(blizzard.contains("clicks from you"),
                "an unexplained pause while a Blizzard window opens reads as a hang")

        for store in [GameStore.steam, .gog, .standalone] {
            let hint = summary(store: store, runnerInstalled: false).actionHint
            #expect(hint.contains("One click"))
        }
    }

    @Test("A once-per-account sign-in says so; a per-window one does not")
    func signInCopyMatchesAuthStyle() {
        let gog = summary(store: .gog, account: nil).actionHint
        #expect(gog.contains("once"))
        #expect(gog.contains("every GOG game"))

        let steam = summary(store: .steam, account: nil).actionHint
        #expect(steam.contains("window opens"), "Steam's sign-in happens in Steam's own window")
        #expect(steam.contains("QR"))
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
        #expect(summary(account: nil).actionSymbol == "person.crop.circle.fill")
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
