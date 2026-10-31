import CellarDomain
import ArgumentParser
import CellarData
import Foundation

struct SavesCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "saves",
        abstract: "Back up and restore a game's save games.",
        discussion: """
        Cellar copies a game's saves out of its bottle before anything that could lose them — a
        reset, removing the bottle, a game or runner update — and keeps the last \(SaveBackups.keep).

          cellar saves list planet-coaster-2                 the backups, newest first
          cellar saves backup planet-coaster-2               take one now
          cellar saves restore planet-coaster-2              put the newest one back
          cellar saves restore planet-coaster-2 --backup "2026-10-30 22.41.07"
        """,
        subcommands: [List.self, Backup.self, Restore.self],
        defaultSubcommand: List.self
    )

    static func line(_ backup: SaveBackups.Backup) -> String {
        Term.bold(backup.id) + "  " + backup.manifest.reason.description
            + Term.dim("  (\(backup.manifest.paths.count) folder(s), \(ByteSize.describe(backup.manifest.bytes)))")
    }

    struct List: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "List a game's save backups, newest first.")

        @Argument(help: "Profile slug, e.g. 'planet-coaster-2'.")
        var slug: String

        func run() throws {
            let plan = try Game.plan(slug: slug)
            let backups = SaveBackups.list(bottle: plan.bottleName)
            guard !backups.isEmpty else {
                print("No save backups for \(plan.name) yet. Take one: cellar saves backup \(slug)")
                return
            }
            print("\(plan.name)'s save backups, newest first:")
            for backup in backups { print("  " + SavesCommand.line(backup)) }
            print(Term.dim("In Finder: \(SaveBackups.directory(forBottle: plan.bottleName).path)"))
        }
    }

    struct Backup: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Back up a game's save games now.")

        @Argument(help: "Profile slug, e.g. 'planet-coaster-2'.")
        var slug: String

        func run() throws {
            let plan = try Game.plan(slug: slug)
            guard FileManager.default.fileExists(atPath: plan.prefix.path) else {
                throw CellarError.invalidArgument("\(plan.name) has no bottle yet, so it has no saves to back up.")
            }
            guard let backup = try SaveBackups.backUp(bottle: plan.prefix, reason: .manual) else {
                print("\(plan.name) has no save games in its bottle yet — nothing to back up.")
                return
            }
            print(Term.green("Backed up: ") + SavesCommand.line(backup))
        }
    }

    struct Restore: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Put a backup of a game's saves back. The saves as they are now are backed up first.")

        @Argument(help: "Profile slug, e.g. 'planet-coaster-2'.")
        var slug: String

        @Option(name: .long, help: "Which backup, as `cellar saves list` names it. Default: the newest.")
        var backup: String?

        func run() throws {
            let plan = try Game.plan(slug: slug)
            let backups = SaveBackups.list(bottle: plan.bottleName)
            let chosen: SaveBackups.Backup
            if let backup {
                guard let match = backups.first(where: { $0.id == backup }) else {
                    throw CellarError.invalidArgument("\(plan.name) has no backup '\(backup)'. See them: cellar saves list \(slug)")
                }
                chosen = match
            } else {
                guard let newest = backups.first else {
                    throw CellarError.invalidArgument("\(plan.name) has no save backups to restore.")
                }
                chosen = newest
            }
            if Uninstall.isGameRunning(plan) {
                throw CellarError.invalidArgument("\(plan.name) is running. Quit it first — it would overwrite the restored saves.")
            }
            try SaveBackups.restore(chosen, into: plan.prefix) { print("  " + Term.dim($0)) }
            print(Term.green("Restored: ") + SavesCommand.line(chosen))
        }
    }
}
