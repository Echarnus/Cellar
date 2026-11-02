import CellarDomain
import Foundation
import Testing
@testable import CellarData

/// A bottle's Steam that never signs in keeps the player's sign-in, and one bottle's Steam is never
/// taken for another's.
///
/// "Fallout Shelter has no connectivity and Steam appears to be offline", while signed in to Steam
/// in Cellar: the client started, wrote no logon line at all, and after the wait Cellar treated
/// that silence as a refused sign-in — it took the handed-over session back, which emptied the
/// shared `loginusers.vdf`, so every later Steam game opened Steam's sign-in window. The silent
/// client was left running, and because "is Steam running" matched any `steam.exe` on the Mac, the
/// next game, in another bottle, skipped the session hand-over.
@Suite(.serialized)
struct SteamClientSignInTests {

    // MARK: - Supervising the logon wait

    /// Everything the supervisor does, in order, so a test can assert the sequence and the counts.
    private final class Recorder {
        var events: [String] = []
        var answers: [SteamBottle.LogonWait]
        init(_ answers: [SteamBottle.LogonWait]) { self.answers = answers }

        func wait() -> SteamBottle.LogonWait {
            events.append("wait")
            return answers.isEmpty ? .noAnswer : answers.removeFirst()
        }

        func count(_ event: String) -> Int { events.filter { $0 == event }.count }

        func supervise(game: String = "Fallout Shelter") throws {
            try SteamBottle.superviseLogon(
                attempts: 2,
                wait: { self.wait() },
                restart: { self.events.append("restart") },
                stop: { self.events.append("stop") },
                refused: { self.events.append("refused:\($0)") },
                game: game)
        }
    }

    @Test("A client that answers after one restart starts the game, and nothing is stopped or taken back")
    func silentThenLoggedOnAfterRestart() throws {
        let recorder = Recorder([.noAnswer, .loggedOn])
        try recorder.supervise()
        #expect(recorder.events == ["wait", "restart", "wait"])
        #expect(recorder.count("restart") == 1)
        #expect(recorder.count("stop") == 0)
        #expect(!recorder.events.contains { $0.hasPrefix("refused") })
    }

    @Test("A client silent twice is restarted once, then stopped, and the sign-in is never taken back")
    func silentTwiceStopsAndKeepsSession() {
        let recorder = Recorder([.noAnswer, .noAnswer])
        #expect(throws: CellarError.self) { try recorder.supervise() }
        #expect(recorder.events == ["wait", "restart", "wait", "stop"],
                "restart once, wait again, then shut the stuck client down — never leave it running")
        #expect(recorder.count("restart") == 1)
        #expect(recorder.count("stop") == 1)
        #expect(!recorder.events.contains { $0.hasPrefix("refused") },
                "silence says nothing about the session, so the session-taking-back path must not run")
    }

    @Test("A client silent twice ends with an error that keeps the sign-in and does not ask for it again")
    func silentTwiceErrorWording() {
        let recorder = Recorder([.noAnswer, .noAnswer])
        do {
            try recorder.supervise(game: "Fallout Shelter")
            Issue.record("a client that never signed in must not let the launch go on")
        } catch {
            let message = "\(error)".lowercased()
            #expect(message.contains("never signed in"), "says what happened: \(message)")
            #expect(message.contains("sign-in is kept"), "tells the player their sign-in is safe: \(message)")
            #expect(!message.contains("sign in again"), "must not send the player to sign in again: \(message)")
            #expect(!message.contains("nobody signed in"), "must not blame the player's sign-in: \(message)")
        }
    }

    @Test("A refusal hands Steam's reason to the refusal path, with no restart and no stop")
    func refusedGoesToRefusalPath() throws {
        let recorder = Recorder([.refused("AccessDenied")])
        try recorder.supervise()
        #expect(recorder.events == ["wait", "refused:AccessDenied"])
        #expect(recorder.count("restart") == 0)
        #expect(recorder.count("stop") == 0)
    }

    @Test("A client signed in at once calls nothing else")
    func loggedOnAtOnce() throws {
        let recorder = Recorder([.loggedOn])
        try recorder.supervise()
        #expect(recorder.events == ["wait"])
    }

    // MARK: - Waiting for one logon

    @Test("The wait returns 'logged on' as soon as Steam says so, having slept only between polls")
    func awaitReturnsLoggedOn() {
        var answers: [SteamClientSession.LogonResult?] = [nil, nil, .loggedOn]
        var polls = 0
        var slept: [TimeInterval] = []
        let outcome = SteamBottle.awaitLogon(timeout: 180, poll: 2,
                                             result: { polls += 1; return answers.removeFirst() },
                                             sleep: { slept.append($0) })
        #expect(outcome == .loggedOn)
        #expect(polls == 3, "stops polling at the first answer")
        #expect(slept == [2, 2])
    }

    @Test("The wait returns Steam's refusal at once, without sleeping")
    func awaitReturnsRefusedAtOnce() {
        var slept: [TimeInterval] = []
        let outcome = SteamBottle.awaitLogon(timeout: 180, poll: 2,
                                             result: { .refused("Expired") },
                                             sleep: { slept.append($0) })
        #expect(outcome == .refused("Expired"))
        #expect(slept.isEmpty)
    }

    @Test("Silence until the timeout is 'no answer', reached in poll-sized sleeps")
    func awaitTimesOutAsNoAnswer() {
        var slept: [TimeInterval] = []
        let outcome = SteamBottle.awaitLogon(timeout: 180, poll: 2,
                                             result: { nil },
                                             sleep: { slept.append($0) })
        #expect(outcome == .noAnswer, "silence is not a refusal")
        #expect(slept.allSatisfy { $0 == 2 }, "every sleep is one poll step")
        #expect(slept.reduce(0, +) == 180, "it waits the whole timeout, and no longer")
        #expect(slept.count == 90)
    }

    // MARK: - Whose Steam is running

    private static let user = "/Users/x"
    private static let prefixes = "/Users/x/Library/Application Support/Cellar/prefixes"
    private static let coaster = "\(prefixes)/planet-coaster-2"
    private static let shelter = "\(prefixes)/fallout-shelter"
    private static let wineserverBin =
        "/Users/x/Library/Application Support/Cellar/runners/wineforge/wine/lib/wine/../../bin/wineserver"

    /// `steam.exe` started by Cellar by its macOS path inside the bottle. No environment on the line.
    private static func cellarStartedClient(_ prefix: String) -> String {
        "\(prefix)/drive_c/Program Files (x86)/Steam/steam.exe -language english -silent"
    }

    /// A Steam that restarted itself shows only its Windows path.
    private static let restartedClient = #"C:\Program Files (x86)\Steam\steam.exe"#

    private static let webHelper =
        #"C:\Program Files (x86)\Steam\bin\cef\cef.win7x64\steamwebhelper.exe -lang=en_US -cachedir=C:\users\steamuser\AppData\Local\Steam\htmlcache -steampath=C:\Program Files (x86)\Steam\steam.exe -launcher=0"#

    private static func wineserver(_ prefix: String) -> String {
        "\(wineserverBin) HOME=\(user) WINEPREFIX=\(prefix) WINEDEBUG=-all"
    }

    /// Lines every `ps` has, which are none of Steam's business.
    private static let noise = [
        "/sbin/launchd",
        "/Users/x/Library/Application Support/Steam/Steam.AppBundle/Steam/Contents/MacOS/steam_osx HOME=/Users/x",
        "/bin/zsh -l HOME=/Users/x SHELL=/bin/zsh",
        "grep -i steam.exe",
    ]

    private static func ps(_ lines: [String]) -> String {
        (noise + lines).map { "  " + $0 }.joined(separator: "\n") + "\n"
    }

    @Test("A client started in one bottle is running in that bottle only")
    func clientBelongsToItsBottle() {
        let clients = SteamBottle.RunningClients.parse(ps: Self.ps([
            Self.cellarStartedClient(Self.coaster),
            Self.wineserver(Self.coaster),
        ]))
        #expect(clients.isRunning(in: Self.coaster))
        #expect(!clients.isRunning(in: Self.shelter),
                "another bottle's Steam must not make Fallout Shelter skip its own session hand-over")
        #expect(clients.otherBottles(than: Self.shelter) == [Self.coaster])
        #expect(clients.otherBottles(than: Self.coaster).isEmpty)
    }

    @Test("A client started in one bottle is not running in another even when that bottle's wineserver is up")
    func cellarStartedClientIgnoresOtherServers() {
        let clients = SteamBottle.RunningClients.parse(ps: Self.ps([
            Self.cellarStartedClient(Self.coaster),
            Self.wineserver(Self.coaster),
            Self.wineserver(Self.shelter),
        ]))
        #expect(clients.isRunning(in: Self.coaster))
        #expect(!clients.isRunning(in: Self.shelter))
        #expect(clients.otherBottles(than: Self.shelter) == [Self.coaster])
    }

    @Test("A Steam that restarted itself counts for the bottle whose wineserver is up")
    func restartedClientPlacedByWineserver() {
        let clients = SteamBottle.RunningClients.parse(ps: Self.ps([
            Self.restartedClient,
            Self.webHelper,
            Self.wineserver(Self.coaster),
        ]))
        #expect(clients.isRunning(in: Self.coaster))
        #expect(!clients.isRunning(in: Self.shelter), "no wineserver in Fallout Shelter's bottle, so not its Steam")
        #expect(clients.otherBottles(than: Self.shelter) == [Self.coaster])
        #expect(clients.otherBottles(than: Self.coaster).isEmpty)
    }

    @Test("The web helper alone is not a Steam client")
    func webHelperIsNotTheClient() {
        let clients = SteamBottle.RunningClients.parse(ps: Self.ps([
            Self.webHelper,
            Self.wineserver(Self.coaster),
        ]))
        #expect(!clients.isRunning(in: Self.coaster))
        #expect(clients.otherBottles(than: Self.shelter).isEmpty)
    }

    @Test("No Steam in the list is no client anywhere")
    func nothingRunning() {
        for text in ["", Self.ps([]), Self.ps([Self.wineserver(Self.coaster)])] {
            let clients = SteamBottle.RunningClients.parse(ps: text)
            #expect(!clients.isRunning(in: Self.coaster))
            #expect(!clients.isRunning(in: Self.shelter))
            #expect(clients.otherBottles(than: Self.shelter).isEmpty)
        }
    }

    @Test("An environment value keeps its spaces and ends at the next variable")
    func environmentValueKeepsSpaces() {
        let line = Self.wineserver(Self.coaster)
        #expect(SteamBottle.RunningClients.environmentValue("WINEPREFIX", in: line) == Self.coaster)
        #expect(SteamBottle.RunningClients.environmentValue("HOME", in: line) == Self.user)
        #expect(SteamBottle.RunningClients.environmentValue("WINEDEBUG", in: line) == "-all")
        #expect(SteamBottle.RunningClients.environmentValue("DYLD_FALLBACK_LIBRARY_PATH", in: line) == nil)
    }

    // MARK: - One shared Steam, one bottle at a time

    private static let skyrim = "\(prefixes)/skyrim-special-edition"

    @Test("Another bottle's Steam with nobody playing beside it is to be closed")
    func idleClientElsewhereIsStopped() {
        let clients = SteamBottle.RunningClients.parse(ps: Self.ps([
            Self.cellarStartedClient(Self.coaster),
            Self.wineserver(Self.coaster),
        ]))
        #expect(SteamBottle.elsewhere(prefix: Self.shelter, clients: clients, playing: []) == .stop([Self.coaster]),
                "it has no window, so the player can't close it: Cellar has to")
        #expect(SteamBottle.elsewhere(prefix: Self.shelter, clients: clients, playing: [Self.shelter])
                    == .stop([Self.coaster]),
                "a game playing in this bottle says nothing about the other bottle's Steam")
    }

    @Test("A Steam that restarted itself in another bottle is to be closed too")
    func restartedClientElsewhereIsStopped() {
        let clients = SteamBottle.RunningClients.parse(ps: Self.ps([
            Self.restartedClient,
            Self.webHelper,
            Self.wineserver(Self.coaster),
        ]))
        #expect(SteamBottle.elsewhere(prefix: Self.shelter, clients: clients, playing: []) == .stop([Self.coaster]))
    }

    @Test("Another bottle's Steam with a game playing beside it refuses the launch, naming that bottle")
    func busyClientElsewhereRefuses() {
        let clients = SteamBottle.RunningClients.parse(ps: Self.ps([
            Self.cellarStartedClient(Self.coaster),
            Self.wineserver(Self.coaster),
        ]))
        #expect(SteamBottle.elsewhere(prefix: Self.shelter, clients: clients, playing: [Self.coaster])
                    == .refuse(Self.coaster),
                "Cellar never takes down a Steam a game is playing beside")
    }

    @Test("With two other bottles' Steams up, the one a game is playing beside refuses; both idle are both closed")
    func twoClientsElsewhere() {
        let clients = SteamBottle.RunningClients.parse(ps: Self.ps([
            Self.cellarStartedClient(Self.coaster),
            Self.cellarStartedClient(Self.skyrim),
            Self.wineserver(Self.coaster),
            Self.wineserver(Self.skyrim),
        ]))
        #expect(SteamBottle.elsewhere(prefix: Self.shelter, clients: clients, playing: [Self.skyrim])
                    == .refuse(Self.skyrim))
        guard case .stop(let bottles) = SteamBottle.elsewhere(prefix: Self.shelter, clients: clients, playing: []) else {
            Issue.record("two idle Steams elsewhere must both be closed")
            return
        }
        #expect(bottles.sorted() == [Self.coaster, Self.skyrim].sorted())
    }

    @Test("This bottle's own Steam, a lone web helper, or no Steam at all leaves nothing to do elsewhere")
    func nothingElsewhere() {
        let cases: [[String]] = [
            [Self.cellarStartedClient(Self.shelter), Self.wineserver(Self.shelter)],
            [Self.restartedClient, Self.webHelper, Self.wineserver(Self.shelter)],
            [Self.webHelper, Self.wineserver(Self.coaster)],
            [],
        ]
        for lines in cases {
            let clients = SteamBottle.RunningClients.parse(ps: Self.ps(lines))
            #expect(SteamBottle.elsewhere(prefix: Self.shelter, clients: clients, playing: [Self.coaster]) == .none,
                    "\(lines)")
        }
    }

    // MARK: - Which games are playing

    @Test("A game is playing for every `cellar launch <slug>` running, and for nothing else")
    func playingSlugsReadsCellarLaunches() {
        let ps = """
          /sbin/launchd
          /Applications/Cellar.app/Contents/MacOS/CellarApp
          /Applications/Cellar.app/Contents/MacOS/cellar launch planet-coaster-2 --events
          /Users/x/.local/bin/cellar launch fallout-shelter --events
          /Users/x/.local/bin/cellar launch --help
          /Users/x/.local/bin/cellar status skyrim-special-edition
          /opt/tools/mycellar launch not-a-game
          /usr/bin/python3 /Users/x/rocket.py launch apollo-11
          \(Self.cellarStartedClient(Self.coaster))
          grep cellar launch
        """
        #expect(SteamBottle.playingSlugs(ps: ps).sorted() == ["fallout-shelter", "planet-coaster-2"])
    }

    @Test("No `cellar launch` running is no game playing")
    func playingSlugsEmpty() {
        #expect(SteamBottle.playingSlugs(ps: "").isEmpty)
        #expect(SteamBottle.playingSlugs(ps: Self.ps([Self.wineserver(Self.coaster)])).isEmpty)
    }
}
