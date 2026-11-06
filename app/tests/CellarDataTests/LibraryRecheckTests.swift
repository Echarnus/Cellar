import CellarDomain
import Foundation
import Testing
@testable import CellarData

/// A game added by an update is asked about, not hidden until the player signs in again (#343),
/// and the player can ask by pulling the sidebar down.
///
/// Theme Hospital arrived in 0.6.5. Kenneth's Steam answers were cached from before it existed, so
/// it had no answer, read as "Cellar hasn't checked this game yet", and was withheld from a library
/// that wasn't empty, where no Check Now button shows. Nothing in the app asked Steam again.
struct LibraryRecheckTests {

    private func cache(_ apps: [String: Ownership], age: TimeInterval = 60) -> StoreLibrary.SteamCache {
        StoreLibrary.SteamCache(checkedAt: Date().addingTimeInterval(-age), account: "player", apps: apps)
    }

    @Test("A profile with no answer in the cache makes Steam due to be asked, however fresh the rest is")
    func newProfileIsAskedAbout() {
        let before = cache(["1172470": .owned, "2229820": .notOwned])
        #expect(!StoreLibrary.steamNeedsRefresh(cache: before, profileAppIDs: [1172470, 2229820]),
                "every game answered a minute ago: nothing to ask")
        let older = cache(["1172470": .owned])
        #expect(StoreLibrary.steamNeedsRefresh(cache: older, profileAppIDs: [1172470, 2229820]),
                "Theme Hospital (2229820) came with an update and has never been asked about")
    }

    @Test("Answers older than a day, or none at all, are due too")
    func staleOrMissingIsDue() {
        #expect(StoreLibrary.steamNeedsRefresh(cache: nil, profileAppIDs: [2229820]))
        let stale = cache(["2229820": .owned], age: StoreLibrary.cacheLifetime + 60)
        #expect(StoreLibrary.steamNeedsRefresh(cache: stale, profileAppIDs: [2229820]))
    }

    @Test("The app asks the stores at every launch and when due, and a pull on the sidebar asks too")
    func appAsksWhenDue() throws {
        // The loop and the gesture need a running app; what can break is the hand-off, so that is
        // what is checked.
        let source = try String(contentsOf: Repo.app.appendingPathComponent(
            "src/CellarApp/Features/Library/LibraryView.swift"), encoding: .utf8)
        #expect(source.contains(".task { await keepOwnershipCurrent() }"), "the check must start with the window")
        let loop = try #require(source.range(of: "private func keepOwnershipCurrent()"), "the loop moved")
        let body = source[loop.lowerBound...].prefix(1400)
        #expect(body.contains("!Self.askedThisLaunch"), "Kenneth: checked at startup, every launch")
        #expect(body.contains("StoreLibrary.steamNeedsRefresh"))
        #expect(body.contains("runner.runBeside(.refreshLibrary)"))
        #expect(source.contains("if pull.update(overscroll: overscroll) { checkLibrary() }"),
                "pulling the sidebar down asks the stores again")
    }

    @Test("A pull asks once, when it passes the threshold, and again only after the list comes to rest")
    func pullFiresOncePerGesture() {
        var pull = PullToRefresh()
        let asked1 = pull.update(overscroll: 8)
        #expect(!asked1, "the bounce at the top of a short list is not a request")
        let asked2 = pull.update(overscroll: PullToRefresh.threshold - 1)
        #expect(!asked2)
        let asked3 = pull.update(overscroll: PullToRefresh.threshold)
        #expect(asked3, "past the threshold: ask")
        let asked4 = pull.update(overscroll: PullToRefresh.threshold + 30)
        #expect(!asked4, "still the same pull")
        let asked5 = pull.update(overscroll: 20)
        #expect(!asked5)
        let asked6 = pull.update(overscroll: 0)
        #expect(!asked6, "back at rest")
        #expect(pull.progress == 0)
        let asked7 = pull.update(overscroll: PullToRefresh.threshold + 5)
        #expect(asked7, "a new pull asks again")
    }

    @Test("Scrolling down the list is never a pull")
    func scrollingIsNotAPull() {
        var pull = PullToRefresh()
        for offset in stride(from: 0.0, through: -800, by: -40) {
            let asked = pull.update(overscroll: offset)
            #expect(!asked)
        }
        #expect(pull.distance == 0)
    }

    // MARK: - Asking too often got the sign-in refused (#345)

    @Test("A launch asks Steam only when the answers are over an hour old, or a game has none")
    func launchAsksOnlyWhenAnHourOld() {
        let fresh = cache(["2229820": .owned], age: 10 * 60)
        #expect(!StoreLibrary.steamLaunchCheckDue(cache: fresh, profileAppIDs: [2229820]),
                "0.6.7 asked at every launch: dozens of times a day, and Steam refused the sign-in")
        let hourOld = cache(["2229820": .owned], age: StoreLibrary.launchCheckInterval + 60)
        #expect(StoreLibrary.steamLaunchCheckDue(cache: hourOld, profileAppIDs: [2229820]))
        #expect(StoreLibrary.steamLaunchCheckDue(cache: fresh, profileAppIDs: [2229820, 1172470]),
                "a game added by an update is still asked about at once (#343)")
        #expect(StoreLibrary.steamLaunchCheckDue(cache: nil, profileAppIDs: [2229820]))
    }

    @Test("Asks moments apart reuse the answer instead of trading the sign-in again")
    func asksMomentsApartReuseTheAnswer() {
        let apps: [String: Ownership] = ["2229820": .owned, "1172470": .notOwned]
        let now = cache(apps, age: 20)
        #expect(StoreLibrary.justAsked(now, account: "PLAYER", appIDs: [2229820, 1172470]) == apps,
                "the app, the CLI and a pull asked within seconds of each other")
        #expect(StoreLibrary.justAsked(now, account: "someone-else", appIDs: [2229820]) == nil,
                "another account's answers are never this account's")
        #expect(StoreLibrary.justAsked(now, account: "player", appIDs: [2229820, 999]) == nil,
                "a game with no answer is asked about")
        let older = cache(apps, age: StoreLibrary.minimumAskGap + 5)
        #expect(StoreLibrary.justAsked(older, account: "player", appIDs: [2229820]) == nil)
    }

    @Test("The app's launch check uses the hourly rule, not the old ask-every-launch")
    func appUsesTheLaunchRule() throws {
        let source = try String(contentsOf: Repo.app.appendingPathComponent(
            "src/CellarApp/Features/Library/LibraryView.swift"), encoding: .utf8)
        let loop = try #require(source.range(of: "private func keepOwnershipCurrent()"))
        let body = source[loop.lowerBound...].prefix(1400)
        #expect(body.contains("StoreLibrary.steamLaunchCheckDue"))
        #expect(!body.contains("var due = !Self.askedThisLaunch"), "asking at every launch is what broke the sign-in")
    }

    @Test("A library check that would replace the sign-in is noticed, and the refusal is logged in Steam's words")
    func renewalAndRefusalAreVisible() {
        #expect(SteamOwnedGames.renewedRefreshToken(["response": ["access_token": "a", "refresh_token": "r"]]))
        #expect(!SteamOwnedGames.renewedRefreshToken(["response": ["access_token": "a"]]))
        #expect(!SteamOwnedGames.renewedRefreshToken(["response": ["access_token": "a", "refresh_token": ""]]))
        #expect(SteamAccount.rejection(in: "Access token was rejected (AccessDenied).") == "accessdenied")
    }
}
