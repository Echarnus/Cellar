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
        let root = Repo.root.appendingPathComponent("Sources/\(folder)", isDirectory: true)
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
        let root = Repo.root.appendingPathComponent("Sources/\(folder)", isDirectory: true)
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
        let text = try String(contentsOf: Repo.root.appendingPathComponent("Sources/\(path)"), encoding: .utf8)
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

    @Test("Every target is checked in Swift 6 mode, and UI modules start on the main actor")
    func swift6Everywhere() throws {
        let manifest = try String(contentsOf: Repo.root.appendingPathComponent("Package.swift"), encoding: .utf8)
        #expect(manifest.contains("swiftLanguageModes: [.v6]"))
        #expect(!manifest.contains(".swiftLanguageMode(.v5)"), "a target opted back out of Swift 6")
        #expect(manifest.contains(".defaultIsolation(MainActor.self)"))
        #expect(manifest.contains("NonisolatedNonsendingByDefault"))
        #expect(manifest.contains("InferIsolatedConformances"))
    }
}
