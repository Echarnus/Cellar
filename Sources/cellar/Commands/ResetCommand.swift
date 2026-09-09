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

        This reaches outside Cellar's own folder: the launcher apps it put in ~/Applications and the
        entries it added to your Steam library go too, because leaving those behind means icons that
        open nothing. Only ones Cellar created — never a shortcut you made yourself.

        Cellar.app and the cellar command stay, so you can carry on using it. Add --everything to
        remove those as well and leave nothing behind.
        """)

    @Flag(name: .long, help: "Actually delete. Without it, this only shows the plan.")
    var yes = false

    @Flag(name: .long, help: "Keep the downloaded Wine runners (they are the slowest to re-fetch).")
    var keepRunners = false

    @Flag(name: .long, help: "Also remove Cellar.app and the cellar command — a full uninstall.")
    var everything = false

    func run() throws {
        var items = Reset.plan(includingCellarItself: everything)
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

        // Say what stays. A command called "remove everything" that quietly leaves two things is
        // the kind of half-truth skills/ux.md exists to stop.
        let staying = Reset.leftBehind(after: items)
        if !staying.isEmpty {
            print(Term.bold("This stays:"))
            for url in staying { print("  \(Term.dim("·")) \(url.path)") }
            print(Term.dim("      so you can keep using Cellar · remove these too with --everything"))
        }

        guard yes else {
            print("")
            print(Term.dim("Nothing has been deleted. To go ahead: cellar reset --yes"))
            return
        }

        let failures = Reset.perform(items) { print("  " + Term.dim($0)) }
        if failures.isEmpty {
            if everything {
                print(Term.green("Cellar is gone.") + " Nothing of it is left on this Mac.")
            } else {
                print(Term.green("Clean slate.") + " Start again with: cellar steam login")
            }
        } else {
            print(Term.yellow("Removed what it could.") + " These were left behind:")
            for failure in failures { print("  " + failure) }
            print(Term.dim("  A running game or a mounted volume will do that. Quit it and re-run."))
        }
    }
}
