import ArgumentParser
import CellarKit

struct RunnerCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "runner",
        abstract: "Manage Wine runners (the LGPL Wine builds Cellar runs games through).",
        subcommands: [List.self, Install.self]
    )

    struct List: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "List installed runners.")

        func run() throws {
            let runners = try RunnerManager.list()
            guard !runners.isEmpty else {
                print(Term.dim("No runners installed. (Phase 1: cellar runner install wine-cx-11)"))
                return
            }
            for runner in runners {
                print("  \(Term.bold(runner.id))  \(Term.dim(runner.url.path))")
            }
        }
    }

    struct Install: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Download & install a Wine runner. [Phase 1]")

        @Argument(help: "Runner id, e.g. 'wine-cx-11'.")
        var id: String

        func run() throws {
            print(Term.yellow("Not yet implemented (Phase 1)."))
            print("""
              Will download a prebuilt, LGPL Wine 11 build (Gcenx wine-crossover) and unpack it to
              \(Paths.runners.appendingPathComponent(id).path)
            """)
        }
    }
}
