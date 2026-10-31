import CellarDomain
import Foundation
import Testing
@testable import CellarKit

/// Whom Cellar thanks, and whether it ships what the licences ask it to.
///
/// Credits drift the moment a runner URL changes and nobody remembers the About screen. These tests
/// tie the credits to the downloads themselves, and the release scripts to the licence texts, so a
/// missing attribution fails here instead of in somebody's inbox. See `docs/LEGAL.md`.
struct CreditsTests {

    /// `github.com/<owner>/...` → `owner`, lowercased.
    private static func githubOwner(_ url: URL) -> String? {
        guard url.host == "github.com" else { return nil }
        return url.pathComponents.dropFirst().first?.lowercased()
    }

    private static var creditedOwners: Set<String> {
        Set(Credits.all.flatMap { [$0.url, $0.sourceURL].compactMap { $0 }.compactMap(githubOwner) })
    }

    @Test("Every publisher Cellar downloads a runner or tool from is credited")
    func downloadsAreCredited() throws {
        let downloads = RunnerCatalog.all.flatMap { $0.artifacts.map(\.url) } + [DepotTool.downloadURL]
        for download in downloads {
            let url = try #require(URL(string: download))
            let owner = try #require(Self.githubOwner(url), "\(download) is not on GitHub — credit it by hand and extend this test")
            #expect(Self.creditedOwners.contains(owner), "\(download) comes from \(owner), whom Credits.all does not name")
        }
    }

    @Test("Every credit names its licence and says what it does")
    func creditsAreComplete() {
        let names = Credits.all.map(\.name)
        #expect(Set(names).count == names.count)
        #expect(Credits.all.first == Credits.wine, "Wine is first: everything Cellar does happens inside it")
        for credit in Credits.all {
            #expect(!credit.role.isEmpty && !credit.license.isEmpty, "\(credit.name)")
            #expect(credit.url.scheme == "https", "\(credit.name)")
        }
    }

    /// Every package in Package.resolved, with the Credit and the licence text that cover it. A new
    /// package fails this until it has a Credit, a row in THIRD_PARTY_LICENSES.md and a text in
    /// licenses/ — and a line here.
    private static let dependencies: [(identity: String, credit: String, text: String)] = [
        ("sparkle", "Sparkle", "Sparkle.txt"),
        ("swift-argument-parser", "swift-argument-parser", "swift-argument-parser.txt"),
    ]

    @Test("Every compiled-in or bundled dependency is credited and its licence text ships")
    func dependenciesAreCovered() throws {
        let resolved = try String(contentsOf: Repo.app.appendingPathComponent("Package.resolved"), encoding: .utf8)
        let identities = resolved.components(separatedBy: "\"identity\" : \"").dropFirst()
            .compactMap { $0.split(separator: "\"").first.map(String.init) }
        #expect(Set(identities) == Set(Self.dependencies.map(\.identity)),
                "a dependency was added or removed: give it a Credit, a row in THIRD_PARTY_LICENSES.md and a text in licenses/")
        let inventory = try String(contentsOf: Repo.root.appendingPathComponent("THIRD_PARTY_LICENSES.md"), encoding: .utf8)
        for dependency in Self.dependencies {
            #expect(Credits.all.contains { $0.name == dependency.credit }, "\(dependency.credit) has no Credit")
            #expect(inventory.contains(dependency.credit), "\(dependency.credit) is not in THIRD_PARTY_LICENSES.md")
            let text = Repo.root.appendingPathComponent("licenses/\(dependency.text)")
            #expect(FileManager.default.fileExists(atPath: text.path), "licenses/\(dependency.text) is missing")
        }
    }

    @Test("Every release artifact carries the licence and notices", arguments: ["package.sh", "install-app.sh"])
    func releaseShipsLegal(_ script: String) throws {
        let body = try String(contentsOf: Repo.app.appendingPathComponent("Scripts/\(script)"), encoding: .utf8)
        for item in ["LICENSE", "NOTICE", "THIRD_PARTY_LICENSES.md", "licenses"] {
            #expect(body.contains(item), "\(script) does not copy \(item) into the release")
        }
    }

    @Test("The DMG carries the licence and notices, in a folder in the install window")
    func dmgShipsLicence() throws {
        let body = try String(contentsOf: Repo.app.appendingPathComponent("Scripts/make-dmg.sh"), encoding: .utf8)
        #expect(body.contains("cp ../LICENSE"))  // the licence sits at the checkout root, beside app/
        #expect(body.contains("cp ../NOTICE"))
        // …and the folder they are in is one of the three things laid out in the window.
        #expect(body.contains("set position of item \"Licence and Read Me\""))
    }
}
