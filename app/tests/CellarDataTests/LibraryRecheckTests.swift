import CellarDomain
import Foundation
import Testing
@testable import CellarData

/// A game added by an update is asked about, not hidden until the player signs in again (#343).
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

    @Test("The app asks Steam by itself when it is due, in the loop that keeps games current")
    func appAsksWhenDue() throws {
        // The loop needs a running app; what can break is the hand-off, so that is what is checked.
        let source = try String(contentsOf: Repo.app.appendingPathComponent(
            "src/CellarApp/Features/Library/LibraryView.swift"), encoding: .utf8)
        let loop = try #require(source.range(of: "private func keepGamesCurrent()"), "the loop moved")
        let body = source[loop.lowerBound...].prefix(2400)
        #expect(body.contains("StoreLibrary.steamNeedsRefresh"))
        #expect(body.contains("runner.runBeside(.refreshLibrary)"))
    }
}
