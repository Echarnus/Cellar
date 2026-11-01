import Foundation
import Testing
@testable import CellarData

/// Skyrim's copy never reached the bottle's Steam library (2026-11-01). `SteamLibraryEntry.register`
/// rightly skips while any Steam is running, because a running client doesn't reread its library.
/// Play called it once, at the top, while the Steam Planet Coaster 2 had left open was still up,
/// and that Steam was only closed afterwards. So Skyrim started beside a client that had no record
/// of it, unlike Fallout Shelter a minute later.
///
/// The fix is where the call sits, so that is what is checked: on the route that starts the game
/// beside Steam, the library entry is made again after the sign-in hand-over and before the client
/// is started. The behaviour of `register` itself is `SteamLibraryEntryTests`.
struct SteamLibraryEntryOrderTests {

    @Test("Play enters the game in Steam's library again once the way is clear, before Steam starts")
    func registersAfterTheHandOverAndBeforeTheClient() throws {
        let source = try String(contentsOf: Repo.source("CellarInfrastructure/Adapters/SteamAdapter.swift"),
                                encoding: .utf8)
        let route = try #require(source.range(of: "func launchThroughClient"), "the launch route moved")
        let body = source[route.lowerBound...]
        let handOver = try #require(body.range(of: "SteamBottle.handOverSession("))
        let alongside = try #require(body.range(of: "SteamBottle.launchAlongside("))
        let registered = body[handOver.upperBound..<alongside.lowerBound]
        #expect(registered.contains("SteamLibraryEntry.register(plan)"),
                "a copy skipped while another game's Steam was open would stay unknown to the client")
    }

    @Test("The entry the second call writes is the same one: a second register changes nothing")
    func registerIsSafeToRepeat() throws {
        // `register` returns `.unchanged` for an entry already on disk; that is what makes calling
        // it twice per Play free. Pinned here because the order test above depends on it.
        let suite = SteamLibraryEntryTests()
        let plan = try suite.downloadedGame()
        #expect(SteamLibraryEntry.register(plan, clientRunning: true) != .registered,
                "skipped while a Steam is running, as on Kenneth's Mac")
        #expect(SteamLibraryEntry.register(plan, clientRunning: false) == .registered)
        #expect(SteamLibraryEntry.register(plan, clientRunning: false) == .unchanged)
    }
}
