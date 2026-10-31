import CellarDomain
import ArgumentParser
import CellarData
import Foundation

/// Cellar, and everything it put on this Mac, gone — with the save games kept unless asked.
///
/// `cellar reset --everything` already removes it all; this is the uninstaller built on it, with
/// the one thing a reset does not do: copy the save games out of the bottles first. The app's
/// Cellar › Uninstall Cellar… runs this.
struct UninstallCellarCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "uninstall-cellar",
        abstract: "Remove Cellar from this Mac — the app, the command, bottles, runners and games.",
        discussion: """
        Prints what it will remove, with sizes, and removes nothing without --yes.

        Save games are kept by default: before anything is deleted, every bottle's save folders
        (Documents, Saved Games and AppData) and the Steam client's local cloud data are copied to
        Documents › Cellar Saved Games. If that copy fails, nothing is deleted. --no-keep-saves
        skips it.

        Games you own stay yours: they come back from the store that sold them if you reinstall.
        Saves your games already keep in your Mac's own Documents folder are not touched.
        """)

    @Flag(name: .long, help: "Actually remove. Without it, this only shows the plan.")
    var yes = false

    @Flag(inversion: .prefixedNo, help: "Copy save games to Documents › Cellar Saved Games first.")
    var keepSaves = true

    func run() throws {
        let items = Reset.plan(includingCellarItself: true)
        let saves = keepSaves ? SaveGames.locate() : []
        func size(_ item: Reset.Item) -> String {
            item.url == nil ? "no disk space" : Reset.humanSize(item.bytes)
        }

        print(Term.bold("Uninstalling Cellar removes:"))
        for item in items {
            print("  \(Term.yellow("×")) \(item.title)")
            print("      \(Term.dim(size(item)))")
            if let url = item.url { print("      \(Term.dim(url.path))") }
        }
        print("  \(Term.yellow("×")) " + "Cellar's folder, with anything left in it")
        print("      \(Term.dim(Paths.appSupport.path))")
        print(Term.bold("Total: ") + Reset.humanSize(Reset.totalBytes(items)))

        let destination = SaveGames.defaultDestination()
        if keepSaves {
            if saves.isEmpty {
                print(Term.green("Save games: ") + "none found inside Cellar's bottles.")
            } else {
                let total = Reset.humanSize(saves.reduce(0) { $0 + $1.bytes })
                print(Term.green("Save games are kept: ") + "\(saves.count) folder(s), \(total), copied first to")
                print("      " + Term.dim(destination.path))
            }
        } else if let warning = Reset.saveGameWarning(in: items, backedUp: false) {
            print(Term.yellow("Careful: ") + warning)
        }
        if SaveGames.someSavesAlreadyInDocuments {
            print(Term.dim("Saves your games keep in your Mac's Documents folder stay where they are."))
        }

        guard yes else {
            print("")
            print(Term.dim("Nothing has been removed. To go ahead: cellar uninstall-cellar --yes"))
            return
        }

        // Saves first. If the copy fails nothing is deleted — the originals are still the only copy.
        if !saves.isEmpty {
            do {
                try SaveGames.export(saves, to: destination) { print("  " + Term.dim($0)) }
                print(Term.green("Save games copied to ") + destination.path)
            } catch {
                print(Term.red("Could not copy your save games, so nothing was removed: ")
                    + error.localizedDescription)
                print(Term.dim("  Free some disk space, or run with --no-keep-saves to remove them too."))
                throw ExitCode(1)
            }
        }

        var failures = Reset.perform(items, backUpSaves: false) { print("  " + Term.dim($0)) }
        // Last: the folder itself, with the logs this very run may have just written into it.
        if FileManager.default.fileExists(atPath: Paths.appSupport.path) {
            do { try FileManager.default.removeItem(at: Paths.appSupport) } catch {
                failures.append("\(Paths.appSupport.lastPathComponent): \(error.localizedDescription)")
            }
        }

        if failures.isEmpty {
            print(Term.green("Cellar is uninstalled.") + " Nothing of it is left on this Mac"
                + (saves.isEmpty ? "." : " except your save games."))
        } else {
            print(Term.yellow("Removed what it could.") + " These were left behind:")
            for failure in failures { print("  " + failure) }
            print(Term.dim("  A running game will do that. Quit it and run this again."))
            throw ExitCode(1)
        }
    }
}
