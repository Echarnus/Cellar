import CellarDomain
import Foundation
import Testing

/// The downloads queue (#168) and what each game says about itself while Cellar works on it (#167).
@Suite("Downloads queue")
struct InstallQueueTests {

    static func entry(_ slug: String, _ store: GameStore = .steam) -> InstallQueue.Entry {
        InstallQueue.Entry(slug: slug, name: slug.capitalized, store: store)
    }

    @Test("Games wait in the order they were asked for, and leave from the front")
    func order() {
        var queue = InstallQueue()
        #expect(queue.enqueue(Self.entry("skyrim")))
        #expect(queue.enqueue(Self.entry("witcher-3", .gog)))
        #expect(queue.position(of: "skyrim") == 1)
        #expect(queue.position(of: "witcher-3") == 2)
        #expect(queue.next()?.slug == "skyrim")
        #expect(queue.position(of: "witcher-3") == 1)
        #expect(queue.next()?.slug == "witcher-3")
        #expect(queue.next() == nil)
        #expect(queue.isEmpty)
    }

    @Test("Pressing Install twice is not two downloads, and the running game is not queued again")
    func noDoubles() {
        var queue = InstallQueue()
        #expect(queue.enqueue(Self.entry("skyrim")))
        #expect(!queue.enqueue(Self.entry("skyrim")))
        #expect(!queue.enqueue(Self.entry("planet-coaster-2"), running: "planet-coaster-2"))
        #expect(queue.count == 1)
    }

    @Test("A game taken out of the line lets the ones behind it move up")
    func remove() {
        var queue = InstallQueue([Self.entry("a"), Self.entry("b"), Self.entry("c")])
        #expect(queue.remove("b"))
        #expect(!queue.remove("b"))
        #expect(queue.waiting.map(\.slug) == ["a", "c"])
        #expect(queue.position(of: "c") == 2)
    }

    // MARK: - GameActivity

    @Test("Each game answers for itself: the running one works, a waiting one is queued, the rest nothing")
    func activityPerGame() {
        let queue = InstallQueue([Self.entry("skyrim"), Self.entry("dark-souls-3")])
        let progress = InstallProgress(.downloading, fraction: 0.03)
        #expect(GameActivity.of("planet-coaster-2", running: "planet-coaster-2", progress: progress, queue: queue)
                == .working(progress))
        #expect(GameActivity.of("skyrim", running: "planet-coaster-2", progress: progress, queue: queue)
                == .queued(position: 1))
        #expect(GameActivity.of("dark-souls-3", running: "planet-coaster-2", progress: progress, queue: queue)
                == .queued(position: 2))
        #expect(GameActivity.of("fallout-shelter", running: "planet-coaster-2", progress: progress, queue: queue) == nil,
                "a game Cellar is not working on shows its own state, never another game's download")
    }

    @Test("Downloading has a number, setting up says Installing, waiting says where in line")
    func statusText() {
        #expect(GameActivity.working(InstallProgress(.downloading, fraction: 0.349)).statusText.contains("34"))
        #expect(GameActivity.working(InstallProgress(.downloading, fraction: 0.349)).isDownloading)
        #expect(GameActivity.working(InstallProgress(.downloading)).statusText == "Downloading")
        for phase in [InstallPhase.runtime, .bottle, .client, .clientUpdate, .installing] {
            let activity = GameActivity.working(InstallProgress(phase))
            #expect(activity.statusText == "Installing", "\(phase)")
            #expect(!activity.isDownloading)
        }
        #expect(GameActivity.working(nil).statusText == "Installing")
        #expect(GameActivity.working(InstallProgress(.updating, fraction: 0.5)).statusText.contains("50"))
        #expect(GameActivity.queued(position: 1).statusText == "Up next")
        #expect(GameActivity.queued(position: 3).statusText.contains("3"))
        #expect(!GameActivity.queued(position: 1).isDownloading)
    }

    @Test("Only a 100% that is really done says 100")
    func percentRoundsDown() {
        #expect(!GameActivity.working(InstallProgress(.downloading, fraction: 0.999)).statusText.contains("100"))
    }

    @Test("Steam and GOG installs can wait their turn; Battle.net's opens a window, so it never waits")
    func queueableStores() {
        #expect(GameStore.steam.descriptor.queuesInstalls)
        #expect(GameStore.gog.descriptor.queuesInstalls)
        #expect(!GameStore.battlenet.descriptor.queuesInstalls)
    }
}
