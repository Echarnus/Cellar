import Foundation
import Testing

/// The layering in docs/APP-ARCHITECTURE.md, checked on every run instead of trusted to review.
///
/// SwiftPM already refuses an import of a target that is not declared as a dependency, so these
/// tests guard the rules it cannot see: which *system* frameworks a layer may use, that the app and
/// its UI library never reach the infrastructure, that the engine knows its store adapters only
/// through the port, and that every target stays in Swift 6 mode.
@Suite("Architecture rules")
struct ArchitectureTests {

    /// Every `import` line in a source folder, as (file, module) pairs.
    static func imports(in folder: String) throws -> [(file: String, module: String)] {
        let root = Repo.source(folder)
        let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" } ?? []
        var found: [(file: String, module: String)] = []
        for file in files {
            for line in try String(contentsOf: file, encoding: .utf8).split(separator: "\n") {
                var words = line.split(separator: " ").map(String.init)
                while let first = words.first, first.hasPrefix("@") { words.removeFirst() }
                guard words.first == "import", words.count > 1 else { continue }
                // `import IOKit.hid` is the IOKit module; `import struct Foo.Bar` names Foo.
                let module = (words[1] == "struct" || words[1] == "class" || words[1] == "enum"
                              || words[1] == "func") && words.count > 2 ? words[2] : words[1]
                found.append((file: file.lastPathComponent, module: String(module.split(separator: ".")[0])))
            }
        }
        return found
    }

    /// The source text of every Swift file in a folder.
    static func sources(in folder: String) throws -> [(file: String, text: String)] {
        let root = Repo.source(folder)
        let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" } ?? []
        return try files.map { (file: $0.lastPathComponent, text: try String(contentsOf: $0, encoding: .utf8)) }
    }

    @Test("The domain imports Foundation and nothing else: no I/O framework, no engine")
    func domainIsPure() throws {
        let found = try Self.imports(in: "CellarDomain")
        #expect(!found.isEmpty)
        for (file, module) in found {
            #expect(module == "Foundation", "\(file) imports \(module)")
        }
    }

    /// Importing only Foundation still leaves the disk, processes and the network in reach. The
    /// domain is values and rules; anything that touches the machine belongs to the engine.
    @Test("The domain never touches the disk, a process, the network or the defaults")
    func domainDoesNoIO() throws {
        let io = ["FileManager", "Process(", "URLSession", "UserDefaults", "ProcessInfo", "FileHandle",
                  "Bundle.main", "contentsOf:", "write(to:"]
        for (file, text) in try Self.sources(in: "CellarDomain") {
            for api in io {
                #expect(!text.contains(api), "CellarDomain/\(file) uses \(api)")
            }
        }
    }

    /// The models every layer trades in live in the domain, so a view can name them without the
    /// engine (#133). A type listed here coming back into CellarKit is a layering regression.
    @Test("The shared models are declared in the domain, not the engine",
          arguments: ["CellarError", "CellarCommand", "Credit", "LogCategory", "LogLevel", "ProfileRef",
                      "DockPresence", "GraphicsBackend", "PrefixInfo", "RunnerArchitecture",
                      "RunnerArtifact", "RunnerSpec", "RemovalScope", "Ownership", "CheckResult",
                      "CheckStatus", "DetectedGraphicsAPI", "PerformanceSetting", "GameLanguage",
                      "GameSummary", "GameFacts", "UpdateState", "PlayRecord", "LibraryVerdict",
                      "LibraryQuery", "LibrarySection", "LibrarySnapshot", "SteamSignInState",
                      "LibraryRepository"])
    func modelsLiveInTheDomain(_ type: String) throws {
        func declares(_ folder: String) throws -> Bool {
            try Self.sources(in: folder).contains { $0.file == "\(type).swift" }
        }
        #expect(try declares("CellarDomain"), "\(type) is not in CellarDomain")
        #expect(try !declares("CellarKit"), "\(type) is back in CellarKit")
    }

    @Test("The engine and the infrastructure never import a UI framework",
          arguments: ["CellarKit", "CellarInfrastructure"])
    func engineHasNoUI(_ folder: String) throws {
        for (file, module) in try Self.imports(in: folder) {
            #expect(!["SwiftUI", "AppKit", "CellarUI"].contains(module), "\(folder)/\(file) imports \(module)")
        }
    }

    @Test("The engine never imports the infrastructure that plugs into it")
    func engineDoesNotImportInfrastructure() throws {
        for (file, module) in try Self.imports(in: "CellarKit") {
            #expect(module != "CellarInfrastructure", "CellarKit/\(file) imports CellarInfrastructure")
        }
    }

    @Test("The UI library never imports the infrastructure")
    func uiLibraryDoesNotImportInfrastructure() throws {
        for (file, module) in try Self.imports(in: "CellarUI") {
            #expect(module != "CellarInfrastructure", "CellarUI/\(file) imports CellarInfrastructure")
        }
    }

    @Test("In the app, only the composition root imports the infrastructure: no view or store does")
    func onlyTheAppsRootImportsInfrastructure() throws {
        for (file, module) in try Self.imports(in: "CellarApp") where module == "CellarInfrastructure" {
            #expect(file == "main.swift", "CellarApp/\(file) imports CellarInfrastructure")
        }
    }

    /// Both binaries read store state in-process (the library, a bottle's client), so each must wire
    /// the adapters in before it runs anything. Missing this is a crash at launch that no other
    /// headless test can see, because none of them starts the app.
    @Test("Every entry point wires the store adapters in", arguments: ["cellar/Cellar.swift", "CellarApp/main.swift"])
    func entryPointsInstallInfrastructure(_ path: String) throws {
        let text = try String(contentsOf: Repo.source(path), encoding: .utf8)
        #expect(text.contains("CellarInfrastructure.install()"), "\(path) never calls CellarInfrastructure.install()")
    }

    @Test("The engine knows the store adapters only through the StoreAdapter port")
    func engineNamesNoConcreteAdapter() throws {
        for (file, text) in try Self.sources(in: "CellarKit") {
            for name in ["SteamAdapter", "BattleNetAdapter", "GOGAdapter"] {
                #expect(!text.contains(name), "CellarKit/\(file) names \(name)")
            }
        }
    }

    @Test("A use case asks its adapter, never switches on the store")
    func useCasesDoNotSwitchOnStore() throws {
        for (file, text) in try Self.sources(in: "CellarKit/UseCases") {
            #expect(!text.contains("switch plan.store") && !text.contains("switch store"),
                    "UseCases/\(file) switches on the store")
        }
    }

    @Test("Nothing re-exports a module: every file imports what it uses")
    func noReexports() throws {
        for folder in ["CellarDomain", "CellarKit", "CellarInfrastructure", "CellarUI", "CellarApp", "cellar"] {
            for (file, text) in try Self.sources(in: folder) {
                #expect(!text.contains("@_exported"), "\(folder)/\(file) re-exports a module")
            }
        }
    }

    /// Every target is laid out by feature, one type per file (#133).
    static let oneTypePerFileTargets = ["CellarDomain", "CellarInfrastructure", "CellarUI", "CellarKit",
                                        "CellarApp", "cellar"]

    @Test("One top-level type per file, and the file is named after it", arguments: oneTypePerFileTargets)
    func oneTypePerFile(_ folder: String) throws {
        let modifiers = Set(["public", "package", "internal", "private", "fileprivate", "final",
                             "nonisolated", "indirect", "open"])
        for (file, text) in try Self.sources(in: folder) {
            var names: [String] = []
            for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
                // Top level only: a nested type is indented, a top-level one starts the line.
                guard let first = line.first, first.isLetter || first == "@" else { continue }
                var words = line.split(separator: " ").map(String.init)
                while let word = words.first, modifiers.contains(word) || word.hasPrefix("@") { words.removeFirst() }
                guard words.count > 1, ["struct", "class", "enum", "actor", "protocol"].contains(words[0]) else { continue }
                names.append(String(words[1].prefix { $0.isLetter || $0.isNumber || $0 == "_" }))
            }
            #expect(names.count <= 1, "\(folder)/\(file) declares \(names.count) types: \(names)")
            if let name = names.first {
                #expect(file == "\(name).swift", "\(folder)/\(file) declares \(name); name the file after it")
            } else {
                #expect(file.contains("+") || file == "main.swift",
                        "\(folder)/\(file) declares no type; an extension file is named Type+Topic.swift")
            }
        }
    }

    @Test("Sources are grouped into feature folders, not left flat at the target root",
          arguments: oneTypePerFileTargets)
    func featureFolders(_ folder: String) throws {
        let root = Repo.source(folder)
        let loose = try FileManager.default.contentsOfDirectory(atPath: root.path).filter { $0.hasSuffix(".swift") }
        // Only the entry point (main.swift, or the module's own namespace file) may sit at the root.
        for file in loose {
            #expect(file == "main.swift" || file.lowercased() == "\(folder).swift".lowercased(),
                    "\(folder)/\(file) belongs in a feature folder")
        }
    }

    /// A script that reads a source file by path breaks silently when the file moves: the install
    /// script once read the version from a path that no longer existed and got an empty string.
    @Test("Every Swift source a build script reads by path exists", arguments: ["install-app.sh", "package.sh"])
    func scriptSourcePathsExist(_ script: String) throws {
        let text = try String(contentsOf: Repo.app.appendingPathComponent("Scripts/\(script)"), encoding: .utf8)
        let paths = text.split(whereSeparator: { " \t\n\"'()".contains($0) })
            .map(String.init)
            .filter { $0.hasSuffix(".swift") && $0.contains("/") && !$0.hasPrefix("$") }
        for path in paths {
            #expect(FileManager.default.fileExists(atPath: Repo.app.appendingPathComponent(path).path),
                    "Scripts/\(script) reads \(path), which does not exist")
        }
    }

    @Test("Every target is checked in Swift 6 mode, and UI modules start on the main actor")
    func swift6Everywhere() throws {
        let manifest = try String(contentsOf: Repo.app.appendingPathComponent("Package.swift"), encoding: .utf8)
        #expect(manifest.contains(".defaultIsolation(MainActor.self)"))
        for (name, text) in try Self.manifests() {
            #expect(text.contains("swiftLanguageModes: [.v6]"), "\(name) is not in Swift 6 mode")
            #expect(!text.contains(".swiftLanguageMode(.v5)"), "a target in \(name) opted back out of Swift 6")
            #expect(text.contains("NonisolatedNonsendingByDefault"), "\(name) lacks Approachable Concurrency")
            #expect(text.contains("InferIsolatedConformances"), "\(name) lacks Approachable Concurrency")
        }
        let ui = try #require(try Self.manifests().first { $0.name == "CellarUI" })
        #expect(ui.text.contains(".defaultIsolation(MainActor.self)"), "CellarUI no longer starts on the main actor")
    }

    /// The app shell's manifest and every local package's, by package name.
    static func manifests() throws -> [(name: String, text: String)] {
        var found = [(name: "Cellar", text: try String(contentsOf: Repo.app.appendingPathComponent("Package.swift"), encoding: .utf8))]
        for package in Set(Repo.packageOfLibrary.values).sorted() {
            let url = Repo.app.appendingPathComponent("Packages/\(package)/Package.swift")
            found.append((name: package, text: try String(contentsOf: url, encoding: .utf8)))
        }
        return found
    }

    /// The layers are local packages, so a dependency a package does not declare cannot be imported
    /// at all. This pins what each one may declare: the domain nothing, the engine only the domain,
    /// the UI library only the domain (it learns where store icons are through `StoreArtworkSource`).
    /// A new arrow has to change this test on purpose.
    @Test("Each local package depends only on the layers below it",
          arguments: [("CellarDomain", [String]()), ("CellarKit", ["CellarDomain"]),
                      ("CellarUI", ["CellarDomain"])])
    func packageDependencies(_ package: String, _ allowed: [String]) throws {
        let text = try #require(try Self.manifests().first { $0.name == package }).text
        let declared = text.split(separator: "\n")
            .filter { $0.contains(".package(") }
            .compactMap { line -> String? in
                guard let range = line.range(of: "path: \"../") else { return "remote: \(line)" }
                return String(line[range.upperBound...].prefix { $0 != "\"" })
            }
        #expect(declared.sorted() == allowed.sorted(), "\(package) declares \(declared)")
    }
}
