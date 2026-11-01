import CellarDomain
import Foundation
import Testing
@testable import CellarData

/// `cellar verify`'s baseline (#203): every check judged from real-shaped text, and one whole run
/// against the fake Wine.
///
/// Each judgement here is one Kenneth used to have to make himself: Steam asking him to sign in,
/// Steam in offline mode, a game whose Workshop never loaded while every probe passed, a crash
/// reporter. The tests pin what each one looks like and what verdict it gets.
struct VerificationVerdictTests {
    @Test("Any failure fails, any gap is a gap, and only all-passed passes; nothing checked is a gap")
    func overall() {
        #expect(VerificationVerdict.overall([.pass, .pass]) == .pass)
        #expect(VerificationVerdict.overall([.pass, .couldNotCheck]) == .couldNotCheck)
        #expect(VerificationVerdict.overall([.couldNotCheck, .fail, .pass]) == .fail)
        #expect(VerificationVerdict.overall([]) == .couldNotCheck)
    }

    @Test("The report leads with its verdict, tables every check, and shows evidence only for what didn't pass")
    func markdown() throws {
        let report = VerificationReport(
            slug: "x", name: "Example", store: "steam", startedAt: Date(timeIntervalSince1970: 0),
            finishedAt: Date(timeIntervalSince1970: 60), environment: ["Cellar": "0.4.0"],
            checks: [VerificationCheck(id: "signed-in", title: "Steam is signed in", verdict: .pass, detail: "ok", evidence: ["hidden"]),
                     VerificationCheck(id: "game-online", title: "Online | servers", verdict: .fail, detail: "no", evidence: ["err:secur32:x"])])
        let text = report.markdown
        #expect(text.contains("**FAIL**: 1 of 2 checks passed, 1 failed."))
        #expect(text.contains("| Online \\| servers | FAIL | no |"), "a pipe in a cell must not break the table")
        #expect(text.contains("err:secur32:x"))
        #expect(!text.contains("hidden"), "a passing check's evidence is not shown")

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        #expect(try decoder.decode(VerificationReport.self, from: encoder.encode(report)) == report)
        #expect(String(decoding: try encoder.encode(report), as: UTF8.self).contains("\"could-not-check\"") == false)
    }

    @Test("A check from one of several launches is numbered for it")
    func numbered() {
        let check = VerificationCheck(id: "stays-up", title: "t", verdict: .pass, detail: "d").inRun(2)
        #expect(check.id == "run-2.stays-up")
    }
}

struct CrashSignsTests {
    @Test("The Frontier crash reporter, Unity's and Unreal's, and Wine's debugger are crashes; Steam's web helper is not")
    func reporters() {
        let table = """
          101 C:\\Program Files (x86)\\Steam\\steamapps\\common\\Planet Coaster 2\\PlanetCoaster2.exe
          102 C:\\Program Files (x86)\\Steam\\steamapps\\common\\Planet Coaster 2\\crash_reporter.exe -parentpath C:\\x\\PlanetCoaster2.exe
          103 C:\\Games\\x\\UnityCrashHandler64.exe --attach 1
          104 C:\\Games\\y\\Engine\\Binaries\\Win64\\CrashReportClient.exe
          105 C:\\windows\\system32\\winedbg.exe --auto 32 48
          106 C:\\Program Files (x86)\\Steam\\bin\\cef\\cef.win7x64\\steamwebhelper.exe --type=crashpad-handler crashpad_handler.exe
          107 /usr/bin/some-mac-thing --crash
        """
        let found = CrashSigns.crashReporters(inProcessList: table)
        #expect(found.count == 4)
        #expect(found.allSatisfy { !$0.contains("steamwebhelper") && !$0.contains(" 101 ") && !$0.contains("107") })
        #expect(CrashSigns.crashReporters(inProcessList: "  9 C:\\g\\MyCrashy.exe", extra: ["MyCrashy.exe"]).count == 1,
                "a profile's own crash_processes are crashes too")
    }

    @Test("Wine's crash lines and Planet Coaster 2's 0xFDEAD are crashes; ordinary log lines are not")
    func crashLines() {
        let log = """
        0124:err:seh:NtRaiseException Unhandled exception code c0000005 flags 0 addr 0x1234
        wine: Unhandled page fault on read access to 0000000000000010 at address 00006FFFFF4A1234
        0130:err:module:x raised 0x0FDEAD
        0040:fixme:ntdll:NtQuerySystemInformation info_class SYSTEM_PERFORMANCE_INFORMATION
        """
        #expect(CrashSigns.crashLines(inWineLog: log).count == 3)
    }

    @Test("Schannel and certificate errors are TLS failures, a fixme is not")
    func tlsErrors() {
        let log = """
        0128:err:secur32:schan_InitializeSecurityContextW Returned SEC_E_INTERNAL_ERROR
        0128:err:crypt:CertVerifyRevocation no revocation provider
        0128:fixme:secur32:schan_QueryContextAttributesW unhandled attribute
        """
        #expect(CrashSigns.tlsErrors(inWineLog: log).count == 2)
    }

    @Test("Verify turns the TLS and crash channels on, keeping any channels the game already had")
    func wineDebug() {
        #expect(CrashSigns.wineDebug(adding: "-all").hasPrefix("-all,err+seh,err+secur32"))
        #expect(CrashSigns.wineDebug(adding: nil).hasPrefix("-all,"))
        #expect(CrashSigns.wineDebug(adding: "+seh").hasPrefix("+seh,err+seh"))
    }
}

struct GameConnectionsTests {
    @Test("lsof's established connections become far ends, IPv4 and IPv6, and nothing else does")
    func lsof() {
        let text = """
        COMMAND   PID USER   FD   TYPE DEVICE SIZE/OFF NODE NAME
        wine64-pr 812 ken   45u  IPv4 0xabc      0t0  TCP 192.168.1.20:50211->52.16.98.4:443 (ESTABLISHED)
        wine64-pr 812 ken   46u  IPv6 0xdef      0t0  TCP [2a02:1810::5]:50212->[2600:9000:2:1::7]:443 (ESTABLISHED)
        wine64-pr 812 ken   47u  IPv4 0x123      0t0  TCP 127.0.0.1:50213->127.0.0.1:27060 (ESTABLISHED)
        wine64-pr 812 ken   48u  IPv4 0x124      0t0  TCP *:27036 (LISTEN)
        """
        let found = GameConnections.remoteEndpoints(inLsof: text)
        #expect(found == [.init(address: "52.16.98.4", port: 443), .init(address: "2600:9000:2:1::7", port: 443),
                          .init(address: "127.0.0.1", port: 27060)])
        #expect(found.filter { GameConnections.isPublic($0.address) }.count == 2,
                "a game talking to Steam over loopback has not reached the internet")
    }

    @Test("Loopback, private, link-local and carrier NAT addresses are not the internet")
    func publicAddresses() {
        for local in ["127.0.0.1", "10.0.0.4", "172.20.1.1", "192.168.0.2", "169.254.3.3", "100.64.0.1", "::1", "fe80::1", "fd00::2"] {
            #expect(!GameConnections.isPublic(local), "\(local)")
        }
        for internet in ["52.16.98.4", "172.32.0.1", "8.8.8.8", "2600:9000::1"] {
            #expect(GameConnections.isPublic(internet), "\(internet)")
        }
    }

    @Test("dscacheutil's answer is read for both address families, and a URL names its host")
    func resolving() {
        let text = "name: css-api.zaonce.net\nip_address: 52.16.98.4\nip_address: 52.16.98.5\n\nname: css-api.zaonce.net\nipv6_address: 2600:9000::1\n"
        #expect(GameConnections.addresses(inDscacheutil: text) == ["52.16.98.4", "52.16.98.5", "2600:9000::1"])
        #expect(GameConnections.hostName("https://css-api.zaonce.net/v1") == "css-api.zaonce.net")
        #expect(GameConnections.hostName("CSS-API.zaonce.net") == "css-api.zaonce.net")
    }
}

struct SteamSessionCheckTests {
    static let ok = "[2026-11-01 20:00:01] [0,0] RecvMsgClientLogOnResponse() : [U:1:1] 'OK'\n"
    static let refused = "[2026-11-01 20:00:01] [0,0] RecvMsgClientLogOnResponse() : [U:1:1] 'AccessDenied'\n"

    func check(_ id: String, log: String, loginUsers: String? = nil, bottle: String? = "kenneth",
               player: String? = "kenneth", steps: [String] = []) -> VerificationCheck? {
        SteamSessionCheck.checks(connectionLog: log, loginUsers: loginUsers, bottleAccount: bottle,
                                 playerAccount: player, launchSteps: steps).first { $0.id == id }
    }

    @Test("A logon Steam accepted by itself, as the player's account, passes both")
    func signedInAndOnline() {
        #expect(check("signed-in", log: Self.ok)?.verdict == .pass)
        #expect(check("steam-online", log: Self.ok)?.verdict == .pass)
    }

    @Test("Steam's own sign-in window having opened fails, even if Steam signed in afterwards (the Skyrim prompt)")
    func promptFails() {
        let steps = ["Steam didn't accept the sign-in Cellar gave it (Expired), so its own window opens instead."]
        #expect(check("signed-in", log: Self.ok, steps: steps)?.verdict == .fail)
    }

    @Test("A refused logon, no logon at all, or another account fail the sign-in")
    func signInFailures() {
        #expect(check("signed-in", log: Self.refused)?.verdict == .fail)
        #expect(check("signed-in", log: "")?.verdict == .fail)
        #expect(check("signed-in", log: Self.ok, bottle: "someone-else")?.verdict == .fail)
    }

    @Test("Offline mode fails online even with a logon (Fallout Shelter), and so does a drop after the logon")
    func offline() {
        let vdf = "\"users\"\n{\n\t\"7656\"\n\t{\n\t\t\"AccountName\"\t\t\"kenneth\"\n\t\t\"WantsOfflineMode\"\t\t\"1\"\n\t}\n}\n"
        #expect(check("steam-online", log: Self.ok, loginUsers: vdf)?.verdict == .fail)
        let dropped = Self.ok + "[2026-11-01 20:05:00] [0,0] ConnectionDisconnected() : remote host closed\n"
        #expect(check("steam-online", log: dropped)?.verdict == .fail)
        #expect(check("steam-online", log: Self.refused)?.verdict == .fail)
    }
}

struct VerifyJudgementTests {
    @Test("The game's pids are its own: never a crash reporter or a Wine helper that only mentions its path")
    func gamePids() {
        let table = """
          101 C:\\Games\\PC2\\PlanetCoaster2.exe -nolauncher
          102 C:\\Games\\PC2\\crash_reporter.exe -parentpath C:\\Games\\PC2\\PlanetCoaster2.exe
          103 C:\\windows\\system32\\winedbg.exe C:\\Games\\PC2\\PlanetCoaster2.exe
          104 C:\\Program Files (x86)\\Steam\\steam.exe
        """
        #expect(VerifyGame.gamePids(inProcessList: table, needles: ["PlanetCoaster2.exe"]) == [101])
        #expect(VerifyGame.gamePids(inProcessList: table, needles: []).isEmpty)
    }

    func plan(online: String? = nil, hosts: [String] = []) throws -> GamePlan {
        var plan = try TestHome.plan("""
        [game]
        name = "Judged"
        [compatibility]
        status = "untested"
        \(online.map { "online = \"\($0)\"" } ?? "")
        """, slug: "judged")
        plan.onlineHosts = hosts
        return plan
    }

    @Test("A game that connected to its named server passes; one that never did fails and says which (the PC2 Workshop)")
    func namedServers() throws {
        var watch = VerifyGame.Watch()
        watch.endpoints = [.init(address: "52.16.98.4", port: 443)]
        watch.hostAddresses = ["css-api.zaonce.net": ["52.16.98.4"]]
        let named = try plan(hosts: ["css-api.zaonce.net"])
        #expect(VerifyGame.judgeOnline(watch, wineLog: "", plan: named).verdict == .pass)

        watch.hostAddresses = ["css-api.zaonce.net": ["52.16.98.9"]]
        let missed = VerifyGame.judgeOnline(watch, wineLog: "", plan: named)
        #expect(missed.verdict == .fail)
        #expect(missed.detail.contains("css-api.zaonce.net"))
    }

    @Test("TLS errors fail online even when the game connected; no connection at all fails; an offline game is not held to it")
    func onlineVerdicts() throws {
        var watch = VerifyGame.Watch()
        watch.endpoints = [.init(address: "52.16.98.4", port: 443)]
        let tls = "0128:err:secur32:schan_InitializeSecurityContextW Returned SEC_E_INTERNAL_ERROR"
        #expect(VerifyGame.judgeOnline(watch, wineLog: tls, plan: try plan()).verdict == .fail)
        #expect(VerifyGame.judgeOnline(watch, wineLog: "", plan: try plan()).verdict == .pass)
        #expect(VerifyGame.judgeOnline(VerifyGame.Watch(), wineLog: "", plan: try plan()).verdict == .fail)
        #expect(VerifyGame.judgeOnline(VerifyGame.Watch(), wineLog: "", plan: try plan(online: "none")).verdict == .pass)
        #expect(VerifyGame.judgeOnline(VerifyGame.Watch(), wineLog: tls, plan: try plan(online: "none")).verdict == .fail)
    }

    @Test("Staying up fails on a crash reporter, an early exit, a game that never appeared, or a crash in the log")
    func staysUp() {
        var watch = VerifyGame.Watch()
        watch.gameSeenRunning = true
        watch.watchedSeconds = 300
        #expect(VerifyGame.judgeStaysUp(watch, wineLog: "", surviveSeconds: 300, name: "G").verdict == .pass)
        #expect(VerifyGame.judgeStaysUp(watch, wineLog: "wine: Unhandled page fault on read", surviveSeconds: 300, name: "G").verdict == .fail)

        var early = watch
        early.exitedAfter = 40
        #expect(VerifyGame.judgeStaysUp(early, wineLog: "", surviveSeconds: 300, name: "G").detail.contains("40 s"))

        var reporter = watch
        reporter.crashReporters = ["102 crash_reporter.exe"]
        #expect(VerifyGame.judgeStaysUp(reporter, wineLog: "", surviveSeconds: 300, name: "G").verdict == .fail)
        #expect(VerifyGame.judgeStaysUp(VerifyGame.Watch(), wineLog: "", surviveSeconds: 300, name: "G").verdict == .fail)
    }

    @Test("A changed runtime fails the untouched check and names the file; leftover Wine fails a clean exit")
    func runtimeAndExit() {
        let before = CellarSandbox.Fingerprint(files: ["wf/wine/bin/wine": "a"])
        #expect(VerifyGame.judgeRuntime(before: before, after: before).verdict == .pass)
        let changed = VerifyGame.judgeRuntime(before: before, after: .init(files: ["wf/wine/bin/wine": "b"]))
        #expect(changed.verdict == .fail && changed.evidence == ["wf/wine/bin/wine was changed"])

        #expect(VerifyGame.judgeCleanExit(left: [], swept: [12]).verdict == .pass)
        #expect(VerifyGame.judgeCleanExit(left: [.init(pid: 9, path: "/r/wine/bin/wineserver")], swept: []).verdict == .fail)
    }

    @Test("Profiles that call themselves offline are recognised; an online description is not")
    func offlineProfiles() {
        #expect(VerifyGame.isOffline("none"))
        #expect(VerifyGame.isOffline("Offline only"))
        #expect(!VerifyGame.isOffline("single-player core + online co-op"))
        #expect(!VerifyGame.isOffline(nil))
    }
}

/// One whole `cellar verify` against the fake Wine: launch, watch, close, report.
@Suite(.serialized)
struct VerifyRunTests {
    private func game(lifetime: Int) throws -> (plan: GamePlan, exeName: String) {
        let install = try FakeWine.install()
        let exeName = "VerifyFixture-\(UUID().uuidString.prefix(8)).exe"
        let plan = try TestHome.plan("""
        [game]
        name  = "Verify Fixture"
        store = "steam"

        [compatibility]
        needs_live_session = false
        online             = "none"
        status             = "untested"

        [runner]
        id = "\(install.spec.id)"

        [install]
        steam_appid = "480"

        [launch]
        exe = "\(exeName)"
        """, slug: "verify")
        try TestHome.installFakeGame(into: plan, at: exeName)
        try FakeWine.keepAlive(try #require(plan.directLaunchExe), seconds: lifetime)
        return (plan, exeName)
    }

    /// No update check (that would ask Steam over the network) and no screenshot (no screen in CI).
    private func verify(_ plan: GamePlan, surviveSeconds: Int) -> VerifyGame {
        var verify = VerifyGame(plan, surviveSeconds: surviveSeconds, sampleSeconds: 1,
                                reportsRoot: TestHome.scratch("reports"))
        verify.checkUpdates = false
        verify.screenshots = false
        verify.dockApps = { [] }
        return verify
    }

    @Test("A game that stays up passes stays-up, is closed afterwards, and the report is written with every baseline check")
    func passingRun() throws {
        let (plan, exeName) = try game(lifetime: 30)
        defer {
            ProcessWatch.kill([exeName])
            try? FileManager.default.removeItem(at: plan.prefix)
        }
        FakeWine.reset()
        let (report, folder) = verify(plan, surviveSeconds: 3).run()
        func verdict(_ id: String) -> VerificationVerdict? { report.checks.first { $0.id == id }?.verdict }

        #expect(verdict("launch") == .pass)
        #expect(verdict("stays-up") == .pass)
        #expect(verdict("game-online") == .pass, "the fixture says it has no online features")
        #expect(verdict("clean-exit") == .pass)
        #expect(verdict("real-install-untouched") == .pass)
        #expect(verdict("dock") == .couldNotCheck, "this test has no Dock to read")
        #expect(verdict("settings-match") == .pass)
        #expect(verdict("dlc") == .couldNotCheck, "the fixture's bottle has no Steam client")
        #expect(verdict("signed-in") == .fail, "nobody signed this sandbox's Steam in, and the report must say so")
        #expect(verdict("steam-online") == .fail)
        #expect(report.verdict == .fail)
        #expect(!ProcessWatch.isRunning(exeName), "verify closes the game when it is done")

        #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent("report.json").path))
        let markdown = try String(contentsOf: folder.appendingPathComponent("report.md"), encoding: .utf8)
        #expect(markdown.contains("## Verification report: Verify Fixture"))

        let call = try #require(FakeWine.calls().last { $0.tool == "wine" && ($0.arguments.first ?? "").hasSuffix(exeName) })
        #expect(call.environment["WINEDEBUG"]?.contains("err+secur32") == true,
                "verify turns on the TLS channels it reads")
    }

    @Test("Stopped mid-watch, verify closes the game, writes the report it has, and passes nothing it didn't see")
    func interruptedRun() throws {
        let (plan, exeName) = try game(lifetime: 60)
        defer {
            ProcessWatch.kill([exeName])
            try? FileManager.default.removeItem(at: plan.prefix)
        }
        var verify = verify(plan, surviveSeconds: 40)
        verify.runs = 2
        let start = Date()
        verify.isInterrupted = { Date().timeIntervalSince(start) > 4 }
        let (report, folder) = verify.run()
        func verdict(_ id: String) -> VerificationVerdict? { report.checks.first { $0.id == id }?.verdict }

        #expect(verdict("run-1.launch") == .pass)
        #expect(verdict("run-1.stays-up") == .couldNotCheck, "up for 4 s is not up for 40 s")
        #expect(verdict("run-1.clean-exit") == .pass, "the run under way is still closed down")
        #expect(verdict("interrupted") == .couldNotCheck)
        #expect(!report.checks.contains { $0.id.hasPrefix("run-2.") }, "run 2 never started")
        #expect(!ProcessWatch.isRunning(exeName))
        #expect(Date().timeIntervalSince(start) < 30, "a stop is answered within seconds, not at the end of the watch")
        let markdown = try String(contentsOf: folder.appendingPathComponent("report.md"), encoding: .utf8)
        #expect(markdown.contains("stopped during run 1"))
    }

    @Test("A game that quits early fails stays-up, saying after how long")
    func earlyExit() throws {
        let (plan, exeName) = try game(lifetime: 6)
        defer {
            ProcessWatch.kill([exeName])
            try? FileManager.default.removeItem(at: plan.prefix)
        }
        let (report, _) = verify(plan, surviveSeconds: 20).run()
        let staysUp = try #require(report.checks.first { $0.id == "stays-up" })
        #expect(staysUp.verdict == .fail)
        #expect(staysUp.detail.contains("stopped after"))
    }
}

/// `dlc`, `dock` and `settings-match` (#208): the three baseline checks that judge what the player
/// would see after a launch rather than whether it started.
struct BaselineCheckTests {
    // MARK: - dlc

    static func manifest(stateFlags: String = "4", depots: [UInt32]) -> String {
        """
        "AppState"
        {
        \t"appid"\t\t"2688950"
        \t"StateFlags"\t\t"\(stateFlags)"
        \t"InstalledDepots"
        \t{
        \(depots.map { "\t\t\"\($0)\"\n\t\t{\n\t\t\t\"manifest\"\t\t\"123\"\n\t\t}" }.joined(separator: "\n"))
        \t}
        }
        """
    }

    @Test("No appmanifest, or one that isn't fully installed, fails: every DLC would read as missing")
    func dlcNeedsAFullyInstalledRecord() {
        #expect(SteamDLCCheck.check(manifest: nil, downloadedDepots: [2688951: 1]).verdict == .fail)
        let partial = SteamDLCCheck.check(manifest: Self.manifest(stateFlags: "1026", depots: [2688951]), downloadedDepots: nil)
        #expect(partial.verdict == .fail)
        #expect(partial.detail.contains("1026"))
    }

    @Test("A depot Cellar downloaded but Steam doesn't list fails, naming the depot; redistributables don't count")
    func dlcDepotsMustAllBeListed() {
        let downloaded: [UInt32: UInt64] = [2688951: 1, 2688952: 2, 228989: 3]
        let missing = SteamDLCCheck.check(manifest: Self.manifest(depots: [2688951]), downloadedDepots: downloaded)
        #expect(missing.verdict == .fail)
        #expect(missing.evidence == ["depot 2688952 downloaded, not in appmanifest"])
        let complete = SteamDLCCheck.check(manifest: Self.manifest(depots: [2688951, 2688952]), downloadedDepots: downloaded)
        #expect(complete.verdict == .pass)
        #expect(SteamDLCCheck.check(manifest: Self.manifest(depots: [2688951]), downloadedDepots: nil).verdict == .pass,
                "a copy Steam installed itself is Steam's to manage")
    }

    @Test("A Steam game whose bottle has no Steam client can't be judged on DLC, and says why")
    func dlcWithoutAClient() throws {
        let plan = try TestHome.plan("""
        [game]
        name  = "No Client"
        store = "steam"

        [install]
        steam_appid = "480"
        """, slug: "dlc-no-client")
        let check = SteamDLCCheck.check(plan)
        #expect(check.verdict == .couldNotCheck)
        #expect(check.detail.contains("no Steam client"))
    }

    // MARK: - dock

    static let gameBundle = "/Users/player/Applications/Cellar Games/Planet Coaster 2.app"
    static let runner = "/Users/player/Library/Application Support/Cellar/runners/wineforge"

    /// `lsappinfo list` as macOS prints it, cut down to the lines the check reads.
    static func lsappinfo(_ apps: [(name: String, bundle: String?, exe: String, type: String)]) -> String {
        apps.enumerated().map { index, app in
            """
             \(index + 1)) "\(app.name)" ASN:0x0-0x\(index)01a:
                bundleID=[ NULL ]
                bundle path=\(app.bundle.map { "\"\($0)\"" } ?? "[ NULL ]")
                executable path="\(app.exe)"
                pid = \(500 + index) type="\(app.type)" flavor=3 Version="1.0" fileType="APPL" creator="????" Arch=x86_64
            """
        }.joined(separator: "\n")
    }

    @Test("lsappinfo's list reads back as name, bundle, executable, pid and type; a NULL bundle is none")
    func parsesLsappinfo() {
        let apps = DockApps.apps(inLsappinfo: Self.lsappinfo([
            ("Finder", "/System/Library/CoreServices/Finder.app", "/System/Library/CoreServices/Finder.app/Contents/MacOS/Finder", "Foreground"),
            ("wineserver", nil, Self.runner + "/wine/bin/wineserver", "BackgroundOnly"),
        ]))
        #expect(apps.count == 2)
        #expect(apps[0] == DockApps.App(name: "Finder", bundlePath: "/System/Library/CoreServices/Finder.app",
                                        executablePath: "/System/Library/CoreServices/Finder.app/Contents/MacOS/Finder",
                                        pid: 500, type: "Foreground"))
        #expect(apps[1].bundlePath == nil)
        #expect(!apps[1].isInDock)
    }

    @Test("Wine, Steam, or anything else started from the runner in the Dock is an intruder; the game's own app is not")
    func dockIntruders() {
        let apps = DockApps.apps(inLsappinfo: Self.lsappinfo([
            ("Planet Coaster 2", Self.gameBundle, Self.gameBundle + "/Contents/MacOS/wine", "Foreground"),
            ("wine", nil, Self.runner + "/wine/bin/wine", "Foreground"),
            ("steamwebhelper.exe", nil, "/somewhere/else", "Foreground"),
            ("PlanetCoaster2_Launcher.exe", nil, Self.runner + "/wine/bin/wine", "Foreground"),
            ("Steam", nil, Self.runner + "/wine/bin/wine", "UIElement"),
            ("Safari", "/Applications/Safari.app", "/Applications/Safari.app/Contents/MacOS/Safari", "Foreground"),
            ("Steam", "/Applications/Steam.app", "/Applications/Steam.app/Contents/MacOS/steam_osx", "Foreground"),
        ]))
        let names = DockApps.intruders(in: apps, runnerRoot: Self.runner, gameBundle: Self.gameBundle).map(\.name)
        #expect(names == ["wine", "steamwebhelper.exe", "PlanetCoaster2_Launcher.exe"],
                "a hidden Steam (UIElement) and the player's own apps, Mac Steam included, are fine")
        #expect(DockApps.game(in: apps, gameBundle: Self.gameBundle, name: "Planet Coaster 2") != nil)
        #expect(DockApps.game(in: apps, gameBundle: Self.gameBundle, name: "planet-coaster-2") == nil,
                "the slug is not the game's name (#220)")
    }

    @Test("dock passes only with the game in it by name and no intruder, and can't judge an empty list")
    func judgesDock() {
        var watch = VerifyGame.Watch()
        watch.gameSeenRunning = true
        #expect(VerifyGame.judgeDock(watch, name: "G").verdict == .couldNotCheck)
        watch.dockSamples = 3
        #expect(VerifyGame.judgeDock(watch, name: "G").verdict == .fail, "the game never showed under its name")
        watch.gameInDock = true
        #expect(VerifyGame.judgeDock(watch, name: "G").verdict == .pass)
        watch.dockIntruders = ["wine (/runners/wineforge/wine/bin/wine)"]
        let intruded = VerifyGame.judgeDock(watch, name: "G")
        #expect(intruded.verdict == .fail)
        #expect(intruded.evidence == ["wine (/runners/wineforge/wine/bin/wine)"])
    }

    // MARK: - settings-match

    @Test("A switch the bottle overrides, or a language other than the Mac's, fails settings-match by name")
    func judgesSettings() {
        let profile = PerformanceSettings.Entry(setting: .metalValidation, value: "true", source: .profile)
        let bottle = PerformanceSettings.Entry(setting: .metalHUD, value: "true", source: .bottle)
        let mac = LanguageChoice(language: .english, source: .system)
        #expect(VerifyGame.judgeSettings([profile], language: mac, macLanguage: .english).verdict == .pass)

        let overridden = VerifyGame.judgeSettings([profile, bottle], language: mac, macLanguage: .english)
        #expect(overridden.verdict == .fail)
        #expect(overridden.evidence == ["metal_hud = true is set for this bottle, over the profile"])

        let dutch = VerifyGame.judgeSettings([profile], language: LanguageChoice(language: .dutch, source: .allGames),
                                             macLanguage: .english)
        #expect(dutch.verdict == .fail, "the Belgian-Terminal bug: Steam and the game in Dutch on an English Mac")
        #expect(dutch.evidence.first?.contains("every game") == true)
    }
}

/// A verify that is stopped part-way (#249): what it says about the runs it did and didn't finish.
struct InterruptedVerifyTests {
    @Test("The interrupted check is never a pass, and says how far verify got")
    func interruptedCheck() {
        let during = VerifyGame.judgeInterrupted(stoppedIn: 3, completed: 2, runs: 3)
        #expect(during.verdict == .couldNotCheck)
        #expect(during.detail.contains("during run 3") && during.detail.contains("2 of 3 runs finished"))
        #expect(VerifyGame.judgeInterrupted(stoppedIn: nil, completed: 1, runs: 3).detail.contains("before run 2 started"))
        #expect(VerifyGame.judgeInterrupted(stoppedIn: nil, completed: 1, runs: 3, stillRunning: true)
            .detail.contains("still running"))
    }

    @Test("A watch cut short is could-not-check for stays-up, unless a crash was already seen")
    func staysUpWhenStopped() {
        var watch = VerifyGame.Watch()
        watch.interrupted = true
        watch.watchedSeconds = 12
        #expect(VerifyGame.judgeStaysUp(watch, wineLog: "", surviveSeconds: 300, name: "G").verdict == .couldNotCheck,
                "stopped before the game appeared is not 'never appeared'")
        watch.gameSeenRunning = true
        let up = VerifyGame.judgeStaysUp(watch, wineLog: "", surviveSeconds: 300, name: "G")
        #expect(up.verdict == .couldNotCheck)
        #expect(up.detail.contains("12 s"))
        watch.crashReporters = ["4242 C:\\Game\\CrashReporter.exe"]
        #expect(VerifyGame.judgeStaysUp(watch, wineLog: "", surviveSeconds: 300, name: "G").verdict == .fail)
    }

    @Test("Not seen yet is could-not-check when stopped early; a failure on evidence stands")
    func cutShort() {
        let failed = VerificationCheck(id: "dock", title: "t", verdict: .fail, detail: "never in the Dock.")
        var watch = VerifyGame.Watch()
        #expect(VerifyGame.cutShort(failed, watch, failedOnEvidence: false).verdict == .fail, "a full watch keeps its verdict")
        watch.interrupted = true
        #expect(VerifyGame.cutShort(failed, watch, failedOnEvidence: false).verdict == .couldNotCheck)
        #expect(VerifyGame.cutShort(failed, watch, failedOnEvidence: true).verdict == .fail)
    }
}
