import ArgumentParser
import CellarKit
import Foundation

struct StorageCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "storage",
        abstract: "See what Cellar uses on disk, clean up, and move games to another drive.",
        discussion: """
          cellar storage                                       what uses the space, largest first
          cellar storage clean                                 delete installers and scratch files
          cellar storage move stardew-valley --to /Volumes/Games
          cellar storage move-back stardew-valley              bring it back to this Mac

        Only games Cellar downloaded itself can move; Steam keeps its own list of where the games
        it installed are.
        """,
        subcommands: [Show.self, Clean.self, Move.self, MoveBack.self],
        defaultSubcommand: Show.self
    )

    struct Show: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Show what Cellar uses on disk.")

        func run() throws {
            let usage = GameStorage.usage()
            guard !usage.isEmpty else { print("Cellar isn't using any disk space yet."); return }
            for item in usage {
                let size = ByteSize.describe(item.bytes).padding(toLength: 10, withPad: " ", startingAt: 0)
                print("  \(size) \(item.label)" + (item.cleanable ? Term.dim("  (cellar storage clean)") : ""))
            }
            print(Term.bold("Total: ") + ByteSize.describe(usage.reduce(0) { $0 + $1.bytes }))
        }
    }

    struct Clean: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Delete downloaded installers and scratch files. Cellar fetches them again if it needs them.")

        func run() throws {
            let freed = GameStorage.clean { print("  " + Term.dim($0)) }
            print(Term.green("Freed \(ByteSize.describe(freed)).") + " Games, bottles, saves and sign-ins are untouched.")
        }
    }

    struct Move: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Move a game's files to another drive.")

        @Argument(help: "Profile slug.")
        var slug: String

        @Option(name: .long, help: "A folder on the drive to move it to; Cellar puts it in 'Cellar Games' there.")
        var to: String

        func run() throws {
            let plan = try Game.plan(slug: slug)
            let destination = URL(fileURLWithPath: (to as NSString).expandingTildeInPath, isDirectory: true)
            try GameStorage.move(plan, to: destination) { print("  " + Term.dim($0)) }
            print(Term.green("\(plan.name) moved.") + " It plays and updates from there; keep the drive connected to play it.")
        }
    }

    struct MoveBack: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "move-back",
                                                        abstract: "Bring a moved game back to this Mac.")

        @Argument(help: "Profile slug.")
        var slug: String

        func run() throws {
            let plan = try Game.plan(slug: slug)
            try GameStorage.moveBack(plan) { print("  " + Term.dim($0)) }
        }
    }
}
