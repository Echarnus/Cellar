import CellarDomain
import ArgumentParser
import CellarData

struct RunnerCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "runner",
        abstract: "Manage Wine runners (the builds Cellar runs games through).",
        subcommands: [List.self, Install.self, Check.self]
    )

    struct List: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "List installed and available runners.")

        func run() throws {
            let installed = RunnerManager.installed()
            if installed.isEmpty {
                print(Term.dim("No runners installed. Install one: cellar runner install \(RunnerCatalog.defaultID)"))
            } else {
                print(Term.bold("Installed:"))
                for runner in installed {
                    let renderers = ["d3dmetal", "dxmt", "dxvk", "d9vk"].filter { runner.renderer($0) != nil }
                    let extra = renderers.isEmpty ? "" : "  renderers: " + renderers.joined(separator: ", ")
                    let archs = runner.measuredArchitectures.joined(separator: "/")
                    let arch = archs.isEmpty ? runner.spec.architecture.rawValue : archs
                    let tag = runner.needsRosetta ? Term.yellow(" [\(arch), Rosetta]") : Term.green(" [\(arch), native]")
                    print("  \(Term.green("✓")) \(runner.spec.id)\(tag)  \(Term.dim(runner.spec.displayName + extra))")
                }
            }
            print("")
            print(Term.bold("Available:"))
            for spec in RunnerCatalog.all {
                let d3d = spec.hasD3DMetal ? Term.cyan(" [D3DMetal]") : ""
                let flag = spec.id == RunnerCatalog.defaultID ? Term.green(" (default)") : ""
                let dep = spec.deprecated.map { Term.yellow(" deprecated: \($0)") } ?? ""
                print("  • \(spec.id)\(d3d)\(flag)  \(Term.dim(spec.displayName))\(dep)")
            }
        }
    }

    struct Install: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Download & install a Wine runner (default: \(RunnerCatalog.defaultID)).")

        @Argument(help: "Runner id: sikarugir (Wine 10 + D3DMetal 3.0, default) or gptk (deprecated).")
        var id: String = RunnerCatalog.defaultID

        func run() throws {
            guard let spec = RunnerCatalog.spec(forID: id) else {
                let options = RunnerCatalog.all.map(\.id).joined(separator: ", ")
                throw CellarError.invalidArgument("Unknown runner '\(id)'. Options: \(options)")
            }
            print(Term.bold("Installing \(spec.displayName)"))
            print(Term.dim("  license: \(spec.license)"))
            if let why = spec.deprecated { print(Term.yellow("  deprecated: \(why)")) }
            if spec.hasD3DMetal {
                print(Term.dim("  note: includes Apple's D3DMetal (redistributed by Gcenx under Apple's"))
                print(Term.dim("        non-commercial grant). Fetched at runtime; never bundled by Cellar."))
            }
            let install = try RunnerManager.install(spec) { print("  " + Term.dim($0)) }
            let version = WineRunner(install: install, prefix: Paths.runners).wineVersion()
            print(Term.green("Installed.") + Term.dim("  \(version.isEmpty ? install.wineBinary.lastPathComponent : version)"))
        }
    }

    /// What Play does before every launch, on demand: check the runner against the checksums
    /// recorded when it was installed, and replace it when it is damaged (`RunnerIntegrity`).
    struct Check: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Check a runner's files and repair it if any are damaged (Play does this by itself).")

        @Argument(help: "Runner id (default: \(RunnerCatalog.defaultID)).")
        var id: String = RunnerCatalog.defaultID

        @Flag(help: "Only report; don't repair.")
        var noRepair = false

        func run() throws {
            guard RunnerCatalog.spec(forID: id) != nil else {
                let options = RunnerCatalog.all.map(\.id).joined(separator: ", ")
                throw CellarError.invalidArgument("Unknown runner '\(id)'. Options: \(options)")
            }
            switch RunnerIntegrity.check(runnerID: id) {
            case nil:
                print(Term.dim("\(id) isn't installed. Install it: cellar runner install \(id)"))
            case .intact?:
                print(Term.green("✓") + " \(id) is intact.")
            case .damaged(let files)?:
                print(Term.yellow("\(id) is damaged: ") + files.joined(separator: ", "))
                guard !noRepair else { throw ExitCode(1) }
                try RunnerIntegrity.ensureIntact(runnerID: id, progress: { print("  " + Term.dim($0)) })
                print(Term.green("✓") + " \(id) is repaired.")
            }
        }
    }
}
