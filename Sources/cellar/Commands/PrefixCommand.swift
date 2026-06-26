import ArgumentParser
import CellarKit

struct PrefixCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "prefix",
        abstract: "Create and manage Wine bottles (isolated per-game environments).",
        subcommands: [Create.self, List.self, Remove.self]
    )

    struct Create: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Create a new bottle.")

        @Argument(help: "Name of the bottle, e.g. 'pc2'.")
        var name: String

        @Option(help: "Graphics backend: d3dmetal, dxvk, vkd3d, wined3d, dxmt.")
        var backend: String = "d3dmetal"

        @Option(help: "Runner id to use (install one with `cellar runner install`).")
        var runner: String = "default"

        func run() throws {
            guard let backendValue = GraphicsBackend(rawValue: backend) else {
                let options = GraphicsBackend.allCases.map(\.rawValue).joined(separator: ", ")
                throw CellarError.invalidArgument("Unknown backend '\(backend)'. Options: \(options)")
            }
            let info = try PrefixManager.create(name: name, backend: backendValue, runner: runner)
            print(Term.green("Created bottle '\(info.name)'") + " at \(Term.dim(info.url.path))")
            print(Term.dim("  backend=\(info.backend)  runner=\(info.runner)"))
            print("")
            print(Term.yellow("Note:") + " the Wine prefix is initialised in Phase 1, once a runner is installed.")
        }
    }

    struct List: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "List bottles.")

        func run() throws {
            let prefixes = try PrefixManager.list()
            guard !prefixes.isEmpty else {
                print(Term.dim("No bottles yet. Create one with: cellar prefix create <name>"))
                return
            }
            for prefix in prefixes {
                print("  \(Term.bold(prefix.name))  \(Term.dim("backend=\(prefix.backend) runner=\(prefix.runner)"))")
            }
        }
    }

    struct Remove: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Delete a bottle and all its data.")

        @Argument(help: "Name of the bottle to remove.")
        var name: String

        func run() throws {
            try PrefixManager.remove(name: name)
            print(Term.green("Removed bottle '\(name)'."))
        }
    }
}
