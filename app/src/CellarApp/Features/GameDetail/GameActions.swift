import CellarDomain
import SwiftUI
import AppKit
import CellarData

/// What each entry of a game's menu does — one implementation behind both of the places the menu
/// appears: the "…" button on the game's page and a right-click on the game in the library.
///
/// The two menus used to be built separately, and the library's had only Play and Settings, so
/// the one action a player reaches for from a list — Uninstall — was a page away (#304). Which
/// entries exist, and in which words, is `GameMenu`'s call; this only carries them out.
@MainActor
struct GameActions {
    let game: GameSummary
    let runner: ActivityStore
    let onChange: () -> Void
    /// Runs before any entry does — the library selects the game, so its page is on screen.
    var before: () -> Void = {}

    func perform(_ item: GameMenu.Item) {
        before()
        switch item {
        case .addToApplications:
            act(.addToApplications(slug: game.slug), String(localized: "Adding to Applications"))
        case .addToMacSteam:
            act(.steamAddShortcut(slug: game.slug), String(localized: "Adding"))
        case .language:
            break   // a submenu of its own
        case .moveToDrive:
            chooseDrive()
        case .moveBack:
            act(.moveBack(slug: game.slug), String(localized: "Moving \(game.name) back"))
        case .uninstall:
            confirmRemoval(scope: .game)
        case .repair:
            act(.setUp(slug: game.slug), String(localized: "Repairing \(game.name)"))
        case .openClient:
            if game.store == .battlenet {
                act(.battleNetOpen(slug: game.slug), String(localized: "Opening Battle.net"))
            } else {
                act(.steamOpen(slug: game.slug), String(localized: "Opening Steam"))
            }
        case .reapplyClientSettings:
            act(.battleNetConfigure(slug: game.slug), String(localized: "Configuring"))
        case .checkForUpdates:
            act(.checkForUpdate(slug: game.slug), String(localized: "Checking \(game.name) for updates"))
        case .saveProfile:
            exportProfile()
        case .technicalDetails:
            TechnicalDetailsWindow.present(game: game, runner: runner)
        case .saveDiagnostics:
            saveDiagnostics()
        case .showLogs:
            NSWorkspace.shared.open(Paths.logs)
        case .removeEverything:
            confirmRemoval(scope: .bottle)
        }
    }

    private func act(_ command: CellarCommand, _ title: String) {
        runner.run(command, title: title, then: { onChange() })
    }

    /// Show what removal would take, and only then run it — through the CLI, like every other
    /// side-effecting action, so the app inherits the same tested path (and its activity log).
    ///
    /// The measuring is kept on the shared `ActivityStore`, not on the page, so the game's page
    /// says "Working out what would be deleted…" whichever menu asked.
    private func confirmRemoval(scope: RemovalScope) {
        let runner = runner, game = game, onChange = onChange
        runner.measuringRemoval = game.slug
        UninstallConfirmation.ask(for: game, scope: scope, measured: { runner.measuringRemoval = nil }) {
            runner.run(.uninstall(slug: game.slug, scope: scope),
                       title: scope == .bottle ? String(localized: "Removing \(game.name)") : String(localized: "Uninstalling"),
                       then: { onChange() })
        }
    }

    /// Pick a folder on another drive, then move the game there through the CLI.
    private func chooseDrive() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = String(localized: "Move Here")
        panel.message = String(localized: "Choose a folder on the drive to move \(game.name) to. Cellar puts it in a “Cellar Games” folder there, and the game plays and updates from it while the drive is connected.")
        panel.directoryURL = URL(fileURLWithPath: "/Volumes", isDirectory: true)
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        act(.moveToDrive(slug: game.slug, folder: folder.path), String(localized: "Moving \(game.name)"))
    }

    /// Copy a draft profile out, for contributing it once the game is known to run.
    private func exportProfile() {
        guard let source = ProfileStore.find(game.slug)?.url else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = source.lastPathComponent
        panel.message = String(localized: "Cellar guessed this profile's settings. If \(game.name) runs, set status and notes to what you saw, then contribute it to Cellar's profiles.")
        guard panel.runModal() == .OK, let target = panel.url else { return }
        try? FileManager.default.removeItem(at: target)
        try? FileManager.default.copyItem(at: source, to: target)
    }

    /// Write the report and show it in Finder, so the player has the file in hand to attach.
    private func saveDiagnostics() {
        Task.detached(priority: .userInitiated) {
            let url = try? Diagnostics.exportReport(cellarVersion: CellarVersion.current)
            await MainActor.run {
                if let url { NSWorkspace.shared.activateFileViewerSelecting([url]) }
            }
        }
    }
}
