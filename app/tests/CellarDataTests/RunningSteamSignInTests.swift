import CellarDomain
import Foundation
import Testing
@testable import CellarData

/// A Steam that is already running is only used once it has signed in (#334).
///
/// 2026-11-05: Assetto Corsa never appeared. The bottle's Steam had started at 20:33, its window
/// process hung before it tried to log on, and the launch that started it was cancelled. The next
/// Play saw Steam running and started the game beside it straight away — beside a client still at
/// `[U:1:0]` — and eight attempts went nowhere. The shared connection log did hold a logon `OK`,
/// but it was Skyrim's, from the Steam before.
struct RunningSteamSignInTests {

    /// The shape of the shared `connection_log.txt` that evening: Skyrim's Steam signs in and ends,
    /// then the Steam started for Assetto Corsa never gets past `[U:1:0]`.
    static let skyrimThenStuck = """
        [2026-11-05 20:29:39] [Logged Off, 0, 0] [U:1:0] CCMInterface::SetSteamID( [U:1:0] )
        [2026-11-05 20:29:40] Connectivity test: result=Connected, ...
        [2026-11-05 20:29:43] [Logged Off, 0, 0] [U:1:1] CCMInterface::SetSteamID( [U:1:1] )
        [2026-11-05 20:30:03] [Logged Off, 4, 0] [U:1:1] LogOn() called; not connected yet, scheduling connection
        [2026-11-05 20:30:04] [Logging On, 4, 7] [U:1:1] Logging on [U:1:1]
        [2026-11-05 20:30:04] [Logging On, 4, 7] [U:1:1] RecvMsgClientLogOnResponse() : [U:1:1] 'OK'
        [2026-11-05 20:30:04] [Logged On, 4, 7] [U:1:1] RecvMsgClientLogOnResponse() : processing complete
        [2026-11-05 20:31:58] [Logged On, 4, 7] [U:1:1] LogOff()
        [2026-11-05 20:31:59] [Logged Off, 0, 0] [U:1:1] Log session ended
        [2026-11-05 20:33:13] [Logged Off, 0, 0] [U:1:0] CCMInterface::SetSteamID( [U:1:0] )
        [2026-11-05 20:33:14] Connectivity test: result=Connected, ...

        """

    @Test("A logon from an earlier Steam does not count for the one running now")
    func earlierClientsLogonIsNotThisOnes() {
        // The whole file says OK — which is exactly the trap.
        #expect(SteamClientSession.logonResult(inConnectionLog: Self.skyrimThenStuck) == .loggedOn)
        #expect(SteamClientSession.runningClientLogon(inConnectionLog: Self.skyrimThenStuck) == nil)
        #expect(SteamBottle.reusedClientAction(
            SteamClientSession.runningClientLogon(inConnectionLog: Self.skyrimThenStuck)) == .waitForLogon)
    }

    @Test("A running Steam that has signed in is used as it is")
    func signedInClientIsUsed() {
        let signedIn = Self.skyrimThenStuck + """
            [2026-11-05 20:33:40] [Logging On, 4, 7] [U:1:1] RecvMsgClientLogOnResponse() : [U:1:1] 'OK'

            """
        #expect(SteamClientSession.runningClientLogon(inConnectionLog: signedIn) == .loggedOn)
        #expect(SteamBottle.reusedClientAction(.loggedOn) == .useIt)
    }

    @Test("A running Steam that was refused goes to the refusal path, not to the game")
    func refusedClientIsNotUsed() {
        let refused = Self.skyrimThenStuck + """
            [2026-11-05 20:33:40] [Logging On, 4, 7] [U:1:1] RecvMsgClientLogOnResponse() : [U:1:1] 'AccessDenied'

            """
        #expect(SteamClientSession.runningClientLogon(inConnectionLog: refused) == .refused("AccessDenied"))
        #expect(SteamBottle.reusedClientAction(.refused("AccessDenied")) == .waitForLogon)
    }

    @Test("The running Steam's stretch starts just after the last 'Log session ended' line")
    func sessionOffset() {
        let text = Self.skyrimThenStuck
        let offset = Int(SteamClientSession.currentSessionOffset(inConnectionLog: text))
        let rest = String(decoding: Array(text.utf8)[offset...], as: UTF8.self)
        #expect(rest.hasPrefix("[2026-11-05 20:33:13]"))
        // A log with no finished session at all is all one session.
        #expect(SteamClientSession.currentSessionOffset(inConnectionLog: "[x] SetSteamID( [U:1:0] )\n") == 0)
    }

    @Test("The bottle's own connection log is what is read")
    func readsTheBottlesLog() throws {
        let prefix = FileManager.default.temporaryDirectory
            .appendingPathComponent("cellar-running-steam-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: prefix) }
        let logs = SteamBottle.logsDirectory(in: prefix)
        try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        try Self.skyrimThenStuck.write(to: logs.appendingPathComponent("connection_log.txt"),
                                       atomically: true, encoding: .utf8)

        let session = SteamBottle.runningSession(in: prefix)
        #expect(session.logon == nil)
        // The wait reads from there, so a logon the stuck client writes later is the one it sees,
        // and Skyrim's never is.
        #expect(SteamBottle.logonResult(in: prefix, since: session.offset) == nil)
        #expect(SteamBottle.logonResult(in: prefix, since: 0) == .loggedOn)
    }

    @Test("No connection log at all is a client that hasn't signed in")
    func noLogIsNotSignedIn() {
        let prefix = FileManager.default.temporaryDirectory
            .appendingPathComponent("cellar-no-steam-log-\(UUID().uuidString)")
        let session = SteamBottle.runningSession(in: prefix)
        #expect(session.offset == 0)
        #expect(session.logon == nil)
    }

    @Test("The restart message says seconds for a short wait and minutes for a long one")
    func waitWording() {
        #expect(SteamBottle.waitWords(SteamBottle.reusedClientLogonTimeout) == "90 seconds")
        #expect(SteamBottle.waitWords(180) == "3 minutes")
    }
}

/// What a launch that goes nowhere leaves behind to read (#334: two empty logs and no reason).
struct LaunchLoggingTests {

    @Test("A game Cellar starts gets Wine's loader and crash errors, and keeps the profile's own channels")
    func startupWineDebug() {
        #expect(SteamBottle.startupWineDebug(nil) == "-all,err+module,err+seh")
        #expect(SteamBottle.startupWineDebug("-all") == "-all,err+module,err+seh")
        #expect(SteamBottle.startupWineDebug("+relay") == "+relay,err+module,err+seh")
        // Applied twice (a retry rebuilds the environment) it is still the same value.
        let once = SteamBottle.startupWineDebug("-all")
        #expect(SteamBottle.startupWineDebug(once) == once)
    }

    @Test("A failed attempt's Wine output is summed up in its last lines, or as nothing at all")
    func attemptLogSummary() throws {
        let log = FileManager.default.temporaryDirectory
            .appendingPathComponent("cellar-attempt-\(UUID().uuidString).log")
        defer { try? FileManager.default.removeItem(at: log) }

        #expect(ProcessWatch.attemptLogSummary(log) == "Wine wrote nothing.")
        try Data().write(to: log)
        #expect(ProcessWatch.attemptLogSummary(log) == "Wine wrote nothing.")

        let lines = (1...30).map { "err:module:import_dll line \($0)" }
        try lines.joined(separator: "\n").write(to: log, atomically: true, encoding: .utf8)
        let summary = ProcessWatch.attemptLogSummary(log, lines: 3)
        #expect(summary.hasPrefix("Wine's last lines:"))
        #expect(summary.contains("line 30"))
        #expect(summary.contains("line 28"))
        #expect(!summary.contains("line 27"))
    }

    @Test("Every failed attempt is supervised with its log, so the reason reaches Cellar's log")
    func superviseStartAcceptsTheLog() throws {
        let log = FileManager.default.temporaryDirectory
            .appendingPathComponent("cellar-supervise-\(UUID().uuidString).log")
        defer { try? FileManager.default.removeItem(at: log) }
        try "err:module:import_dll Library steam_api64.dll not found".write(to: log, atomically: true, encoding: .utf8)
        var starts = 0
        #expect(throws: CellarError.self) {
            try ProcessWatch.superviseStart(attempts: 2, appearSeconds: 1, settleSeconds: 1, backoffSeconds: 0,
                                            cleanup: {}, start: { starts += 1 }, isUp: { false },
                                            attemptLog: log)
        }
        #expect(starts == 2)
    }
}

/// DepotDownloader names each depot the account has no licence for in the same words it uses for
/// an app it doesn't own; only the app line is about the game (#334).
struct DepotLicenceWordingTests {

    @Test("A DLC depot without a licence is not 'this account doesn't own it'")
    func dlcDepotIsNotTheGame() {
        var listing = DepotManifests.Listing()
        listing.read("Depot 244211 (Assetto Corsa - Dream Pack 1) is not available from this account.")
        #expect(listing.failure == nil)
        #expect(!DepotTool.appIsUnavailable("Depot 244211 (Assetto Corsa - Dream Pack 1) is not available from this account."))
        #expect(DepotTool.probeVerdict(in: "Depot 244211 (Assetto Corsa - Dream Pack 1) is not available from this account.") == nil)
    }

    @Test("The app itself not on the account still is")
    func appLineStillCounts() {
        var listing = DepotManifests.Listing()
        listing.read("App 244210 (Assetto Corsa) is not available from this account.")
        #expect(listing.failure == "Steam says this account doesn't own it")
        #expect(DepotTool.appIsUnavailable("  App 244210 (Assetto Corsa) is not available from this account."))
    }
}
