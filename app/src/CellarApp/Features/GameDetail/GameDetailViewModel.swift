import CellarDomain
import Foundation
import Observation
import CellarData

/// The game page's state: what it read about one game from this Mac (its language, its newest save
/// backup, the controllers plugged in) and the engine calls behind the page's own buttons.
///
/// `GameDetailView` owns one and calls `load(_:)` when the selected game changes. The view keeps the
/// parts only AppKit can do (panels, alerts); every read of the machine goes through here.
@MainActor
@Observable
final class GameDetailViewModel {
    /// The game's language submenu, read when the page appears rather than from the body.
    var language = GameLanguageMenu.Selection()
    /// The newest copy of this game's saves, read when the page appears and after a backup or restore.
    private(set) var latestBackup: SaveBackups.Backup?
    /// The controllers macOS sees, kept current as pads come and go.
    private(set) var pads: [Controllers.Pad] = []
    /// Wheels, pedals and shifters, read when the page appears (macOS posts no notice for them).
    private(set) var wheels: [Wheels.Device] = []

    /// Read everything the page shows about `game` from the machine.
    func load(_ game: GameSummary) {
        language = .load(game)
        refreshBackups(of: game)
        refreshPads()
        wheels = Wheels.connected()
    }

    func refreshPads() {
        pads = Controllers.connected()
    }

    func refreshBackups(of game: GameSummary) {
        latestBackup = SaveBackups.list(bottle: game.bottleName).first
    }

    /// Where this game's save backups are kept, for "Show in Finder".
    func backupFolder(of game: GameSummary) -> URL {
        SaveBackups.directory(forBottle: game.bottleName)
    }

    /// When Cellar last copied the saves out, and why — or that it never has.
    var backupSummary: String {
        guard let backup = latestBackup else {
            return String(localized: "No backup yet. Cellar takes one by itself before a reset, an update or removing the bottle.")
        }
        let when = RelativeDateTimeFormatter().localizedString(for: backup.manifest.created, relativeTo: Date())
        return String(localized: "Last backed up \(when) — \(backup.manifest.reason.description.lowercased()), \(ByteSize.describe(backup.manifest.bytes)). Cellar keeps the last \(SaveBackups.keep).")
    }

    /// What force feedback the connected wheels get, said once under their names.
    var forceFeedbackNote: String {
        Wheels.forceFeedbackNote(for: wheels, cellarSDL: CellarSDL.libraryDirectory != nil)
    }

    /// Hand the backend back to the profile. False when the bottle could not be written, which
    /// leaves the page as it was: the truth.
    func resetBackend(of game: GameSummary) -> Bool {
        (try? BackendChoice.set(nil, in: BottleConfig.url(forBottle: game.bottleName))) != nil
    }
}
