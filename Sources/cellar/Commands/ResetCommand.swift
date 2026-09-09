import ArgumentParser
import CellarKit

/// Back to "Cellar has never run here".
struct ResetCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "reset",
        abstract: "Remove everything Cellar has put on this Mac — bottles, runners, games, sign-in.",
        discussion: """
        Prints exactly what it will delete, with sizes, and deletes nothing without --yes. All of it
        is re-obtainable: runners re-download, bottles rebuild, games come back from the store that
        sold them, and signing in is one QR scan.

        Local save games live inside bottles. Anything a game saved only on this Mac — not to Steam
        Cloud — goes with them.
        """)

    @Flag(name: .long, help: "Actually delete. Without it, this only shows the plan.")
    var yes = false

    @Flag(name: .long, help: "Keep the downloaded Wine runners (they are the slowest to re-fetch).")
    var keepRunners = false

    func run() throws {
        var items = Reset.plan()
        if keepRunners { items.removeAll { $0.url == Paths.runners } }
        // Sizes only make sense for files; a keychain item has none and is not pretended to.
        func size(_ item: Reset.Item) -> String {
            item.url == nil ? "no disk space" : Reset.humanSize(item.bytes)
        }

        guard !items.isEmpty else {
            print(Term.green("Nothing to remove.") + " Cellar has no state on this Mac.")
            return
        }

        print(Term.bold("This removes:"))
        for item in items {
            print("  \(Term.yellow("×")) \(item.title)")
            print("      \(Term.dim(size(item) + " · " + item.cost))")
            if let url = item.url { print("      \(Term.dim(url.path))") }
        }
        print(Term.bold("Total: ") + Reset.humanSize(Reset.totalBytes(items)))
        if let warning = Reset.saveGameWarning(in: items) {
            print(Term.yellow("Careful: ") + warning)
        }

        guard yes else {
            print("")
            print(Term.dim("Nothing has been deleted. To go ahead: cellar reset --yes"))
            return
        }

        let failures = Reset.perform(items) { print("  " + Term.dim($0)) }
        if failures.isEmpty {
            print(Term.green("Clean slate.") + " Start again with: cellar steam login")
        } else {
            print(Term.yellow("Removed what it could.") + " These were left behind:")
            for failure in failures { print("  " + failure) }
            print(Term.dim("  A running game or a mounted volume will do that. Quit it and re-run."))
        }
    }
}
