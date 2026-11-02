import CellarDomain
import Foundation
import Testing
@testable import CellarData

/// The uninstall dialog speaks to a player (Kenneth, #266): the size, and that the game isn't gone
/// for good. Never a bottle, a runner, a manifest or a Terminal command.
@Suite("Uninstall dialog wording")
struct RemovalSummaryTests {
    private func plan(scope: RemovalScope, gameData: Bool) -> RemovalPlan {
        let items = [
            RemovalItem(label: "Game files", url: URL(fileURLWithPath: "/tmp/game"), bytes: 42_700_000_000,
                        kind: .path, isGameData: gameData),
            RemovalItem(label: "Steam manifest", url: URL(fileURLWithPath: "/tmp/m.acf"), bytes: 1_024,
                        kind: .path, isGameData: false),
        ]
        return RemovalPlan(slug: "planet-coaster-2", name: "Planet Coaster 2", store: .steam,
                           bottleName: "planet-coaster-2", scope: scope, items: items,
                           kept: ["The Wine runner 'wineforge', shared by every bottle. Remove runners with: cellar runner remove <id>"],
                           warnings: [], blockers: [], closesStoreClient: false)
    }

    @Test("Each kind of removal asks its own question and names the size", arguments: [
        (RemovalScope.game, true, "Uninstall Planet Coaster 2?"),
        (RemovalScope.game, false, "Clean up what's left of Planet Coaster 2?"),
        (RemovalScope.bottle, true, "Remove Planet Coaster 2 completely?"),
    ])
    func question(scope: RemovalScope, gameData: Bool, expected: String) {
        let removal = plan(scope: scope, gameData: gameData)
        #expect(removal.question == expected)
        #expect(removal.playerSummary.contains(removal.totalSizeDescription))
    }

    @Test("The summary says the game can come back, and carries no internals", arguments: [
        (RemovalScope.game, true), (RemovalScope.game, false), (RemovalScope.bottle, true),
    ])
    func plainWords(scope: RemovalScope, gameData: Bool) {
        let text = plan(scope: scope, gameData: gameData).playerSummary.lowercased()
        for word in ["bottle", "runner", "wine", "manifest", "cellar runner", "prefix", "<id>"] {
            #expect(!text.contains(word), "'\(word)' in: \(text)")
        }
        if gameData { #expect(text.contains("download it again")) }
    }

    @Test("Removing everything promises the save games are backed up first")
    func savesBackedUp() {
        #expect(plan(scope: .bottle, gameData: true).playerSummary.contains("backs up your save games"))
    }
}
