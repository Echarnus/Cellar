import CellarDomain
import Foundation
import Testing
@testable import CellarData

/// Each Steam ownership check is a whole DepotDownloader sign-in, so they run side by side. These pin
/// the three things that makes safe: every game gets an answer, no two running checks share a logon
/// id (Steam signs the older session out), and progress is reported once per answer.
struct SteamOwnershipCheckTests {

    @Test("Every game is asked about exactly once, and its own answer comes back")
    func everyItemAnswered() {
        let ids = Array(1...11)
        let answers = StoreLibrary.askSideBySide(ids, width: 4) { id, _ in id * 10 }
        #expect(answers.count == ids.count)
        for id in ids { #expect(answers[id] == id * 10) }
    }

    @Test("Checks run side by side, never with more than `width` at once")
    func runsConcurrentlyWithinWidth() {
        let probe = Probe()
        let started = Date()
        _ = StoreLibrary.askSideBySide(Array(0..<8), width: 4) { _, slot in
            probe.enter(slot)
            Thread.sleep(forTimeInterval: 0.1)
            probe.leave(slot)
            return true
        }
        let elapsed = Date().timeIntervalSince(started)
        #expect(probe.peak > 1, "checks ran one at a time")
        #expect(probe.peak <= 4)
        // In turn this is 0.8 s; four at a time, about 0.2 s.
        #expect(elapsed < 0.6)
        #expect(!probe.sharedSlot, "two running checks were given the same logon slot")
    }

    @Test("Progress counts up once per answer")
    func progressCountsUp() {
        var counts: [Int] = []
        _ = StoreLibrary.askSideBySide(Array(0..<5), width: 3, ask: { _, _ in 0 }) { count in
            counts.append(count)
        }
        #expect(counts == [1, 2, 3, 4, 5])
    }

    @Test("Nothing to ask returns at once")
    func emptyInput() {
        let answers: [Int: Int] = StoreLibrary.askSideBySide([], width: 4) { _, _ in 1 }
        #expect(answers.isEmpty)
    }

    @Test("A sign-in Steam turned away is retried, not read as an answer")
    func alreadyLoggedInElsewhereIsBusy() {
        #expect(DepotTool.probeVerdict(in: "Unable to login to Steam3: AlreadyLoggedInElsewhere") == .busy)
        #expect(DepotTool.probeVerdict(in: "App 413150 (Stardew Valley) is not available from this account.")
                == .answer(.unavailable))
        #expect(DepotTool.probeVerdict(in: "Using app branch: 'public'.") == .answer(.available))
        #expect(DepotTool.probeVerdict(in: "Got 379 licenses for account!") == nil)
    }

    @Test("A free licence the check itself obtained is not ownership (#272)")
    func claimedFreeIsNotOwned() {
        // DepotDownloader asks Steam for a free-on-demand licence before giving up, then carries on as
        // if the game were owned. The claim settles it: the player never added this game.
        #expect(DepotTool.probeVerdict(in: "Obtained FreeOnDemand license for app 730")
                == .answer(.claimedFree))

        var claimed: Set<String> = []
        let first = StoreLibrary.steamAnswers([730: .claimedFree, 374320: .available], into: [:],
                                              claimedFree: &claimed)
        #expect(first["730"] == .notOwned)
        #expect(first["374320"] == .owned)
        #expect(claimed == ["730"])

        // The next check finds the licence the first one obtained. It still isn't the player's.
        let second = StoreLibrary.steamAnswers([730: .available], into: first, claimedFree: &claimed)
        #expect(second["730"] == .notOwned)
    }

    @Test("The library follows Steam's own list: a free licence nobody played is not in it (#288)")
    func libraryFollowsSteamsList() {
        // What GetOwnedGames returns with include_free_sub=false: paid games and played free ones.
        let response: [String: Any] = ["response": ["game_count": 2,
                                                    "games": [["appid": 374320], ["appid": 271590]]]]
        let library = SteamOwnedGames.appIDs(inResponse: response)
        #expect(library == [374320, 271590])

        // Overwatch 2 holds a free licence an older check claimed, but was never played: not listed.
        let answers = SteamOwnedGames.answers(for: [374320, 271590, 2357570], library: library ?? [])
        #expect(answers["374320"] == .owned)
        #expect(answers["271590"] == .owned)
        #expect(answers["2357570"] == .notOwned)

        // The request leaves unused free licences out and played free games in.
        let form = SteamOwnedGames.ownedForm(access: "a", steamID: "76561197960287930")
        #expect(form["include_free_sub"] == "false")
        #expect(form["include_played_free_games"] == "true")
    }

    @Test("An answer Steam wouldn't give is 'couldn't ask', never 'owns nothing'")
    func refusedListIsNotEmptyLibrary() {
        #expect(SteamOwnedGames.appIDs(inResponse: ["response": [String: Any]()]) == nil)
        #expect(SteamOwnedGames.appIDs(inResponse: [:]) == nil)
        #expect(SteamOwnedGames.appIDs(inResponse: ["response": ["game_count": 0]]) == [])
        #expect(SteamOwnedGames.accessToken(["response": ["access_token": "tok"]]) == "tok")
        #expect(SteamOwnedGames.accessToken(["response": ["access_token": ""]]) == nil)
        #expect(SteamOwnedGames.tokenForm(refresh: "r", steamID: "s") == ["refresh_token": "r", "steamid": "s"])
    }

    @Test("Concurrent logon ids stay clear of DepotDownloader's default")
    func loginIDsAvoidDefault() {
        let defaultID: UInt32 = 0x534B32 // "SK2", used by a download started without -loginid
        for slot in 0..<StoreLibrary.steamCheckWidth {
            #expect(StoreLibrary.steamLoginIDBase + UInt32(slot) != defaultID)
        }
    }

    private final class Probe: @unchecked Sendable {
        private let lock = NSLock()
        private var running: Set<Int> = []
        private(set) var peak = 0
        private(set) var sharedSlot = false

        func enter(_ slot: Int) {
            lock.withLock {
                if running.contains(slot) { sharedSlot = true }
                running.insert(slot)
                peak = max(peak, running.count)
            }
        }

        func leave(_ slot: Int) { lock.withLock { _ = running.remove(slot) } }
    }
}
