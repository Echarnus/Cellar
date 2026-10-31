import CellarDomain
import Foundation
import Testing
@testable import CellarData

/// The game page's "…" menu, held to what Kenneth asked of it: a player sees what a gamer needs, in
/// plain words, and everything that is there to fix something waits under Troubleshooting.
@Suite
struct GameMenuTests {

    private func game(store: GameStore = .steam,
                      gameInstalled: Bool = true,
                      bottleExists: Bool = true,
                      clientInstalled: Bool = true,
                      needsLiveSession: Bool = true,
                      update: UpdateState? = nil,
                      isDraft: Bool = false,
                      isOnOtherDrive: Bool = false) -> GameSummary {
        var summary = GameSummary(
            slug: "fixture", name: "Fixture", store: store, appID: 1, iconPath: nil,
            runnerInstalled: true, clientInstalled: clientInstalled, account: "kenneth",
            gameInstalled: gameInstalled, bottleExists: bottleExists, running: false,
            productCode: nil, needsLiveSession: needsLiveSession, artworkAppID: nil,
            artPortraitURL: nil, artHeroURL: nil, needsClientAtRuntime: needsLiveSession,
            update: update, facts: GameFacts(), runnerID: "wineforge", backend: "d3dmetal",
            bottleName: "fixture")
        summary.isDraft = isDraft
        summary.isOnOtherDrive = isOnOtherDrive
        return summary
    }

    /// Every shape of game the menu has to handle, across all three stores.
    private var everyGame: [GameSummary] {
        GameStore.allCases.flatMap { store in
            [true, false].flatMap { installed in
                [true, false].flatMap { bottle in
                    [true, false].map { live in
                        game(store: store, gameInstalled: installed, bottleExists: bottle,
                             clientInstalled: bottle, needsLiveSession: live,
                             update: store == .steam ? .unknown("not checked") : nil, isDraft: !live)
                    }
                }
            }
        }
    }

    /// The words Kenneth asked to keep away from players.
    private static let jargon = ["bottle", "runner", "wine", "prefix", "d3dmetal", "dxvk", "log", "profile", "client"]

    @Test("An installed Steam game's menu is the short list: Applications, Steam, language, move, uninstall")
    func steamTopLevel() {
        #expect(GameMenu(game: game()).main == [
            [.addToApplications, .addToMacSteam, .language],
            [.moveToDrive],
            [.uninstall],
        ])
    }

    @Test("The top level never says bottle, runner, Wine, log or profile")
    func topLevelHasNoJargon() {
        for summary in everyGame {
            for item in GameMenu(game: summary).main.flatMap({ $0 }) {
                let title = item.title(for: summary).lowercased()
                for word in Self.jargon {
                    #expect(!title.contains(word), "'\(title)' (\(summary.store)) says '\(word)'")
                }
            }
        }
    }

    @Test("Nothing anywhere in the menu says bottle")
    func noBottleAnywhere() {
        for summary in everyGame {
            for item in GameMenu(game: summary).allItems {
                #expect(!item.title(for: summary).lowercased().contains("bottle"))
            }
        }
    }

    @Test("Installing is the page's big button: the top level offers no second way in", arguments: GameStore.allCases)
    func noSecondInstall(_ store: GameStore) {
        for installed in [true, false] {
            let main = GameMenu(game: game(store: store, gameInstalled: installed)).main.flatMap { $0 }
            #expect(!main.contains(.installThroughClient))
            #expect(!main.contains(.repair))
            #expect(!main.contains(.openClient))
        }
    }

    @Test("Troubleshooting always has the details, the report and the logs")
    func diagnosticsAlwaysThere() {
        for summary in everyGame {
            let fixes = GameMenu(game: summary).troubleshooting.flatMap { $0 }
            #expect(fixes.contains(.technicalDetails))
            #expect(fixes.contains(.saveDiagnostics))
            #expect(fixes.contains(.showLogs))
        }
    }

    @Test("Removing everything is under Troubleshooting, last, and only when there is something to remove")
    func removeEverythingIsLastResort() {
        let menu = GameMenu(game: game())
        #expect(!menu.main.flatMap { $0 }.contains(.removeEverything))
        #expect(menu.troubleshooting.last == [.removeEverything])
        #expect(!GameMenu(game: game(bottleExists: false)).allItems.contains(.removeEverything))
        #expect(GameMenu.Item.removeEverything.isDestructive)
        #expect(GameMenu.Item.uninstall.isDestructive)
    }

    @Test("A game that isn't installed offers no uninstall, no move and no language before its set-up exists")
    func notInstalled() {
        let main = GameMenu(game: game(gameInstalled: false, bottleExists: false)).main.flatMap { $0 }
        #expect(!main.contains(.uninstall))
        #expect(!main.contains(.moveToDrive))
        #expect(!main.contains(.language))
        #expect(main.contains(.addToApplications))
    }

    @Test("A download that stopped partway can still be uninstalled, though it is not a game yet")
    func interruptedDownload() {
        var summary = game(gameInstalled: false)
        summary.installInterrupted = true
        let main = GameMenu(game: summary).main.flatMap { $0 }
        #expect(main.contains(.uninstall))
        #expect(!main.contains(.moveToDrive), "nothing whole to move yet")
    }

    @Test("Battle.net games are never moved behind Blizzard's back")
    func battleNetStays() {
        let menu = GameMenu(game: game(store: .battlenet))
        #expect(!menu.allItems.contains(.moveToDrive))
        #expect(!menu.allItems.contains(.addToMacSteam))
        #expect(menu.troubleshooting.first == [.repair, .openClient, .reapplyClientSettings])
        #expect(GameMenu.Item.openClient.title(for: game(store: .battlenet)) == "Open Battle.net")
    }

    @Test("A game on another drive offers the way back instead of another move")
    func otherDrive() {
        let main = GameMenu(game: game(isOnOtherDrive: true)).main.flatMap { $0 }
        #expect(main.contains(.moveBack))
        #expect(!main.contains(.moveToDrive))
    }

    @Test("Steam's own client is only offered where the game has one")
    func steamClientOnlyWhereThereIsOne() {
        let none = GameMenu(game: game(clientInstalled: false, needsLiveSession: false)).allItems
        #expect(!none.contains(.openClient))
        #expect(!none.contains(.installThroughClient))
        let some = GameMenu(game: game()).allItems
        #expect(some.contains(.openClient))
        #expect(some.contains(.installThroughClient))
    }

    @Test("Updates are checked from Troubleshooting, and only for a game Cellar keeps current")
    func updates() {
        #expect(GameMenu(game: game(update: .unknown("not checked"))).troubleshooting.flatMap { $0 }.contains(.checkForUpdates))
        #expect(!GameMenu(game: game(update: nil)).allItems.contains(.checkForUpdates))
    }

    @Test("GOG keeps no install or accounts entry: the button installs, Settings holds the account")
    func gogIsShort() {
        let menu = GameMenu(game: game(store: .gog, clientInstalled: false, needsLiveSession: false))
        #expect(menu.main == [[.addToApplications, .language], [.moveToDrive], [.uninstall]])
        #expect(!menu.allItems.contains(.openClient))
    }

    @Test("Overview facts are who and when; the engine and graphics API are technical")
    func factsSplit() {
        let facts = GameFacts(developer: "Frontier", released: "2024", engine: "Cobra", graphicsAPI: "DX12")
        #expect(facts.overview.map(\.label) == ["Developer", "Released"])
        #expect(facts.technical.map(\.label) == ["Engine", "Graphics API"])
    }
}
