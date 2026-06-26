import ArgumentParser
import CellarKit

struct RunnerCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "runner",
        abstract: "Manage Wine runners (the builds Cellar runs games through).",
        subcommands: [List.self, Install.self]
    )

    struct List: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "List installed and available runners.")

        func run() throws {
            let installed = RunnerManager.installed()
            if installed.isEmpty {
                print(Term.dim("No runners installed. Install one: cellar runner install gptk"))
            } else {
                print(Term.bold("Installed:"))
                for runner in installed {
                    print("  \(Term.green("✓")) \(runner.spec.id)  \(Term.dim(runner.spec.displayName))")
                }
            }
            print("")
            print(Term.bold("Available:"))
            for spec in RunnerCatalog.all {
                let d3d = spec.hasD3DMetal ? Term.cyan(" [D3DMetal]") : ""
                print("  • \(spec.id)\(d3d)  \(Term.dim(spec.displayName))")
            }
        }
    }

    struct Install: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Download & install a Wine runner (default: gptk).")

        @Argument(help: "Runner id: gptk (Wine + D3DMetal) or wine-staging (LGPL).")
        var id: String = "gptk"

        func run() throws {
            guard let spec = RunnerCatalog.spec(forID: id) else {
                let options = RunnerCatalog.all.map(\.id).joined(separator: ", ")
                throw CellarError.invalidArgument("Unknown runner '\(id)'. Options: \(options)")
            }
            print(Term.bold("Installing \(spec.displayName)"))
            print(Term.dim("  license: \(spec.license)"))
            if spec.hasD3DMetal {
                print(Term.dim("  note: includes Apple's D3DMetal (redistributed by Gcenx under Apple's"))
                print(Term.dim("        non-commercial grant). Fetched at runtime; never bundled by Cellar."))
            }
            let install = try RunnerManager.install(spec) { print("  " + Term.dim($0)) }
            let version = WineRunner(binary: install.wineBinary, prefix: Paths.runners).wineVersion()
            print(Term.green("Installed.") + Term.dim("  \(version.isEmpty ? install.wineBinary.lastPathComponent : version)"))
        }
    }
}
