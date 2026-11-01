import CellarDomain
import Testing

/// What each game's page says while Cellar works (#195): only its own game's work, never another's.
@Suite("Game page status")
struct GamePageStatusTests {

    typealias Runner = GamePageStatus.Runner

    static let launchingCoaster = Runner(busy: true, game: "planet-coaster-2", title: "Launching", launching: true)
    static let playingCoaster = Runner(busy: true, game: "planet-coaster-2", title: "Launching",
                                       launching: true, playing: true)

    @Test("Planet Coaster 2 starting is not Skyrim starting")
    func launchStaysOnItsOwnPage() {
        #expect(GamePageStatus.of("planet-coaster-2", runner: Self.launchingCoaster, queuePosition: nil)
                == .busy(title: "Launching", launch: true))
        #expect(GamePageStatus.of("skyrim", runner: Self.launchingCoaster, queuePosition: nil)
                == .anotherGameRunning,
                "the bug: Skyrim, not even installed, read \"Launching\" while Planet Coaster 2 started")
    }

    @Test("Playing is said on the played game's page only, for the whole session")
    func playingStaysOnItsOwnPage() {
        #expect(GamePageStatus.of("planet-coaster-2", runner: Self.playingCoaster, queuePosition: nil) == .playing)
        #expect(GamePageStatus.of("skyrim", runner: Self.playingCoaster, queuePosition: nil) == .anotherGameRunning)
    }

    @Test("Another game's repair or move is not this game's either")
    func otherGameWork() {
        let repairing = Runner(busy: true, game: "witcher-3", title: "Repairing The Witcher 3")
        #expect(GamePageStatus.of("witcher-3", runner: repairing, queuePosition: nil)
                == .busy(title: "Repairing The Witcher 3", launch: false))
        #expect(GamePageStatus.of("skyrim", runner: repairing, queuePosition: nil) == .anotherGameBusy)
    }

    @Test("Downloads: the downloading game draws its bar, another says so, a queued one says where in line")
    func downloads() {
        let downloading = Runner(busy: true, game: "planet-coaster-2", title: "Installing", installing: true)
        #expect(GamePageStatus.of("planet-coaster-2", runner: downloading, queuePosition: nil) == .installing)
        #expect(GamePageStatus.of("skyrim", runner: downloading, queuePosition: nil) == .anotherGameDownloading)
        #expect(GamePageStatus.of("skyrim", runner: downloading, queuePosition: 2) == .queued(position: 2))
        #expect(GamePageStatus.of("skyrim", runner: Self.playingCoaster, queuePosition: 1) == .queued(position: 1),
                "a download queued behind a play session still says where it is in line")
    }

    @Test("Work for Cellar as a whole shows on every page: it is why every button waits")
    func appWideWork() {
        let signingIn = Runner(busy: true, game: nil, title: "Signing in")
        #expect(GamePageStatus.of("skyrim", runner: signingIn, queuePosition: nil)
                == .busy(title: "Signing in", launch: false))
        #expect(GamePageStatus.of("skyrim", runner: .idle, queuePosition: nil) == .idle)
    }

    @Test("Every command that works on a game names it; Cellar's own work names none")
    func commandsNameTheirGame() {
        for command in CellarCommand.examples {
            let slugInArguments = command.arguments.contains("game")
            #expect((command.game == "game") == slugInArguments, "\(command)")
        }
        #expect(CellarCommand.launch(slug: "planet-coaster-2", showHUD: false, backend: nil).game == "planet-coaster-2")
        #expect(CellarCommand.steamSignIn.game == nil)
    }
}
