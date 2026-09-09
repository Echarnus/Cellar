import ArgumentParser
import CellarKit
import Foundation

struct UninstallCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "uninstall",
        abstract: "Remove an installed game and everything Cellar put on disk for it.",
        discussion: """
        Deletes the game's files, the launcher app Cellar generated in ~/Applications, the icon it
        extracted, and the entry it added to your native Steam library. Nothing else: the bottle,
        the Wine runner and your store sign-in all stay, so re-installing is just the download.

        Add --bottle to remove the bottle as well — the Wine prefix, its registry and the store
        client installed inside it.

        Cellar prints exactly what it will delete, and what it will keep, before it deletes anything.
        """
    )

    @Argument(help: "Profile slug of the game to remove, e.g. 'planet-coaster-2'.")
    var profile: String

    @Flag(name: [.customLong("bottle"), .customLong("everything")],
          help: "Also remove the bottle: the Wine prefix, its registry and the store client in it.")
    var removeBottle = false

    @Flag(name: .shortAndLong, help: "Don't ask for confirmation.")
    var yes = false

    @Flag(name: .customLong("dry-run"), help: "Show what would be removed and stop.")
    var dryRun = false

    func run() throws {
        let game = try Game.plan(slug: profile)
        let scope: RemovalScope = removeBottle ? .bottle : .game
        let removal = Uninstall.plan(for: game, scope: scope)

        print(Term.bold("Uninstall \(game.name)")
            + Term.dim("  (store: \(game.store.displayName), bottle: \(game.bottleName))"))
        print("")

        // A blocker first: a plan can be empty *because* something stopped it being made, and
        // "nothing to remove" in place of "that bottle belongs to two other games" is a lie.
        if let blocker = removal.blockers.first {
            print(Term.red("Can't remove it. ") + blocker)
            throw ExitCode.failure
        }

        guard !removal.isEmpty else {
            let bottleExists = FileManager.default.fileExists(atPath: game.prefix.path)
            print("Nothing to remove — \(game.name) isn't installed"
                + (scope == .bottle && !bottleExists ? " and its bottle doesn't exist." : "."))
            print(Term.dim("  Install it with: cellar setup --profile \(profile)"))
            return
        }

        // An uninstall of a game that was never installed is a tidy-up, and saying so is the
        // difference between "Cellar removed my game" and "Cellar swept up after itself".
        if removal.removesGameFiles || scope == .bottle {
            print(Term.bold("This deletes:"))
        } else {
            print("\(game.name) isn't installed. " + Term.bold("These leftovers can still go:"))
        }
        for item in removal.items {
            let size = item.kind == .steamShortcut ? "" : ByteSize.describe(item.bytes)
            print("  \(item.label.padded(to: 30))\(size.padded(to: 10))\(Term.dim(item.displayPath))")
        }
        print("  " + Term.bold("Total".padded(to: 30) + removal.totalSizeDescription))
        print("")

        if !removal.kept.isEmpty {
            print(Term.bold("This stays:"))
            for line in removal.kept { print("  • \(line)") }
            print("")
        }
        for warning in removal.warnings {
            print(Term.yellow("Note: ") + warning)
        }
        if !removal.warnings.isEmpty { print("") }

        if dryRun {
            print(Term.dim("Dry run — nothing was deleted."))
            return
        }

        if !yes {
            print("Delete \(removal.totalSizeDescription)? " + Term.dim("[y/N] "), terminator: "")
            let answer = readLine()?.trimmingCharacters(in: .whitespaces).lowercased() ?? ""
            guard answer == "y" || answer == "yes" else {
                print("Left everything where it was.")
                return
            }
            print("")
        }

        let freed = try Uninstall.perform(removal, for: game) { print("  " + Term.dim($0)) }
        print("")
        print(Term.green(removal.removesGameFiles || scope == .bottle
                         ? "Removed \(game.name)." : "Cleaned up after \(game.name).")
            + " Freed \(ByteSize.describe(freed)).")
        switch scope {
        case .game:
            print(Term.dim("  Install it again with: cellar \(reinstallCommand(for: game))"))
        case .bottle:
            print(Term.dim("  Start over with: cellar setup --profile \(profile)"))
        }
    }

    /// The command that puts this game back, in the store's own terms — the last line of an
    /// uninstall is the best place to say that undoing it is one command.
    private func reinstallCommand(for game: GamePlan) -> String {
        switch game.store {
        case .steam:      return "steam install \(game.slug)"
        case .battlenet:  return "battlenet open \(game.slug)"
        case .gog:        return "gog install \(game.slug)"
        case .standalone: return "fetch-depot \(game.slug)"
        }
    }
}

private extension String {
    /// Left-aligned in a fixed column, so the table lines up without a formatter.
    func padded(to width: Int) -> String {
        count >= width ? self + "  " : self + String(repeating: " ", count: width - count)
    }
}
